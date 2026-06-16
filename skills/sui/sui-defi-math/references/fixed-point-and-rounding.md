# Sui Fixed-Point and Rounding Reference

## Scaling

Document the unit of every scaled value:

- basis points: `10_000 = 100%`
- wad-like decimal: `1e18 = 1.0`
- ray-like decimal: `1e27 = 1.0`
- token decimals: token-specific; never assume all coins have 9 decimals like SUI

## Multiplication pattern

Prefer:

```text
result = (amount as u128) * (rate as u128) / SCALE
```

over:

```text
result = amount / SCALE * rate
```

The second loses precision before the multiply.

## Rounding helpers

Create or reuse explicit helpers:

- `mul_div_down(a, b, denominator)`
- `mul_div_up(a, b, denominator)`
- `decimal::from_percent`, `decimal::mul`, repo-specific equivalents

Rounding up formula:

```text
(a * b + denominator - 1) / denominator
```

Only use after proving `a * b` cannot overflow the widened type.

## Rounding defaults by operation

| Operation | Default rounding | Reason |
|---|---|---|
| Mint shares to user | Down | avoid over-issuing ownership |
| Return underlying for burned shares | Down | avoid over-paying reserves |
| Burn shares for exact requested underlying | Up | ensure enough shares are burned |
| Protocol fee extraction | Down | avoid taking too much |
| Liquidation repay/bonus | Protocol-specific | define borrower vs liquidator vs reserve favor explicitly |
| Oracle value conversion | Conservative | avoid overstating collateral or understating debt |

## Oracle safety

Accept a price only when:

- the publish timestamp is within the configured staleness window;
- confidence is within threshold;
- exponent/decimal conversion is handled;
- price is positive and nonzero;
- caller handles `None` or equivalent failure explicitly.

## Refresh ordering

For any action involving rates, rewards, debt, or shares:

```text
refresh oracle/exchange rate → accrue interest/rewards → update indexes → mutate user/pool state
```

Skipping refresh lets users act against stale prices or stale exchange rates.
