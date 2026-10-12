// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCoreIMD} from "src/SwarmCoreIMD.sol";

contract SwarmCoreDeploymentProbe {
    function deploy(bool deterministic, bytes32 salt) external returns (SwarmCoreIMD) {
        return deterministic ? new SwarmCoreIMD{salt: salt}() : new SwarmCoreIMD();
    }
}

/// @dev Supplements the accepted suite with transaction atomicity and allowance lifecycle checks.
/// forge-config: default.fuzz.runs = 1000
contract SwarmCoreIMDEdgeCasesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    SwarmCoreIMD internal token;
    address internal holder = makeAddr("edge holder");
    address internal spender = makeAddr("edge spender");
    address internal recipient = makeAddr("edge recipient");
    address internal outsider = makeAddr("edge outsider");

    function setUp() public {
        vm.prank(holder);
        token = new SwarmCoreIMD();
    }

    function test_factoryReceivesSupplyInsteadOfCallerOrTransactionOrigin() public {
        SwarmCoreDeploymentProbe factory = new SwarmCoreDeploymentProbe();
        for (uint256 i; i < 2; ++i) {
            vm.prank(spender, outsider);
            SwarmCoreIMD fresh = factory.deploy(i == 1, bytes32(i));
            assertEq(fresh.INITIAL_HOLDER(), address(factory));
            assertEq(fresh.balanceOf(address(factory)), SUPPLY);
            assertEq(fresh.balanceOf(spender), 0);
            assertEq(fresh.balanceOf(outsider), 0);
            assertEq(fresh.balanceOf(address(fresh)), 0);
            assertEq(fresh.balanceOf(address(0)), 0);
            assertEq(fresh.totalSupply(), SUPPLY);
        }
    }

    function test_oneWeiRoundTripIsExact() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        _assertInitialBalances();
    }

    // Kept outside the random-call population: a one-way recipient would eventually drain the actors
    // and leave long invariant sequences exercising mostly zero-value transfers.
    function test_transferToTokenItselfDoesNotBurnSupply() public {
        vm.prank(holder);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowanceAndEmitsTransfer() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(outsider);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, outsider), 0);
        _assertInitialBalances();
    }

    function test_fullBalanceSelfTransferEmitsWithoutChangingBalances() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(holder, holder, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(holder, SUPPLY));
        _assertInitialBalances();
    }

    function test_delegatedSelfTransferConsumesFiniteAllowance() public {
        _approve(holder, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, SUPPLY));
        assertEq(token.allowance(holder, spender), 0);
        _assertInitialBalances();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, holder, 1);
        _assertInitialBalances();
    }

    function test_holderCannotUseTransferFromWithoutSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        _assertInitialBalances();

        _approve(holder, holder, 1);
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_maximumFiniteAllowanceIsDecremented() public {
        uint256 allowed = type(uint256).max - 1;
        _approve(holder, spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), allowed - 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_infiniteAllowanceSurvivesFullBalanceSpendAndRefill() public {
        _approve(holder, spender, type(uint256).max);
        for (uint256 i; i < 2; ++i) {
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, recipient, SUPPLY));
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(recipient), SUPPLY);
            assertEq(token.allowance(holder, spender), type(uint256).max);
            vm.prank(recipient);
            assertTrue(token.transfer(holder, SUPPLY));
        }
        _assertInitialBalances();
    }

    function test_revokingInfiniteApprovalBlocksFurtherSpending() public {
        _approve(holder, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Approval(holder, spender, 0);
        _approve(holder, spender, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalDoesNotReserveTokensOrAuthorizeAnotherSpender() public {
        _approve(holder, spender, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY));
        assertEq(token.allowance(holder, spender), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, spender, 1);
        assertEq(token.allowance(holder, spender), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, spender, 1);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_spenderCannotSpendAnotherSpendersApproval() public {
        _approve(holder, spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1));
        vm.prank(outsider);
        token.transferFrom(holder, outsider, 1);
        assertEq(token.allowance(holder, spender), SUPPLY);
        assertEq(token.allowance(holder, outsider), 0);
        _assertInitialBalances();
    }

    function test_maximumTransferFailsWithoutChangingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(holder);
        token.transfer(recipient, type(uint256).max);
        _assertInitialBalances();
    }

    function test_maximumTransferFromFailsWithInfiniteApprovalIntact() public {
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        _assertInitialBalances();
    }

    function test_zeroValueTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(holder);
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        _assertInitialBalances();
    }

    function test_zeroValueApprovalToZeroStillReverts() public {
        _approve(holder, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        assertEq(token.allowance(holder, spender), 1);
        _assertInitialBalances();
    }

    function testFuzz_transferRoundTripRestoresBothHolders(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        _assertInitialBalances();
    }

    function testFuzz_finiteApprovalCannotBeSpentTwice(uint256 amount, uint256 firstSpend) public {
        amount = bound(amount, 1, SUPPLY);
        firstSpend = bound(firstSpend, 0, amount);
        _approve(holder, spender, amount);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(holder, recipient, firstSpend));
        assertEq(token.allowance(holder, spender), amount - firstSpend);
        assertTrue(token.transferFrom(holder, recipient, amount - firstSpend));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(holder, recipient, 1);
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedTransferFromRestoresFiniteAllowance(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        vm.prank(holder);
        token.transfer(recipient, balance);
        _approve(recipient, spender, amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, balance, amount)
        );
        vm.prank(spender);
        token.transferFrom(recipient, outsider, amount);
        assertEq(token.allowance(recipient, spender), amount, "failed transfer consumed approval");
        assertEq(token.balanceOf(recipient), balance);
        assertEq(token.balanceOf(holder), SUPPLY - balance);
        assertEq(token.balanceOf(outsider), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromToZeroRestoresAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 allowed = infinite ? type(uint256).max : amount;
        _approve(holder, spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), allowed);
        _assertInitialBalances();
    }

    function testFuzz_replacingApprovalIsExactAndIsolated(uint256 previous, uint256 replacement) public {
        _approve(holder, outsider, 13);
        _approve(recipient, spender, 17);
        _approve(holder, spender, previous);
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        // Repeating the same approval is idempotent, even at uint256.max.
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(holder, outsider), 13);
        assertEq(token.allowance(recipient, spender), 17);
        assertEq(token.allowance(spender, holder), 0);
        _assertInitialBalances();
    }

    function testFuzz_delegatedSelfTransferPreservesBalance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 allowed = infinite ? type(uint256).max : amount;
        _approve(holder, spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.allowance(holder, spender), infinite ? allowed : 0);
        _assertInitialBalances();
    }

    function _approve(address owner, address approvedSpender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(approvedSpender, amount));
    }

    function _assertInitialBalances() internal view {
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(outsider), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
