# EVM Pre-Audit Checklist

Use for Solidity, Foundry, Hardhat, upgradeable proxies, ERC tokens, lending pools, staking systems, and vaults.

## Scope and Build

- Identify compiler version, optimizer settings, remappings, libraries, and deployment scripts.
- Identify upgrade model: immutable, proxy, beacon, diamond, governance upgrade, migration script.
- Check initializer and constructor paths.
- Check whether tests run against the same assumptions as deployment.

## Access Control

- Verify owner/admin/guardian/operator roles and who can rotate them.
- Check role confusion between protocol admin, emergency admin, keeper, rewards manager, and strategy manager.
- Check whether privileged functions emit events.
- Check timelock, multisig, governance, and emergency powers as trust assumptions.
- Check `tx.origin` is not used for authorization.

## Asset Flow

- Trace every `transfer`, `transferFrom`, `safeTransfer`, `call{value:...}`, mint, burn, deposit, withdraw, claim, refund.
- Check wrong-recipient, double-claim, duplicate-withdrawal, and stuck-funds cases.
- Check fee recipient and protocol reserve accounting.
- Check ETH receive/fallback behavior and dust handling.
- Check token approvals are not left broader than needed.

## External Calls and Reentrancy

- Identify all external calls before and after state changes.
- Prefer checks-effects-interactions or explicit reentrancy guards where value can move.
- Check callbacks, ERC777 hooks, ERC721/ERC1155 receiver hooks, strategy calls, DEX callbacks, and oracle calls.
- Check whether pull payments are safer than push payments.

## ERC Token Assumptions

- Check non-standard ERC20 behavior: no return value, fee-on-transfer, rebasing, pausable, blacklistable, different decimals.
- Check decimals are read once or validated.
- Check token address cannot be replaced with malicious contracts unless intended.
- Check share or receipt token mint/burn authorization.

## Accounting and Math

- Check rounding direction for deposits, withdrawals, shares, debt, interest, rewards, and fees.
- Check empty-pool and first-depositor branches.
- Check total assets, total shares, total debt, reserves, and user balances remain consistent.
- Check overflow/underflow assumptions and precision loss.
- Check repeated tiny operations cannot drain dust or inflate shares.

## Oracle and Pricing

- Check stale price, zero price, negative price, bad decimals, sequencer status, heartbeat, confidence, and round completeness.
- Check price source cannot be changed unexpectedly.
- Check liquidation and borrow power use the same unit system.
- Check fallback oracle behavior and paused markets.

## State Machines

- Check allowed and forbidden transitions for pause, deposit, borrow, repay, liquidate, withdraw, cooldown, claim, cancel, dispute, migrate.
- Check terminal states cannot be reused.
- Check timeouts, deadlines, and `block.timestamp` boundaries.
- Check replay, repeated calls in same block, and partial completion.

## Upgrade and Migration

- Check storage layout compatibility.
- Check initializer cannot be called twice.
- Check old assets, shares, debts, rewards, and approvals migrate exactly once.
- Check upgrade admin is documented as a trust assumption.

## Test Gaps to Flag

- Unauthorized caller tests.
- Reentrancy or malicious receiver tests.
- Boundary and rounding tests.
- Fork tests when behavior depends on deployed integrations.
- Invariant tests for asset conservation and solvency.
