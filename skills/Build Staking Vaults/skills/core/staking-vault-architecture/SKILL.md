---
name: staking-vault-architecture
description: Use when designing staking vault architecture, vault routers, protocol-specific ERC-4626 vaults, multi-protocol yield integrations, withdrawal capabilities, reward harvesting, fee models, and security invariants.
version: 0.1.0
---

# Staking Vault Architecture

Use this skill before writing staking vault contracts or materially changing their storage, accounting, privilege, routing, fee, reward, or asset-flow behavior.

## Purpose

Design a staking/yield vault system where users interact through one shared gateway router, choose any supported protocol vault, and receive shares from that protocol-specific ERC-4626 vault.

The system should have one `VaultRouter` as the common gateway for all supported protocol vaults. The first version should keep registry state inside this router. A separate `VaultRegistry` contract is optional and should only be introduced when governance separation, upgrade separation, or external discovery requirements justify it.

## Core Architecture

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

## Required Inputs

Determine these requirements before selecting or implementing the architecture:

- Supported protocol vaults for the first version.
- Underlying asset accepted by each protocol vault.
- Whether router usage is an on-chain restriction or the official user-facing gateway.
- Whether each protocol vault supports instant withdrawal or async request/claim withdrawal.
- External reward token policy.
- Platform fee policy.
- Whether contracts are immutable or upgradeable.
- Administrative controls: pause, vault registration, rescue, harvest, fee configuration, upgrade.
- Unsupported token behaviors: fee-on-transfer, rebasing, ERC777 hooks, non-standard ERC20 return values.
- External integrations: lending pools, vault protocols, DEX routers, reward controllers, or oracles.

If requirements are missing, state assumptions explicitly before proposing contracts.

## Architecture Defaults

Use these defaults unless the requirements demand otherwise:

- Use one shared `VaultRouter` for all supported protocol vaults.
- Keep the first version minimal: one `VaultRouter` and one or more protocol-specific ERC-4626 vaults.
- Keep registry state inside `VaultRouter` for the first version.
- A single external protocol may have multiple vault instances.
- Each vault instance supports exactly one underlying asset.
- Each vault instance issues its own ERC-4626 shares.
- Do not make a single ERC-4626 vault accept multiple unrelated underlying assets.
- Do not issue a shared router-level share token by default.
- The router validates and forwards requests; it must not own long-term accounting, calculate yield, or hold user funds after a completed operation.
- The router tracks supported vaults, underlying assets, protocol identifiers, active status, and withdrawal capabilities.
- Use a common protocol vault interface and an abstract base template only for behavior that is truly shared across integrations.
- Model withdrawals by capability: instant withdrawal when the external protocol can return assets in the same transaction, async request/claim flow when it cannot.
- Use immutable deployment unless upgradeability is required.
- Use explicit user-initiated `deposit`, `withdraw`, `redeem`, `requestRedeem`, and `claimRedeem` actions as applicable.
- Use OpenZeppelin `ERC4626` as the default base implementation for synchronous protocol vaults.
- Use `SafeERC20` for all ERC20 transfers.
- Reject fee-on-transfer and rebasing underlying tokens unless the vault accounting model explicitly supports them.
- Use `HarvestAndCompound` as the default external reward policy.
- Keep principal withdrawal available when technically safe, even if deposits, harvesting, or reward handling are paused.
- Keep privileged roles minimal and distinct only where operational separation is required.
- Emit events for user asset movements and every privileged state change.

## Contract Responsibilities

### VaultRouter

The router is the single user-facing gateway for all supported protocol vault interactions. Users call the same router to deposit into, withdraw from, redeem from, or request async withdrawal from any supported protocol vault.

The first version should also store registry metadata inside the router, so the router can decide which protocol vaults are supported and how each vault can be used.

Execution responsibilities:

- Route user deposits, withdrawals, redeems, async requests, and async claims to the user-selected protocol vault.
- Validate that the target vault is supported and active.
- Validate that the input asset matches the selected vault.
- Validate the target vault capability before calling instant or async withdrawal flows.
- Enforce user protection parameters such as `minSharesOut`, `minAssetsOut`, and `maxAssetsIn`.
- Emit routing-level events for analytics and integrations.

Registry responsibilities:

- Track supported protocol vaults.
- Track each vault's underlying asset.
- Track each vault's protocol identifier.
- Track each vault instance identifier.
- Track whether each vault is active or disabled.
- Track each vault's withdrawal capability flags.

Non-responsibilities:

- Must not mint or burn protocol vault shares directly.
- Must not own protocol vault accounting.
- Must not calculate protocol yield or share price.
- Must not retain user principal after a completed operation.
- Must not merge accounting across protocol vaults.

Implementation note:

- The router may transfer assets into the selected vault or use an allowance-based vault pull flow.
- In either case, the router must not retain user assets after the operation completes.

Example router registry state:

```solidity
struct VaultInfo {
    address asset;
    bytes32 protocolId;
    bytes32 vaultId;
    uint256 capabilities;
    bool active;
}

mapping(address vault => VaultInfo info) public vaults;
mapping(bytes32 vaultId => address vault) public vaultById;
mapping(bytes32 protocolId => address[] vaults) public vaultsByProtocol;
mapping(address asset => address[] vaults) public vaultsByAsset;
```

### Protocol Vault Contracts

Each integrated protocol/asset pair should have its own protocol vault instance. A protocol vault contains the logic required to deposit into, withdraw from, and account for one underlying asset position in one external protocol, such as Aave, Morpho, Compound, or another yield source.

Each protocol vault should:

- Support only its explicitly configured underlying asset.
- Support exactly one underlying asset per vault instance.
- Issue its own ERC-4626 shares for that vault instance.
- Own its own accounting, share price, `totalAssets()`, and protocol interaction logic.
- Define whether withdrawals are instant or require an async request/claim flow.
- Expose a common interface so the router can interact with different protocol vaults consistently.
- Use OpenZeppelin `ERC4626` as the default base implementation for synchronous vault behavior.

One external protocol can have multiple vault instances:

```text
AaveUSDCVault4626   -> asset: USDC -> shares: aaveUSDC shares
AaveWETHVault4626   -> asset: WETH -> shares: aaveWETH shares
MorphoUSDCVault4626 -> asset: USDC -> shares: morphoUSDC shares
```

The vault address is the canonical unique key. Use `vaultId` only for lookup and readability, such as `keccak256("AAVE-USDC")`.

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

Add a separate `VaultRegistry.sol` only when registry separation is justified by governance separation, upgrade separation, or external discovery requirements.

## ERC-4626 Share Model

Rules:

- Each protocol vault has its own share token.
- Each ERC-4626 vault instance has exactly one `asset()` underlying token.
- Shares from one protocol vault cannot be redeemed from another protocol vault.
- Yield or loss from one protocol vault must not affect another protocol vault.
- `totalAssets()` must reflect actual idle assets plus redeemable protocol position value.
- `totalAssets()` must not include projected APR, estimated future rewards, or unclaimable value.
- The router must not issue a shared vault token unless the architecture explicitly changes into a meta-vault.

## Base Vault Template

Use an abstract template only for genuinely shared behavior.

```solidity
abstract contract BaseProtocolVault4626 is ERC4626 {
    function _supplyToProtocol(uint256 assets) internal virtual;

    function _withdrawFromProtocol(uint256 assets, address receiver)
        internal
        virtual
        returns (uint256);

    function _protocolTotalAssets() internal view virtual returns (uint256);

    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _protocolTotalAssets();
    }
}
```

Rules:

- Keep protocol-specific assumptions in concrete vaults.
- Do not force every protocol into the same internal mechanics.
- Do not force async protocols into synchronous ERC-4626 withdrawal semantics.

## Withdrawal Capability Model

Vaults can support different withdrawal behavior.

| Capability | Meaning |
|---|---|
| `INSTANT_WITHDRAWAL` | Assets can be returned in the same transaction |
| `ASYNC_WITHDRAWAL` | User must request withdrawal and claim later |
| `PAUSABLE_DEPOSIT` | Deposits can be paused independently |
| `PAUSABLE_WITHDRAWAL` | Withdrawals can be paused only when technically necessary |

Async vaults should expose a separate interface:

```solidity
interface IAsyncProtocolVault {
    function requestRedeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 requestId);

    function claimRedeem(uint256 requestId, address receiver)
        external
        returns (uint256 assets);

    function isClaimable(uint256 requestId) external view returns (bool);
}
```

## Protocol Flows

### Deposit

```text
User -> VaultRouter.depositToVault()
Router: validate vault, asset, active status, minSharesOut
Router -> ProtocolVault.deposit()
ProtocolVault -> External Protocol: supply assets
ProtocolVault -> User: mint protocol vault shares
```

Required checks:

- Vault is active.
- Asset matches the selected vault.
- Minted shares are at least `minSharesOut`.
- Router does not retain user funds.

### Instant Withdraw

```text
User -> VaultRouter.withdrawFromVault()
Router: validate instant withdrawal capability and minAssetsOut
Router -> ProtocolVault.withdraw()
ProtocolVault -> External Protocol: withdraw assets
ProtocolVault -> User: transfer assets
ProtocolVault: burn shares
```

Required checks:

- Vault supports instant withdrawal.
- `maxWithdraw(user)` is sufficient.
- Returned assets are at least `minAssetsOut`.

### Async Withdraw

```text
User -> VaultRouter.requestRedeem()
Router: validate async withdrawal capability
Router -> AsyncProtocolVault.requestRedeem()
AsyncProtocolVault: record withdrawal request

Later:
User -> VaultRouter.claimRedeem()
Router -> AsyncProtocolVault.claimRedeem()
AsyncProtocolVault -> User: transfer assets
```

Required checks:

- Request owner is validated.
- Request cannot be claimed twice.
- Claimable state is externally observable.

## Reward And Yield Accounting

The default reward model is ERC-4626 share-price based accounting.

Each protocol vault should treat yield as an increase in `totalAssets()`. Users do not receive a separate reward balance by default. Instead, users realize yield when they redeem or withdraw their vault shares.

### Share-Price Yield Model

```text
User deposits asset -> Protocol vault mints shares
Protocol generates yield -> Vault totalAssets increases
Share price increases -> User redeems shares for more assets
```

Example:

```text
Initial state:
totalAssets = 100 USDC
totalSupply = 100 shares
sharePrice = 1 USDC/share

After protocol yield:
totalAssets = 110 USDC
totalSupply = 100 shares
sharePrice = 1.1 USDC/share

User redeems 100 shares:
assetsOut = 100 * 110 / 100 = 110 USDC
```

Protocol vaults must calculate `totalAssets()` from real assets controlled by the vault:

```solidity
function totalAssets() public view override returns (uint256) {
    return IERC20(asset()).balanceOf(address(this)) + _protocolTotalAssets();
}
```

Rules:

- Protocol yield should increase `totalAssets()` and therefore increase share price.
- Users earn yield by holding and redeeming vault shares.
- Do not add staking-style `claimReward()` by default.
- Do not use `rewardPerToken` or accumulator reward accounting unless distributing external reward tokens separately.
- `totalAssets()` must not include projected APR, estimated future rewards, or unclaimable value.
- `totalAssets()` must only include idle underlying assets plus redeemable protocol position value.

### External Reward Tokens

Some external protocols may emit reward tokens that are different from the vault underlying asset.

Default policy: `HarvestAndCompound`.

External rewards should be claimed, swapped into the vault underlying asset, and reinvested into the protocol vault. Users do not receive external reward tokens directly. Instead, harvested rewards increase `totalAssets()`, which increases the ERC-4626 share price.

```text
External protocol emits reward token
Vault harvests reward token
Vault swaps reward token -> underlying asset
Vault reinvests underlying asset
totalAssets increases
share price increases
users realize yield when redeeming shares
```

Rules:

- Do not distribute external reward tokens directly to users by default.
- Do not use `rewardPerToken` or separate reward accumulator accounting by default.
- Harvested rewards must be converted into the vault underlying asset before being counted in `totalAssets()`.
- Unclaimed reward tokens must not be counted in `totalAssets()` unless they are safely claimable and valued by a documented pricing mechanism.
- Swaps must use slippage protection such as `minAmountOut`.
- Swap routes, routers, and price assumptions must be explicit in the design.
- Failed harvesting must not block normal principal withdrawal when technically safe.
- Harvesting must not reduce assets backing ERC-4626 shares.
- Emit events for harvest amount, swapped amount, received underlying, and reinvested amount.

Required harvest flow:

```text
harvest()
1. Claim external reward tokens from the integrated protocol.
2. Swap reward tokens into the vault underlying asset with slippage protection.
3. Reinvest the received underlying asset into the external protocol.
4. Update observable accounting through `totalAssets()`.
```

Security requirements:

- Only authorized harvesters may call harvest functions unless the function is intentionally permissionless and MEV/slippage risks are handled.
- Never approve unlimited third-party spenders without a clear allowance reset policy.
- Do not rely on a manipulable spot price without protection.
- Do not allow arbitrary swap calldata unless the trusted boundary is explicit.
- Reward token balances held before swapping are not user-claimable balances.

## Fee Model

The vault system may have two fee categories:

1. External protocol fees.
2. Platform fees charged by this vault system.

Fees must be explicit in the design before implementation. Do not hide fees inside ambiguous accounting.

### External Protocol Fees

External protocol fees are costs caused by integrated protocols, swap routes, withdrawal mechanisms, or liquidity constraints.

Examples:

- Lending protocol withdrawal fees.
- Strategy exit fees.
- Swap fees when converting external rewards into the underlying asset.
- Slippage during harvest, deposit, or withdrawal.
- Bridge or message fees if cross-chain integrations are used.
- Losses caused by protocol-specific redemption mechanics.

Default treatment:

- External protocol fees are reflected in actual assets received or recoverable by the protocol vault.
- External protocol fees reduce `totalAssets()` or reduce the assets received in a specific operation.
- Do not promise users a gross amount before external fees unless the system explicitly subsidizes the difference.
- Use preview functions and slippage parameters to protect users from unexpected external costs.

Rules:

- `totalAssets()` must reflect net recoverable value, not gross theoretical value.
- Withdraw/redeem flows must account for protocol exit fees or slippage.
- Harvest flows must account for swap fees and slippage before reinvesting.
- Router functions should expose protection parameters such as `minSharesOut`, `minAssetsOut`, or `maxAssetsIn`.
- If external fees are subsidized by the platform, the subsidy source and limit must be explicit.

### Platform Fees

Platform fees are fees charged by this vault system.

Possible platform fee types:

| Fee Type | Charged On | Default |
|---|---|---|
| `DepositFee` | Assets deposited | Disabled |
| `WithdrawalFee` | Assets withdrawn or shares redeemed | Disabled |
| `PerformanceFee` | Realized yield or harvested profit | Optional |
| `ManagementFee` | Time-based assets under management fee | Disabled unless explicitly required |
| `HarvestFee` | Harvested external rewards | Optional |

Recommended default:

- Do not charge deposit fees in the first version.
- Do not charge withdrawal fees unless needed for protocol exit-cost protection.
- Use performance fees only if the profit calculation is clear and testable.
- Management fees require careful time-based accounting and should not be added by default.
- Fee recipient must be explicit, usually `treasury`.

### Performance Fee

If the system charges a performance fee, charge it only on realized profit.

For ERC-4626 protocol vaults, profit is normally reflected as share price growth through `totalAssets()`.

A performance fee design must define:

- High-water mark or profit baseline.
- Whether fees are minted as shares to treasury or taken as underlying assets.
- When fees are crystallized.
- Whether losses must be recovered before new performance fees are charged.

Recommended model:

- Mint fee shares to treasury instead of removing underlying assets.
- Charge only on positive yield since the last fee checkpoint.
- Do not charge performance fees when share price has not increased.
- Do not charge fees on user principal.

### External Reward Harvest Fee

If external reward tokens are harvested and compounded, the platform may charge a fee on the harvested profit.

Flow:

```text
harvest()
1. Claim external reward tokens.
2. Swap rewards into underlying asset.
3. Calculate platform harvest fee on received underlying.
4. Send fee to treasury or mint equivalent shares to treasury.
5. Reinvest the remaining underlying into the protocol vault.
6. `totalAssets()` increases by the net compounded amount.
```

Rules:

- Fee must be calculated after swap output is known.
- Fee must use basis points with an explicit maximum cap.
- Fee recipient must not be zero address.
- Fee changes must be access-controlled and event-emitted.
- Fee changes should be timelocked or bounded if governance risk matters.

### Fee Accounting Invariants

- Platform fees must not make user principal accounting insolvent.
- External protocol fees must be reflected in net asset value.
- `totalAssets()` must not overstate value before fees, slippage, or protocol exit costs.
- Fee-on-fee behavior must be explicitly avoided or documented.
- Fee recipients must not be able to withdraw assets backing user shares except through defined fee logic.
- Fee calculations must be rounded in favor of the vault unless explicitly documented otherwise.

## Security Invariants

Every architecture document must include the applicable invariants before implementation.

- Router only routes to active registered vaults.
- Router must not keep principal after a completed user operation.
- Router must not mint or burn protocol vault shares directly.
- Router vault metadata must match the protocol vault's actual underlying asset.
- Each protocol vault accounts only for its own assets and protocol position.
- Shares from vault A cannot redeem assets from vault B.
- Yield or loss in one vault cannot change another vault's share price.
- `totalAssets()` must not include projected or unclaimable value.
- `maxWithdraw()` and `maxRedeem()` must respect real protocol liquidity.
- Async withdrawal requests cannot be claimed more than once.
- Pausing deposits should not block safe principal withdrawal unless technically required.
- Rescue functions cannot remove assets backing user principal or claimable withdrawals.
- Harvesting and fee collection must not reduce assets backing user shares except through explicitly documented fee logic.

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
- Which asset each protocol vault accepts.
- Whether router access is a product convention or an on-chain restriction.
- Whether each protocol vault supports instant or async withdrawal.
- How external reward tokens are harvested, swapped, and compounded.
- Which platform fees are enabled.
- Whether vaults are immutable or upgradeable.
- Which admin roles can register vaults, pause flows, harvest rewards, configure fees, rescue tokens, or upgrade contracts.
