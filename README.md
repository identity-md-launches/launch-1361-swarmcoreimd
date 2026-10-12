# SwarmCoreIMD (SWARMCORE)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum mainnet.

| Property          | Value                                                        |
| ----------------- | ------------------------------------------------------------ |
| Solidity contract | `SwarmCoreIMD` (`src/SwarmCoreIMD.sol`)                      |
| `name()`          | `SwarmCoreIMD`                                               |
| `symbol()`        | `SWARMCORE`                                                  |
| `decimals()`      | 18                                                           |
| `totalSupply()`   | 1,000,000,000 tokens = `1000000000000000000000000000` minor units |
| Constructor args  | none                                                         |
| Minting           | once, in the constructor, the whole supply to `msg.sender`   |
| Owner / admin     | none                                                         |
| Compiler          | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |
| Base library      | OpenZeppelin Contracts v5.4.0 `ERC20`, vendored unmodified   |

## Behaviour

- The constructor mints `TOTAL_SUPPLY` to the deployer and emits `Transfer(0x0, deployer, supply)`
  followed by `SupplyMinted(deployer, supply)`. `INITIAL_HOLDER` records the deployer.
- There is no `mint`, `burn`, `pause`, blacklist, freeze, fee, reflection, vesting or ownership
  function. The supply can never grow, and no address can move or lock another holder's balance.
- Transfers, approvals and `transferFrom` are standard ERC-20 (OpenZeppelin v5 semantics):
  - every transfer moves exactly the amount requested, with no tax or burn;
  - transfers to the zero address revert with `ERC20InvalidReceiver`;
  - overdrafts revert with `ERC20InsufficientBalance`;
  - `transferFrom` beyond the allowance reverts with `ERC20InsufficientAllowance`;
  - an allowance of `type(uint256).max` is treated as infinite and is not decremented;
  - `approve(address(0), …)` reverts with `ERC20InvalidSpender`.
- The contract holds no ETH and has no `receive` or `fallback`; calls with value or unknown
  selectors revert.
- The runtime bytecode contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, and no linked
  library placeholders (every library call is internal and inlined).

## Assumptions

- **The deployer is the ProjectFactory.** On the IdentityMD launch the factory deploys the token
  from its creation code and receives the whole supply. The token exempts nobody and taxes nobody,
  so the factory's three launch flows (10% to the MerkleDistributor, 80% to seed the Uniswap v4
  pool, 10% to `economics.remainderTo`) each move exactly the amount sent. The launch's actual
  figures (pool share, opening market cap, remainder address) are the requester's `economics` and
  are copied into `launch.json` by the manifest step, not by this repository.
- **No constructor arguments.** The manifest's `constructorArgs` for the token is an empty list.
  The constructor makes no external calls and does not require any address to have code, so it
  runs identically on an empty chain.
- **Pair, fee, tick spacing and price** are the launch's (IMD at
  `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, fee 12500, tick spacing 60) and are not encoded in
  the token.
- **No owner.** The brief asked for a plain token, so there is nothing for an owner to configure.
  Nothing is read from the environment anywhere in the contracts, script or tests.

## Deployment parameters

The launch deploys `SwarmCoreIMD` from its bytecode as built with the pinned configuration in
`foundry.toml`. Nothing is configurable at deployment. For a manual or test deployment,
`script/DeploySwarmCoreIMD.s.sol` exposes `deploy()` (callable from tests, returns the token) and
`run()` (broadcasts `deploy()` with whichever signer `forge script` is given). The script reads no
environment variables. Whoever broadcasts becomes the initial holder of the entire supply.

```sh
forge build
forge test
forge fmt --check
# Reference only; the IdentityMD launch does not run this.
forge script script/DeploySwarmCoreIMD.s.sol --rpc-url <RPC> --account <KEYSTORE> --broadcast
```

## After launch

There are no owner-settable values and no post-launch configuration steps. The token is complete
at construction.

## Operational responsibilities

- **Supply custody.** Immediately after deployment the deployer holds 100% of the supply. On the
  launch this is the factory, which pays everything out. Anyone deploying this token outside the
  launch is responsible for distributing the supply they receive; the contract cannot do it for them.
- **No recovery path.** There is no admin, upgrade or pause. Tokens sent to a wrong address or to
  a contract that cannot use them are irrecoverable by design. Tokens sent to the token contract's
  own address are likewise stuck.
- **Approvals.** Holders should approve exact amounts to spenders they trust; an infinite
  allowance is honoured and never decremented.
- **Explorer verification.** Verifying the source on Etherscan after the launch
  (`forge verify-contract` with `--compiler-version 0.8.26`, optimizer 200 runs, no constructor
  args) is the deployer's/launch operator's task, not this repository's.
- **Audit status.** The tests in `test/` pass but are not a security audit. The token itself is an
  unmodified OpenZeppelin v5.4.0 `ERC20` with a constructor mint; the attack surface is the
  standard one. An independent adversarial review is still recommended before release.

## Repository layout

```
foundry.toml                       compiler pins, bytecode_hash = "none", remappings, no ffi/fs
src/SwarmCoreIMD.sol               the token
script/DeploySwarmCoreIMD.s.sol    reference deployment script (deploy() is unit-tested)
test/SwarmCoreIMD.t.sol            success, failure, fuzz, launch-flow and bytecode tests
lib/forge-std                      forge-std v1.9.7, vendored as plain files (src + licences)
lib/openzeppelin-contracts         OpenZeppelin Contracts v5.4.0, vendored as plain files (contracts + licence)
```

Dependencies are committed as ordinary files, not submodules, so the project builds offline.
