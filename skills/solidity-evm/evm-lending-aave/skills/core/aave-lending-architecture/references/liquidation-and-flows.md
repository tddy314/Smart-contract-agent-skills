# Liquidation And Flows

## Scope

Read this file when implementing or changing supply, withdraw, borrow, repay, or liquidation flows.

## Supply

Expected flow:

```text
user supplies reserve asset
Pool validates reserve state
Pool transfers asset in
Pool mints aToken claim
```

## Withdraw

Expected flow:

```text
user withdraws supplied reserve asset
Pool accrues reserve state
Pool checks resulting health factor if the asset is used as collateral
Pool burns aToken claim
Pool transfers asset out
```

## Borrow

Expected flow:

```text
user borrows reserve asset
Pool accrues reserve state
Pool validates collateral capacity and health factor
Pool updates debt state
Pool transfers borrowed asset out
```

## Repay

Expected flow:

```text
user repays reserve debt
Pool accrues reserve state
Pool transfers asset in
Pool reduces debt state
```

## Liquidation

Expected flow:

```text
liquidator repays borrower debt
Pool validates borrower health factor
Pool seizes collateral under liquidation rules
Pool reduces borrower debt and collateral
```

Rules:

- Liquidation must only be allowed when the borrower is unhealthy.
- Liquidation pricing must use the same valuation path as account data.
- The seized collateral amount must respect liquidation bonus and collateral availability.
