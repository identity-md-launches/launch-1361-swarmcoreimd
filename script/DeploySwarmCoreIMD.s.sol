// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SwarmCoreIMD} from "../src/SwarmCoreIMD.sol";

/// @title Deployment script for SwarmCoreIMD
/// @notice Reviewable reference for a plain deployment. The IdentityMD launch does NOT run this
///         script: the ProjectFactory deploys the token from its creation code as built, and the
///         constructor mints the supply to the factory. This script exists so that a reviewer or an
///         operator standing up a test deployment has one documented entry point.
/// @dev    The script reads no environment variables and has no configuration: the token takes no
///         constructor arguments. Whoever broadcasts `run()` becomes the initial holder.
contract DeploySwarmCoreIMD is Script {
    /// @notice Deploys the token. Separated from `run()` so tests can call it directly without
    ///         broadcasting.
    /// @return token The deployed token; the caller of this function holds the whole supply.
    function deploy() public returns (SwarmCoreIMD token) {
        token = new SwarmCoreIMD();
    }

    /// @notice Broadcast entry point for `forge script`. Uses whichever signer forge is given on the
    ///         command line (`--private-key`, `--ledger`, `--account`, ...); nothing is read here.
    function run() external returns (SwarmCoreIMD token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
