# Withdrawal Model

## Scope

Read this file when implementing or changing instant withdrawal, async request/claim withdrawal, capability flags, or router flow checks.

## Withdrawal Capability Model

Vaults can support different withdrawal behavior.

| Capability | Meaning |
|---|---|
| `INSTANT_WITHDRAWAL` | Assets can be returned in the same transaction |
| `ASYNC_WITHDRAWAL` | User must request withdrawal and claim later |
| `PAUSABLE_DEPOSIT` | Deposits can be paused independently |
| `PAUSABLE_WITHDRAWAL` | Withdrawals can be paused only when technically necessary |

Async vaults should expose a separate interface:

```solidity
interface IAsyncProtocolVault {
    function requestRedeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 requestId);

    function claimRedeem(uint256 requestId, address receiver)
        external
        returns (uint256 assets);

    function isClaimable(uint256 requestId) external view returns (bool);
}
```

## Rules

Apply these rules when implementing or reviewing withdrawal capability logic:

- Revert if a router path calls an instant withdrawal function on a vault without instant withdrawal capability.
- Revert if a router path calls an async withdrawal function on a vault without async withdrawal capability.
- Keep request ownership explicit and enforce it during claim.
- Ensure async withdrawal requests cannot be claimed twice.
- Make claimable state observable on-chain.
- Prefer keeping principal withdrawal available even when deposits are paused, unless the external protocol makes this technically unsafe.
- Enforce user protection parameters such as `minAssetsOut` or equivalent slippage protection on flows exposed to external exit risk.
- Emit events for request creation, request fulfillment, and request cancellation if cancellation exists.

## Deposit

```text
User -> VaultRouter.depositToVault()
Router: validate vault, asset, active status, minSharesOut
Router -> ProtocolVault.deposit()
ProtocolVault -> External Protocol: supply assets
ProtocolVault -> User: mint protocol vault shares
```

Required checks:

- Vault is active.
- Asset matches the selected vault.
- Minted shares are at least `minSharesOut`.
- Router does not retain user funds.
- The deposit path must not bypass router-level vault and asset validation.

## Instant Withdraw

```text
User -> VaultRouter.withdrawFromVault()
Router: validate instant withdrawal capability and minAssetsOut
Router -> ProtocolVault.withdraw()
ProtocolVault -> External Protocol: withdraw assets
ProtocolVault -> User: transfer assets
ProtocolVault: burn shares
```

Required checks:

- Vault supports instant withdrawal.
- `maxWithdraw(user)` is sufficient.
- Returned assets are at least `minAssetsOut`.
- Router does not retain returned user assets after completion.

## Async Withdraw

```text
User -> VaultRouter.requestRedeem()
Router: validate async withdrawal capability
Router -> AsyncProtocolVault.requestRedeem()
AsyncProtocolVault: record withdrawal request

Later:
User -> VaultRouter.claimRedeem()
Router -> AsyncProtocolVault.claimRedeem()
AsyncProtocolVault -> User: transfer assets
```

Required checks:

- Request owner is validated.
- Request cannot be claimed twice.
- Claimable state is externally observable.
- Claim paths must not bypass ownership checks through alternate receiver parameters.
