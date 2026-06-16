# Sui Liquid Staking Lifecycle Reference

## Common objects

- `StakePool` / `Storage` - shared global accounting and validator allocation.
- `ValidatorPool` - per-validator active/inactive stake and refresh status.
- `LSTInfo` / `Cert` - liquid staking token or certificate metadata/accounting.
- `TreasuryCap<LST>` - mint/burn authority for the LST.
- `AdminCap` / `OperatorCap` - config vs operational authority.

## Refresh sequence

```text
read epoch → update validator active/inactive state → reconcile total underlying → update exchange rate → collect/apply fees → perform user action
```

Refresh should be safe to call repeatedly in the same epoch.

## Mint flow

1. Receive `Coin<SUI>`.
2. Convert to balance or stake input as the repo requires.
3. Refresh exchange-rate state.
4. Compute LST/cert amount with conservative rounding.
5. Mint with `TreasuryCap`.
6. Emit deposit/mint event.

## Redeem flow

1. Refresh exchange-rate and inactive stake state.
2. Burn LST or lock receipt.
3. If liquidity exists, return SUI.
4. If delayed, create/request claim object with explicit ownership and timing.
5. Emit redeem/request event.

## Test focus

- first deposit and zero supply;
- nonzero deposit producing zero LST is rejected;
- refresh twice same epoch is no-op;
- epoch rollover updates exchange rate;
- inactive validator migration;
- insufficient liquidity delayed redeem;
- cap-gated operator/admin actions;
- fee bounds and fee extraction rounding.
