# Security Checks

## Scope

Read this file when implementing or reviewing cross-cutting safety checks for the Aave-style lending system.

## Checks

- Add reentrancy protection to user and admin paths that combine state changes with external calls.
- Use checks-effects-interactions ordering where practical.
- Validate zero-address sensitive inputs on initialization and privileged updates.
- Ensure pause and freeze controls do not accidentally bypass repayment or safe unwind paths.
- Ensure rescue paths cannot remove assets backing supplier claims or debt settlement.
- Keep reserve, token, and user-account transitions consistent if an external call reverts.
- Emit events for every privileged change and every user-facing asset movement.
