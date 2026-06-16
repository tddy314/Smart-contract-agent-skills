# Lending Pool Architecture

Use this skill before writing lending pool contracts or materially changing collateral accounting, borrow accounting, liquidity supplier accounting, oracle pricing, interest accrual, rate curves, liquidation, fees, admin controls, or asset-flow behavior.

Unless the user explicitly asks for a mock, simulation, or spike, implement real protocol or production-facing contract logic rather than mock-only architecture.

## Purpose

Design a lending pool where users can:

- Deposit multiple supported tokens as collateral.
- Supply liquidity to token-specific lending reserves and earn yield.
- Move part of their collateral into liquidity supply when the remaining collateral still covers their debt.
- Borrow multiple supported tokens at the same time using a shared collateral pool.
- Repay debt.
- Be liquidated when total debt value exceeds liquidation-adjusted collateral value.

The first version should use one core `LendingPool` contract as the main user-facing gateway.

## Core Model

The architecture is:

```text
User / Lender / Liquidator
 |
 | depositCollateral / withdrawCollateral
 | supplyLiquidity / withdrawLiquidity / supplyFromCollateral
 | borrow / repay / liquidate
 v
LendingPool
 |
 | collateral accounting
 | liquidity supplier share accounting
 | scaled debt accounting
 | borrow power and liquidation checks
 | reserve state and interest accrual
 |
 +--> ChainlinkPriceOracle
 |
 +--> DefaultInterestRateModel
```

Use these defaults unless requirements say otherwise:

- Use one core `LendingPool` contract as the gateway for all user operations.
- Use global collateral config per collateral token, not per borrow-token/collateral-token pair.
- Allow users to deposit multiple collateral tokens.
- Allow users to borrow multiple debt tokens at the same time.
- Use Chainlink oracle feeds and normalize every token value to USD with `1e18` precision.
- Use utilization-based variable borrow rates.
- Use reserve-specific liquidity pools for each borrow token.
- Give liquidity suppliers pool shares for the specific token they supply.
- Let supplier yield come from borrower interest after protocol reserve fees.
- Track user debt with scaled debt and a borrow index.
- Track protocol fee as `protocolReserves[token]`.
- Use `SafeERC20` for all ERC20 transfers.
- Reject fee-on-transfer and rebasing tokens unless the accounting model explicitly supports them.
- Keep repay available even if borrow is paused.

## Required Inputs

Determine these requirements before selecting or implementing the architecture:

- Supported collateral tokens.
- Supported borrow and liquidity tokens.
- Whether any token is both collateral and borrowable.
- Global collateral risk parameters: LTV, liquidation threshold, liquidation bonus.
- Reserve parameters for each borrow/liquidity token: supply enabled, borrow enabled, reserve factor, borrow cap, supply cap.
- Interest rate parameters: base rate, slope1, slope2, optimal utilization.
- Chainlink feeds for every collateral and borrow token.
- Oracle stale price threshold.
- Protocol fee policy and treasury address.
- Whether close factor is required for liquidation.
- Administrative controls: token registration, config updates, oracle updates, pause controls, reserve withdrawals, rescue.
- Unsupported token behaviors: fee-on-transfer, rebasing, ERC777 hooks, non-standard ERC20 return values.

If requirements are missing, state assumptions explicitly before proposing contracts.

## Core Formulas

Borrow power is based on all collateral deposited by the user:

```text
collateralValueUSD[token] = collateralAmount[token] * tokenPriceUSD

borrowPowerUSD =
  sum(collateralValueUSD[token] * ltvBps[token] / 10000)
```

Total debt is the sum of all borrowed tokens:

```text
totalDebtUSD =
  sum(actualDebt[token] * debtTokenPriceUSD)
```

Borrow and collateral withdrawal are allowed only when:

```text
totalDebtUSDAfter <= borrowPowerUSDAfter
```

Liquidation uses liquidation threshold, not LTV:

```text
liquidationPowerUSD =
  sum(collateralValueUSD[token] * liquidationThresholdBps[token] / 10000)
```

The user is liquidatable when:

```text
totalDebtUSD > liquidationPowerUSD
```

## Main Components

The main state model is:

- `CollateralConfig[token]`: global collateral risk config.
- `ReserveConfig[token]`: supply and borrow config for each reserve token.
- `ReserveState[token]`: supply shares, scaled borrows, available liquidity, borrow index, last accrual timestamp, protocol reserves.
- `collateralBalance[user][token]`: deposited collateral.
- `supplyShares[user][token]`: liquidity supplier claim.
- `borrowDebt[user][token]`: scaled user debt.

Rules that should stay true across implementations:

- `ltvBps <= liquidationThresholdBps <= 10000`.
- Protocol fees come only from accrued interest, not principal.
- `protocolReserves[token]` are not supplier claim.
- Supplier shares cannot redeem more than available liquidity.
- Borrowing reduces available liquidity.
- Repayment increases available liquidity.
- Liquidation can occur only when total debt exceeds liquidation power.
- Admin rescue cannot remove accounted collateral, supplier liquidity, borrower repayment liquidity, or protocol reserves beyond the recorded reserve amount.

## Read References And Rules

Keep `SKILL.md` as the overview. Read the detailed reference files for architecture details and the rules files for implementation guardrails.

- For reserve state, scaled debt, supplier share accounting, and collateral-to-liquidity movement:
  See [architecture-accounting.md](architecture-accounting.md)
  For implementation checks on the same area:
  See [architecture-accounting-rules.md](architecture-accounting-rules.md)
- For oracle normalization, borrow power math, collateral config, and price validation:
  See [architecture-oracle-and-pricing.md](architecture-oracle-and-pricing.md)
  For implementation checks on the same area:
  See [architecture-oracle-and-pricing-rules.md](architecture-oracle-and-pricing-rules.md)
- For utilization, borrow rate curve, accrual timing, reserve factor, and protocol reserves:
  See [architecture-interest-rate-model.md](architecture-interest-rate-model.md)
  For implementation checks on the same area:
  See [architecture-interest-rate-rules.md](architecture-interest-rate-rules.md)
- For detailed external function requirements and admin control requirements:
  See [architecture-function-spec.md](architecture-function-spec.md)
  For implementation checks on the same area:
  See [architecture-function-rules.md](architecture-function-rules.md)
- For liquidation conditions, seize math, and close-factor considerations:
  See [architecture-liquidation.md](architecture-liquidation.md)
  For implementation checks on the same area:
  See [architecture-liquidation-rules.md](architecture-liquidation-rules.md)
- For invariant-driven testing expectations:
  See [architecture-test-plan.md](architecture-test-plan.md)
  For system-wide implementation security checks:
  See [architecture-security-checks.md](architecture-security-checks.md)

## Contract Layout

Use this baseline layout:

```text
contracts/
+-- core/
|   `-- LendingPool.sol
+-- interfaces/
|   +-- ILendingPool.sol
|   +-- IPriceOracle.sol
|   +-- IInterestRateModel.sol
|   `-- IChainlinkAggregator.sol
+-- oracle/
|   `-- ChainlinkPriceOracle.sol
+-- rates/
|   `-- DefaultInterestRateModel.sol
+-- libraries/
|   +-- PercentageMath.sol
|   `-- WadRayMath.sol
`-- mocks/
    +-- MockERC20.sol
    `-- MockChainlinkAggregator.sol
```

Prefer existing project folder conventions before creating new directories.

## Required Design Output

Before implementation, produce a design brief with:

1. Supported collateral tokens.
2. Supported borrow/liquidity tokens.
3. Collateral config table.
4. Reserve config table.
5. Interest rate config table.
6. Oracle feed table and stale threshold.
7. Contract/file map.
8. User accounting model.
9. Reserve accounting model.
10. Borrow power formula.
11. Liquidation power formula.
12. Borrow, repay, supply, withdraw, and liquidation flows.
13. Protocol fee model.
14. Admin roles and trust assumptions.
15. Security invariants.
16. Test plan mapped to invariants.
17. Unresolved design decisions that block implementation.

## Stop Conditions

Do not implement contracts until these are clear:

- Which tokens are accepted as collateral.
- Which tokens can be supplied and borrowed.
- Whether liquidity supply shares are internal accounting or external ERC20 pool tokens.
- Whether close factor is required.
- Oracle feeds and stale thresholds.
- Interest rate parameters for every reserve.
- Reserve factor and treasury policy.
- Borrow and supply caps.
- Admin roles and allowed config changes.
- Whether unsupported token behaviors are explicitly rejected or supported.
