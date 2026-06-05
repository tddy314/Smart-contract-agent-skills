# Security Checks

## Scope

Read this file when implementing or reviewing cross-cutting safety checks for the lending pool.

## Checks

- Add reentrancy protection to deposit, withdraw, supply, withdraw liquidity, borrow, repay, liquidate, rescue, and admin paths that combine external calls with state mutation.
- Use checks-effects-interactions ordering where practical.
- Validate zero-address sensitive inputs on initialization and privileged updates.
- Bound fee basis points, liquidation parameters, caps, and utilization config.
- Ensure pause controls cannot accidentally lock technically safe repayment.
- Ensure rescue flows cannot remove assets backing user collateral, supplier claims, or protocol reserves beyond the recorded amount.
- Keep reserve state transitions consistent if an external token transfer or oracle call reverts.
- Emit events for every privileged change and every user-facing asset movement.
- Test unsupported token behavior explicitly if the design rejects fee-on-transfer, rebasing, or non-standard ERC20 tokens.
