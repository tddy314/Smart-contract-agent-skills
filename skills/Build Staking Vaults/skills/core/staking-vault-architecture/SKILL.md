---
name: staking-vault-architecture
description: Use when designing or implementing staking vault architecture in Solidity, including shared vault routers, protocol-specific ERC-4626 vaults, multi-protocol yield integrations, instant and async withdrawals, reward harvesting, fee policy, and security invariants.
---

# Staking Vault Architecture

Use this skill before writing staking vault contracts or materially changing storage, accounting, privilege boundaries, routing, fees, rewards, or asset-flow behavior.

Unless the user explicitly asks for a mock, simulation, or spike, implement real protocol integration paths rather than mock-only architecture.

## Purpose

Design a staking or yield vault system where users interact through one shared router, select a supported protocol vault, and receive shares from that protocol-specific vault.

The first version should use:

- one `VaultRouter` as the common gateway
- registry state stored inside `VaultRouter`
- one or more protocol-specific vaults, usually ERC-4626 for synchronous integrations

Only introduce a separate `VaultRegistry` when governance separation, upgrade separation, or external discovery requirements justify it.

## Core Model

The architecture is:

```text
User
 |
 | deposit / withdraw / redeem / requestRedeem / claimRedeem
 v
VaultRouter
 |
 | validate selected vault, asset, capability, and slippage
 |
 +---------------------+----------------------+-------------------+
 v                     v                      v
AaveUSDCVault4626  AaveWETHVault4626     MorphoUSDCVault4626
shares: aUSDC-V    shares: aWETH-V       shares: mUSDC-V
 |                     |                      |
 v                     v                      v
Aave Protocol       Morpho Protocol       Protocol X
```

Use these defaults unless requirements say otherwise:

- Use one shared `VaultRouter` for all supported protocol vaults.
- Keep the first version minimal: one `VaultRouter` and one or more protocol-specific vaults.
- Keep registry state inside `VaultRouter`.
- Let each vault instance support exactly one underlying asset.
- Let each vault instance issue its own shares.
- Do not create a shared router-level share token by default.
- Let the router validate and forward requests, not own long-term accounting.
- Model withdrawal by capability: instant or async.
- Use immutable deployment unless upgradeability is required.
- Use `SafeERC20` for transfers.
- Reject fee-on-transfer and rebasing underlying tokens unless explicitly supported.
- Use harvest-and-compound as the default external reward policy.

## Required Inputs

Determine these requirements before selecting or implementing the architecture:

- Supported protocol vaults for the first version.
- Which real protocol should be integrated first. Before implementation, confirm the target protocol with the user if it is not already explicit.
- Underlying asset accepted by each protocol vault.
- Whether router usage is an on-chain restriction or just the official product gateway.
- Whether each protocol vault supports instant withdrawal or async request/claim withdrawal.
- External reward token policy.
- Platform fee policy.
- Whether contracts are immutable or upgradeable.
- Administrative controls: pause, vault registration, rescue, harvest, fee configuration, upgrade.
- Unsupported token behaviors: fee-on-transfer, rebasing, ERC777 hooks, non-standard ERC20 return values.
- External integrations: lending pools, vault protocols, DEX routers, reward controllers, or oracles.

If requirements are missing, state assumptions explicitly before proposing contracts.

## Core Rules

The main rules are:

- Each protocol vault has its own share token.
- Each vault instance has exactly one underlying `asset()`.
- Shares from one vault cannot be redeemed from another vault.
- Yield or loss from one vault must not affect another vault.
- `totalAssets()` must reflect actual idle assets plus redeemable protocol position value.
- `totalAssets()` must not include projected APR, estimated future rewards, or unclaimable value.
- The router must not mint or burn protocol vault shares directly.
- The router must not keep user principal after a completed user operation.
- The router must not merge accounting across protocol vaults.

## Main Components

The main state and responsibility split is:

- `VaultRouter`: supported vault registry, capability checks, asset checks, slippage checks, routing.
- protocol vaults: per-asset, per-protocol accounting and protocol interaction logic.
- optional async vault interface for request/claim flows.
- optional abstract base vault only for genuinely shared behavior.

Use a common protocol vault interface and a shared base template only where behavior is truly shared across integrations.

## Read References

Keep `SKILL.md` as the overview. Read the detailed references only when the task needs them.

- For router responsibilities, registry state, protocol vault boundaries, and base vault guidance:
  See [references/router-and-vaults.md](references/router-and-vaults.md)
- For instant and async withdrawal capability design and protocol flows:
  See [references/withdrawal-model.md](references/withdrawal-model.md)
- For share-price accounting, external reward handling, and fee policy:
  See [references/rewards-and-fees.md](references/rewards-and-fees.md)
- For invariants, trust boundaries, and the minimum test plan:
  See [references/security-and-testing.md](references/security-and-testing.md)
- For contract test strategy and A/B evaluation of skill-vs-no-skill performance:
  See [references/skill-evaluation.md](references/skill-evaluation.md)

## Contract Layout

Use this baseline layout:

```text
contracts/
+-- gateway/
|   `-- VaultRouter.sol
+-- vaults/
|   +-- BaseProtocolVault4626.sol
|   +-- AaveUSDCVault4626.sol
|   +-- AaveWETHVault4626.sol
|   `-- MorphoUSDCVault4626.sol
+-- interfaces/
|   +-- IProtocolVault.sol
|   +-- IAsyncProtocolVault.sol
|   `-- IVaultRouter.sol
`-- mocks/
```

Add `VaultRegistry.sol` only when registry separation is justified.

## Required Design Output

Before implementation, produce a design brief with:

1. Supported protocol vaults for the first version.
2. Asset supported by each protocol vault.
3. Router responsibilities and registry state stored inside the router.
4. Vault id and lookup convention, such as `keccak256("AAVE-USDC")`.
5. Vault capability table.
6. Contract/file map.
7. Deposit flow.
8. Instant withdrawal flow.
9. Async withdrawal flow, if required.
10. ERC-4626 share model.
11. External reward harvest-and-compound policy.
12. Fee model.
13. Administrative roles and trust assumptions.
14. Security invariants.
15. Test plan mapped to invariants.
16. Unresolved design decisions that block implementation.

## Stop Conditions

Do not implement contracts until these are clear:

- Which protocol vaults are supported first.
- Which protocol should be integrated first if implementation is expected.
- Which asset each protocol vault accepts.
- Whether router access is a product convention or an on-chain restriction.
- Whether each protocol vault supports instant or async withdrawal.
- How external reward tokens are harvested, swapped, and compounded.
- Which platform fees are enabled.
- Whether vaults are immutable or upgradeable.
- Which admin roles can register vaults, pause flows, harvest rewards, configure fees, rescue tokens, or upgrade contracts.
