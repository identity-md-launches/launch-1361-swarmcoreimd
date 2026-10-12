// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCoreIMD} from "src/SwarmCoreIMD.sol";

/// @dev Closed population of four callers keeps value circulating throughout long sequences.
/// Ghost accounting starts from the specified issuance and changes only from successful call inputs;
/// it never copies balances or allowances back out of the token. No deal/store cheats alter token state.
contract SwarmCoreIMDHandler is Test {
    SwarmCoreIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    constructor(SwarmCoreIMD token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        ghostBalance[actors_[0]] = 1_000_000_000 * 1e18;
    }

    function transfer(uint256 ownerSeed, uint256 recipientSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        address recipient = _actor(recipientSeed);
        uint256 amount = bound(rawAmount, 0, ghostBalance[owner]);
        _transfer(owner, recipient, amount);
    }

    function transferAll(uint256 ownerSeed, uint256 recipientSeed) external {
        address owner = _actor(ownerSeed);
        _transfer(owner, _actor(recipientSeed), ghostBalance[owner]);
    }

    // All uint256 values are valid approvals, including values above the entire token supply.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function approveInfinite(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), 0);
    }

    // Uses approvals left by earlier calls; it does not create an approval to make this call succeed.
    // Owner, spender and recipient may coincide, exercising self-approval and delegated self-transfers.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 limit = ghostBalance[owner] < allowed ? ghostBalance[owner] : allowed;
        uint256 amount = bound(rawAmount, 0, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount), "valid delegated transfer returned false");
        _recordTransfer(owner, recipient, amount);
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
    }

    function rejectTransferOverBalance(uint256 ownerSeed, uint256 recipientSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        address recipient = _actor(recipientSeed);
        uint256 balance = ghostBalance[owner];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(owner);
        token.transfer(recipient, amount);
        // Ghost state deliberately remains unchanged after every rejected call.
    }

    function rejectTransferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 rawAmount
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        uint256 balance = ghostBalance[owner];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max - 1);
        // A finite, sufficient allowance reaches the balance check. Its attempted consumption must roll back.
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }

    function rejectTransferFromOverAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 rawAmount
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor(recipientSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        // An infinite approval cannot be exceeded, so revoke it through the real public API first.
        if (allowed == type(uint256).max) {
            _approve(owner, spender, 0);
            allowed = 0;
        }
        uint256 amount = bound(rawAmount, allowed + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = ghostBalance[owner];
        if (delegated && ghostAllowance[owner][spender] < limit) limit = ghostAllowance[owner][spender];
        uint256 amount = bound(rawAmount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _transfer(address owner, address recipient, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount), "valid transfer returned false");
        _recordTransfer(owner, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        ghostAllowance[owner][spender] = amount;
    }

    function _recordTransfer(address owner, address recipient, uint256 amount) internal {
        // Sequential writes also describe a self-transfer correctly: its net balance change is zero.
        ghostBalance[owner] -= amount;
        ghostBalance[recipient] += amount;
    }
}
