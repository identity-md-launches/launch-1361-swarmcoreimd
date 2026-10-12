// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SwarmCoreIMD (SWARMCORE)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 tokens (18 decimals) is minted
///         once, in the constructor, to the deployer. There is no owner, no minter, no pause, no
///         blacklist, no fee and no burn hook: after deployment the contract has no privileged
///         function of any kind, and the supply can never grow.
/// @dev    The deployer is `msg.sender` at construction. On an IdentityMD custom-token launch that is
///         the ProjectFactory, which then distributes the supply (swarm share, pool seed, remainder)
///         according to the launch manifest. The contract takes no constructor arguments.
///
///         Built on OpenZeppelin Contracts v5.4.0 `ERC20`, which is used unmodified. Transfers,
///         approvals and allowances follow the ERC-20 standard exactly: every transfer moves the full
///         amount requested, transfers to the zero address revert, and `transferFrom` requires a
///         sufficient allowance from the holder.
contract SwarmCoreIMD is ERC20 {
    /// @notice Human-readable token name returned by `name()`.
    string public constant TOKEN_NAME = "SwarmCoreIMD";

    /// @notice Ticker returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "SWARMCORE";

    /// @notice Number of decimals; the same as `decimals()`, exposed as a constant for integrators.
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply in whole tokens, before scaling by `DECIMALS`.
    uint256 public constant SUPPLY_WHOLE_TOKENS = 1_000_000_000;

    /// @notice The fixed total supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = SUPPLY_WHOLE_TOKENS * 10 ** uint256(DECIMALS);

    /// @notice The address that received the entire supply at construction (the deployer).
    address public immutable INITIAL_HOLDER;

    /// @notice Emitted once, when the supply is minted to the deployer.
    /// @param recipient The deployer, which received the whole supply.
    /// @param amount The amount minted, equal to `TOTAL_SUPPLY`.
    event SupplyMinted(address indexed recipient, uint256 amount);

    /// @notice Mints the entire fixed supply to the deployer.
    /// @dev    No arguments, no external calls, no code-size checks: the constructor runs
    ///         identically on an empty chain.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        INITIAL_HOLDER = msg.sender;
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
