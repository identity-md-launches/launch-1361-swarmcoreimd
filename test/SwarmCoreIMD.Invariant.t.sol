// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwarmCoreIMD} from "src/SwarmCoreIMD.sol";
import {SwarmCoreIMDHandler} from "./handlers/SwarmCoreIMDHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmCoreIMDInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    SwarmCoreIMD internal token;
    SwarmCoreIMDHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        actors = [
            makeAddr("sequence deployer"),
            makeAddr("sequence alice"),
            makeAddr("sequence bob"),
            makeAddr("sequence carol")
        ];
        vm.prank(actors[0]);
        token = new SwarmCoreIMD();
        handler = new SwarmCoreIMDHandler(token, actors);

        // Establish several funded holders, an empty holder, and both kinds of live allowance.
        // All funding goes through ordinary transfers and the same ghost accounting as fuzzed calls.
        handler.transfer(0, 1, SUPPLY / 4);
        handler.transfer(0, 2, SUPPLY / 4);
        handler.approve(0, 3, SUPPLY / 2);
        handler.approve(1, 2, SUPPLY / 8);
        handler.approveInfinite(2, 1);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.approveInfinite.selector;
        selectors[4] = handler.revoke.selector;
        selectors[5] = handler.transferFrom.selector;
        selectors[6] = handler.rejectTransferOverBalance.selector;
        selectors[7] = handler.rejectTransferFromOverBalance.selector;
        selectors[8] = handler.rejectTransferFromOverAllowance.selector;
        selectors[9] = handler.rejectZeroReceiver.selector;
        selectors[10] = handler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyAndEveryBalanceMatchTheLedger() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply changed after construction");
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 actual = token.balanceOf(actors[i]);
            assertEq(actual, handler.ghostBalance(actors[i]), "holder balance diverged from transfer ledger");
            sum += actual;
        }
        assertEq(sum, SUPPLY, "sum of all balances differs from issuance");
        assertEq(token.balanceOf(address(token)), 0, "token collected an unexpected fee");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(handler)), 0, "handler received tokens unexpectedly");
        assertEq(token.INITIAL_HOLDER(), actors[0], "initial holder changed");
    }

    function invariant_everyAllowanceMatchesApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance changed without its owner's approval or a successful spend"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    // Pin a meaningful multi-step trace so the handler cannot quietly become a collection of no-ops.
    function test_handlerExercisesPartialSpendingRevocationAndRollback() public {
        uint256 initial = SUPPLY / 4;
        handler.transfer(1, 3, 100);
        handler.approve(3, 2, 40);
        handler.transferFrom(3, 2, 1, 25);
        assertEq(token.balanceOf(actors[3]), 75);
        assertEq(token.balanceOf(actors[1]), initial - 75);
        assertEq(token.allowance(actors[3], actors[2]), 15);
        handler.rejectTransferOverBalance(3, 1, 76);
        handler.rejectTransferFromOverAllowance(3, 2, 1, 16);
        handler.rejectZeroReceiver(3, 2, 10, true);
        handler.rejectZeroReceiver(3, 2, 10, false);
        handler.rejectZeroSpender(3, type(uint256).max);
        handler.revoke(3, 2);
        handler.rejectTransferFromOverAllowance(3, 2, 1, 1);
        handler.rejectTransferFromOverBalance(3, 2, 1, 76);
        assertEq(token.allowance(actors[3], actors[2]), 76, "revert failed to restore finite approval");
        handler.transferFrom(3, 2, 1, 75);
        assertEq(token.balanceOf(actors[3]), 0);
        assertEq(token.balanceOf(actors[1]), initial);
        assertEq(token.allowance(actors[3], actors[2]), 1);
        invariant_fixedSupplyAndEveryBalanceMatchTheLedger();
        invariant_everyAllowanceMatchesApprovalsAndSuccessfulSpends();
    }

    function test_handlerExercisesInfiniteSelfTransfersAndFullBalanceRoundTrip() public {
        handler.approveInfinite(0, 1);
        handler.transferFrom(0, 1, 0, SUPPLY / 2);
        assertEq(token.balanceOf(actors[0]), SUPPLY / 2);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max);
        handler.transferFrom(0, 1, 3, SUPPLY / 2);
        assertEq(token.balanceOf(actors[0]), 0);
        assertEq(token.balanceOf(actors[3]), SUPPLY / 2);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max);
        handler.rejectTransferFromOverAllowance(0, 1, 3, 1);
        assertEq(token.allowance(actors[0], actors[1]), 0);
        handler.transferAll(3, 0);
        assertEq(token.balanceOf(actors[0]), SUPPLY / 2);
        assertEq(token.balanceOf(actors[3]), 0);
        invariant_fixedSupplyAndEveryBalanceMatchTheLedger();
        invariant_everyAllowanceMatchesApprovalsAndSuccessfulSpends();
    }
}
