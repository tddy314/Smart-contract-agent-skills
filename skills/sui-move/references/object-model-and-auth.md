# Sui Object Model and Authorization Reference

Use this when implementing or reviewing object state, capabilities, dynamic fields, and transfer behavior.

## Object ownership model

- **Address-owned objects** are controlled by the owning address and can be transferred between addresses.
- **Shared objects** can be accessed by many users; mutable access (`&mut`) routes through consensus and serializes that object.
- **Immutable objects** can be read by anyone but cannot be mutated.
- **Wrapped objects** are stored inside another object and are inaccessible until unwrapped.
- **Dynamic fields / dynamic object fields** extend an object by key. Use dynamic object fields when the child object should remain discoverable by ID.

## Ability decisions

- `key` makes a struct an onchain object and requires `id: UID` as the first field.
- `store` allows wrapping and public transfer; do not add it to objects that require custom transfer rules.
- Objects cannot have `copy` or `drop` because `UID` has neither ability.
- Events are non-object structs and should have `copy, drop`.

## Capability pattern

Prefer explicit capability objects over hardcoded addresses.

Common caps:

- `AdminCap` - config, fee, upgrade or privileged parameter changes.
- `OperatorCap` / `RelayerCap` - bounded operational actions like refresh, rebalance, stake routing.
- `TreasuryCap<T>` - mint/burn authority for a coin type; trace where it is stored and who can borrow it.
- `UpgradeCap` - package upgrade authority; do not leak or wrap casually.

Checklist:

1. Find where the cap is created (`init`, publisher flow, registry setup).
2. Find who receives it.
3. Find every function that accepts it.
4. Confirm the cap is borrowed by reference unless it is intentionally consumed or transferred.
5. Confirm operator caps cannot mutate admin config unless intended.

## Transfer rules

- `transfer::transfer` is module-restricted and works for objects without `store` inside the defining module.
- `transfer::public_transfer` works for objects with `store` and can be called by other modules.
- Once `store` is granted, other modules can transfer/wrap the object; you cannot enforce all transfer logic in your module.
- When destroying an object, unpack it and delete the `UID`; remove dynamic fields first.

## Composability

Prefer:

```move
public fun mint(ctx: &mut TxContext): NFT { ... }

entry fun mint_and_keep(ctx: &mut TxContext) {
    let nft = mint(ctx);
    transfer::transfer(nft, ctx.sender());
}
```

over a single public function that always transfers to the sender. Returning values lets PTBs compose the result with later calls.

## Source anchors

- MystenLabs `object-model` skill: ownership, transfers, dynamic fields, patterns.
- MystenLabs `composable-move-functions` skill: `public` vs `entry`, parameter order, return patterns.
- Move Book object/storage chapters under `sui-skills-ref/mystenlabs/move-book/book/`.
