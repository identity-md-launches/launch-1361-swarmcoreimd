// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCoreIMD} from "../src/SwarmCoreIMD.sol";
import {DeploySwarmCoreIMD} from "../script/DeploySwarmCoreIMD.s.sol";

contract SwarmCoreIMDTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 1e18;

    /// @dev Stands in for the ProjectFactory: the address that deploys and therefore holds the supply.
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    SwarmCoreIMD internal token;

    event SupplyMinted(address indexed recipient, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        token = new SwarmCoreIMD();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "SwarmCoreIMD");
        assertEq(token.symbol(), "SWARMCORE");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "SwarmCoreIMD");
        assertEq(token.TOKEN_SYMBOL(), "SWARMCORE");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstantsAgree() public view {
        assertEq(token.SUPPLY_WHOLE_TOKENS(), 1_000_000_000);
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), token.SUPPLY_WHOLE_TOKENS() * 10 ** token.decimals());
    }

    // ---------------------------------------------------------------------------------------------
    // Constructor: the whole supply, once, to the deployer
    // ---------------------------------------------------------------------------------------------

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "total supply");
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY, "deployer balance");
        assertEq(token.INITIAL_HOLDER(), deployer, "initial holder");
    }

    function test_constructorEmitsMintEvents() public {
        address factory = makeAddr("factory");
        // Transfer(0x0, factory, supply) from OpenZeppelin's _mint, then our SupplyMinted.
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), factory, EXPECTED_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(factory, EXPECTED_SUPPLY);
        vm.prank(factory);
        new SwarmCoreIMD();
    }

    function test_deployerIsWhoeverCallsTheConstructor() public {
        address factory = makeAddr("factory");
        vm.prank(factory);
        SwarmCoreIMD fresh = new SwarmCoreIMD();
        assertEq(fresh.balanceOf(factory), EXPECTED_SUPPLY);
        assertEq(fresh.balanceOf(deployer), 0);
        assertEq(fresh.INITIAL_HOLDER(), factory);
    }

    function test_constructorTakesNoArgumentsAndRunsOnAnEmptyChain() public {
        // Deploy raw creation code with no appended arguments through CREATE2 from an address with
        // no other code around it, the way the launch factory does.
        bytes memory code = type(SwarmCoreIMD).creationCode;
        address at;
        vm.prank(deployer);
        assembly ("memory-safe") {
            at := create2(0, add(code, 32), mload(code), 0x1234)
        }
        assertTrue(at != address(0), "create2 failed");
        assertGt(at.code.length, 0, "no runtime");
        assertEq(SwarmCoreIMD(at).balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(SwarmCoreIMD(at).totalSupply(), EXPECTED_SUPPLY);
    }

    function test_deployScriptMintsToItsCaller() public {
        DeploySwarmCoreIMD script = new DeploySwarmCoreIMD();
        SwarmCoreIMD deployed = script.deploy();
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(address(script)), EXPECTED_SUPPLY);
        assertEq(deployed.name(), "SwarmCoreIMD");
        assertEq(deployed.symbol(), "SWARMCORE");
    }

    // ---------------------------------------------------------------------------------------------
    // Transfers: success paths
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        uint256 amount = 1_000e18;
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, EXPECTED_SUPPLY));
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5e18));
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_secondaryTransfersAreUntaxed() public {
        uint256 amount = 123_456e18;
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(bob), amount, "bob received short");
        assertEq(token.balanceOf(alice), 0, "alice kept something");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_approveAndTransferFrom() public {
        uint256 amount = 10e18;
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.approve(alice, amount));
        assertEq(token.allowance(deployer, alice), amount);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, bob, amount);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, amount));
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        assertEq(token.allowance(deployer, alice), 0, "allowance not consumed");
    }

    function test_transferFromPartialAllowanceDecrements() public {
        vm.prank(deployer);
        token.approve(alice, 10e18);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 4e18);
        assertEq(token.allowance(deployer, alice), 6e18);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1e18);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 10e18);
        token.approve(alice, 3e18);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 3e18);
    }

    // ---------------------------------------------------------------------------------------------
    // Transfers: failure paths
    // ---------------------------------------------------------------------------------------------

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1e18, 1e18 + 1));
        vm.prank(alice);
        token.transfer(bob, 1e18 + 1);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transfer(bob, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transferFrom(deployer, stranger, 1);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 5e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 5e18, 5e18 + 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 5e18 + 1);
    }

    function test_RevertWhen_transferFromExceedsBalanceDespiteAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 1e18);
        vm.prank(alice);
        token.approve(bob, 100e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1e18, 2e18));
        vm.prank(bob);
        token.transferFrom(alice, bob, 2e18);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged surface: nothing mints, pauses, freezes or seizes
    // ---------------------------------------------------------------------------------------------

    function test_noAdminCallIncreasesSupplyOrCreditsCaller() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], stranger, type(uint128).max);
            vm.prank(stranger);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpectedly accepted from stranger: ", signatures[i]));
            vm.prank(deployer);
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpectedly accepted from deployer: ", signatures[i]));
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
            assertEq(token.balanceOf(stranger), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        uint256 held = EXPECTED_SUPPLY / 1_000;
        vm.prank(deployer);
        token.transfer(alice, held);

        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpectedly accepted: ", signatures[i]));
        }
        // The deployer has no allowance, so it cannot pull from a holder either.
        vm.prank(deployer);
        (bool moved,) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, alice, deployer, 1));
        assertFalse(moved, "deployer pulled from a holder without allowance");

        assertEq(token.balanceOf(alice), held, "holder balance changed");
        vm.prank(alice);
        assertTrue(token.transfer(bob, held / 2), "holder can no longer transfer");
        assertEq(token.balanceOf(bob), held / 2);
    }

    function test_unknownSelectorsAndPlainValueAreRejected() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "unknown selector accepted");
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token accepted ETH");
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Launch flows: every leg of the distribution moves exactly what it says
    // ---------------------------------------------------------------------------------------------

    function test_launchDistributionArrivesWhole() public {
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("poolManager");
        address remainderTo = makeAddr("remainderTo");
        address claimant = makeAddr("claimant");

        uint256 swarm = (EXPECTED_SUPPLY * 1_000) / 10_000; // 10%
        uint256 pool = (EXPECTED_SUPPLY * 8_000) / 10_000; // 80%
        uint256 remainder = EXPECTED_SUPPLY - swarm - pool; // 10%

        vm.startPrank(deployer);
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(poolManager, pool));
        assertTrue(token.transfer(remainderTo, remainder));
        vm.stopPrank();

        assertEq(token.balanceOf(distributor), swarm, "swarm share short");
        assertEq(token.balanceOf(poolManager), pool, "pool seed short");
        assertEq(token.balanceOf(remainderTo), remainder, "remainder short");
        assertEq(token.balanceOf(deployer), 0, "factory kept something");

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm, "claim short");
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "launch flows changed the supply");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: conservation of supply
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer) + token.balanceOf(to), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferFromConservesSupply(address spender, address to, uint256 allowed, uint256 amount) public {
        vm.assume(spender != address(0) && to != address(0) && to != deployer);
        allowed = bound(allowed, 0, EXPECTED_SUPPLY);
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);
        vm.prank(spender);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
            token.transferFrom(deployer, to, amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertTrue(token.transferFrom(deployer, to, amount));
            assertEq(token.balanceOf(to), amount);
            assertEq(token.allowance(deployer, spender), allowed - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_overdraftAlwaysReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, EXPECTED_SUPPLY - 1);
        excess = bound(excess, 1, EXPECTED_SUPPLY - held);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, held + excess)
        );
        vm.prank(alice);
        token.transfer(bob, held + excess);
    }

    // ---------------------------------------------------------------------------------------------
    // Bytecode properties the launch requires
    // ---------------------------------------------------------------------------------------------

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    function test_contractNameFitsTheManifest() public pure {
        // The launch records the Solidity identifier as bytes32.
        assertLe(bytes("SwarmCoreIMD").length, 32);
    }
}
