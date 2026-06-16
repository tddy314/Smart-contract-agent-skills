# Rewards And Fees

## Scope

Read this file when implementing or changing share-price accounting, external reward harvesting, or platform fee policy.

## Share-Price Yield Model

The default reward model is share-price based accounting.

Each protocol vault should treat yield as an increase in `totalAssets()`. Users do not receive a separate reward balance by default. Users realize yield when they redeem or withdraw shares.

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

Rules:

- Protocol yield should increase `totalAssets()` and therefore increase share price.
- Users earn yield by holding and redeeming vault shares.
- Do not add staking-style `claimReward()` by default.
- Do not use `rewardPerToken` or accumulator reward accounting unless distributing external reward tokens separately.
- `totalAssets()` must not include projected APR, estimated future rewards, or unclaimable value.
- `totalAssets()` must only include idle underlying assets plus redeemable protocol position value.
- Share price changes must arise from real asset changes, not synthetic bookkeeping that overstates value.
- Fee collection must not make share accounting insolvent.

## External Reward Tokens

Some external protocols may emit reward tokens different from the vault underlying asset.

Default policy: `HarvestAndCompound`.

External rewards should be claimed, swapped into the vault underlying asset, and reinvested into the protocol vault. Users do not receive external reward tokens directly.

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
- Harvesting must not reduce assets backing shares.
- Emit events for harvest amount, swapped amount, received underlying, and reinvested amount.

Required harvest flow:

```text
harvest()
1. Claim external reward tokens from the integrated protocol.
2. Swap reward tokens into the vault underlying asset with slippage protection.
3. Reinvest the received underlying asset into the external protocol.
4. Update observable accounting through `totalAssets()`.
```

## Rules

Apply these rules when implementing or reviewing reward harvesting:

- Restrict harvest access unless the function is intentionally permissionless and MEV or slippage risks are explicitly handled.
- Do not use arbitrary swap calldata unless the trusted boundary is explicit.
- Do not approve unlimited third-party spenders without a documented allowance reset policy.
- Do not count reward tokens in `totalAssets()` before they are safely claimable and valued under a documented policy.
- Do not count harvested value until the reward token has been swapped or otherwise converted under the accounting policy.
- Failed harvest execution must not block technically safe principal withdrawal.
- Emit events for claimed rewards, swap output, fee charged, and reinvested amount.

## Fee Model

The vault system may have two fee categories:

1. External protocol fees.
2. Platform fees charged by this vault system.

### External Protocol Fees

External protocol fees are costs caused by integrated protocols, swap routes, withdrawal mechanisms, or liquidity constraints.

Rules:

- `totalAssets()` must reflect net recoverable value, not gross theoretical value.
- Withdraw and redeem flows must account for protocol exit fees or slippage.
- Harvest flows must account for swap fees and slippage before reinvesting.
- Router functions should expose user protection parameters such as `minSharesOut`, `minAssetsOut`, or `maxAssetsIn`.
- If the platform subsidizes any external cost, document the subsidy source and cap.

### Platform Fees

Possible platform fee types:

| Fee Type | Charged On | Default |
|---|---|---|
| `DepositFee` | Assets deposited | Disabled |
| `WithdrawalFee` | Assets withdrawn or shares redeemed | Disabled |
| `PerformanceFee` | Realized yield or harvested profit | Optional |
| `ManagementFee` | Time-based assets under management fee | Disabled unless explicitly required |
| `HarvestFee` | Harvested external rewards | Optional |

Recommended defaults:

- Do not charge deposit fees in the first version.
- Do not charge withdrawal fees unless needed for protocol exit-cost protection.
- Use performance fees only if the profit calculation is clear and testable.
- Avoid management fees by default.
- Make the fee recipient explicit, usually `treasury`.
- Bound every fee in basis points and validate the cap on every config update.

If the system charges a performance fee:

- Charge only on positive yield since the last fee checkpoint.
- Prefer minting fee shares to treasury over removing underlying assets.
- Do not charge performance fees when share price has not increased.
- Do not charge fees on user principal.
- Emit events for fee configuration changes and fee crystallization actions.
