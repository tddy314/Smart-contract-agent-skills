# Function Rules

## Scope

Read this file when implementing or reviewing the external API and admin control surface.

## User Function Rules

- Revert on zero-amount operations unless the design explicitly supports them.
- Revert if the token is not enabled for the requested action.
- Revert if user balances or debt are insufficient for the requested action.
- Do not let borrow or withdrawal paths bypass borrow-power checks.
- Do not let repay over-credit a user beyond actual debt.
- Do not leave transferred assets stranded in temporary accounting after an operation completes.
- Use `SafeERC20` for every transfer and approval interaction.
- Emit events for collateral deposits, collateral withdrawals, liquidity supply, liquidity withdrawal, borrow, repay, and collateral-to-liquidity moves.

## Admin Rules

- Validate zero-address sensitive inputs such as treasury, oracle dependencies, and privileged role targets.
- Bound config writes for fees, caps, and stale thresholds.
- Emit events for every privileged state change.
- Do not allow config changes that immediately make accounting insolvent without an explicit migration plan.
- Pausing borrow must not block repay.
- Pausing supply should not block safe liquidity withdrawal when technically possible.
- Rescue flows must not remove accounted collateral, supplier claim backing, or protocol reserves beyond the recorded amount.
