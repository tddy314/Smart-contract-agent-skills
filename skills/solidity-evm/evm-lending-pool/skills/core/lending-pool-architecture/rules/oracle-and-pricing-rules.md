# Oracle And Pricing Rules

## Scope

Read this file when implementing or reviewing Chainlink integration, price normalization, borrow power checks, or liquidation pricing.

## Rules

- Revert if the token has no configured price feed.
- Revert if the oracle answer is zero, negative, stale, or incomplete.
- Normalize token decimals and feed decimals consistently in one code path.
- Use the same pricing path for borrow power, debt value, liquidation power, and seized collateral math.
- Do not hardcode stablecoin prices unless the design explicitly documents that choice.
- Do not rely on manipulable spot prices or caller-provided prices.
- Bound stale-price thresholds and validate admin updates to them.
- Emit events when feeds or oracle configuration are changed.
