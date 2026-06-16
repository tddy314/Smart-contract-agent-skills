# Router And Vaults

## Scope

Read this file when implementing or changing the router, registry state, protocol vault boundaries, or the base vault template.

## VaultRouter

The router is the single user-facing gateway for supported protocol vault interactions.

Users call the same router to deposit into, withdraw from, redeem from, or request async withdrawal from any supported protocol vault.

The first version should also store registry metadata inside the router.

Execution responsibilities:

- Route user deposits, withdrawals, redeems, async requests, and async claims to the selected protocol vault.
- Validate that the target vault is supported and active.
- Validate that the input asset matches the selected vault.
- Validate the target vault capability before calling instant or async withdrawal flows.
- Enforce user protection parameters such as `minSharesOut`, `minAssetsOut`, and `maxAssetsIn`.
- Emit routing-level events for analytics and integrations.

Registry responsibilities:

- Track supported protocol vaults.
- Track each vault's underlying asset.
- Track each vault's protocol identifier.
- Track each vault instance identifier.
- Track whether each vault is active or disabled.
- Track each vault's withdrawal capability flags.

Non-responsibilities:

- Must not mint or burn protocol vault shares directly.
- Must not own protocol vault accounting.
- Must not calculate protocol yield or share price.
- Must not retain user principal after a completed operation.
- Must not merge accounting across protocol vaults.

Implementation note:

- The router may transfer assets into the selected vault or use an allowance-based vault pull flow.
- In either case, the router must not retain user assets after the operation completes.

Example router registry state:

```solidity
struct VaultInfo {
    address asset;
    bytes32 protocolId;
    bytes32 vaultId;
    uint256 capabilities;
    bool active;
}

mapping(address vault => VaultInfo info) public vaults;
mapping(bytes32 vaultId => address vault) public vaultById;
mapping(bytes32 protocolId => address[] vaults) public vaultsByProtocol;
mapping(address asset => address[] vaults) public vaultsByAsset;
```

## Rules

Apply these rules when implementing or reviewing router and registry logic:

- Revert if the selected vault is not active.
- Revert if the requested asset does not match the vault's configured underlying asset.
- Revert if the registry metadata does not match the vault's actual behavior or underlying asset.
- Do not allow duplicate or inconsistent `vaultId` registration.
- Do not allow inconsistent `protocolId` and vault grouping writes.
- Do not leave user principal stranded in the router after a completed operation.
- Do not mint or burn protocol vault shares directly in the router.
- Do not merge accounting across protocol vaults.
- Emit events for vault registration, activation, deactivation, capability changes, and protocol or asset metadata changes.
- Restrict rescue flows so they cannot remove assets backing user principal, pending withdrawals, or vault share claims.

## Protocol Vault Contracts

Each integrated protocol and asset pair should have its own protocol vault instance.

Each protocol vault should:

- Support only its explicitly configured underlying asset.
- Support exactly one underlying asset per vault instance.
- Issue its own shares for that vault instance.
- Own its own accounting, share price, `totalAssets()`, and protocol interaction logic.
- Define whether withdrawals are instant or async.
- Expose a common interface so the router can interact with different protocol vaults consistently.
- Use OpenZeppelin `ERC4626` as the default base implementation for synchronous vault behavior.

One external protocol can have multiple vault instances:

```text
AaveUSDCVault4626   -> asset: USDC -> shares: aaveUSDC shares
AaveWETHVault4626   -> asset: WETH -> shares: aaveWETH shares
MorphoUSDCVault4626 -> asset: USDC -> shares: morphoUSDC shares
```

The vault address is the canonical unique key. Use `vaultId` only for lookup and readability, such as `keccak256("AAVE-USDC")`.

## Base Vault Template

Use an abstract template only for genuinely shared behavior.

```solidity
abstract contract BaseProtocolVault4626 is ERC4626 {
    function _supplyToProtocol(uint256 assets) internal virtual;

    function _withdrawFromProtocol(uint256 assets, address receiver)
        internal
        virtual
        returns (uint256);

    function _protocolTotalAssets() internal view virtual returns (uint256);

    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _protocolTotalAssets();
    }
}
```

Rules:

- Keep protocol-specific assumptions in concrete vaults.
- Do not force every protocol into the same internal mechanics.
- Do not force async protocols into synchronous ERC-4626 withdrawal semantics.
- Revert if a vault is initialized with the wrong underlying asset.
- Keep each vault bound to exactly one underlying asset for its lifetime unless upgradeability explicitly permits controlled migration.
- Ensure `totalAssets()` counts only idle underlying assets plus redeemable protocol position value.
- Do not include projected APR, estimated future rewards, or unclaimable value in `totalAssets()`.
- Keep losses and gains isolated to the vault instance that owns the position.
