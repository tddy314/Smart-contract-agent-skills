# Sui Strategy Wrapper and Hot-Potato Reference

## Wrapped authority model

A wrapper may hold or mediate an authority object/cap from another protocol. Treat this as a high-value object.

Checklist:

- where the cap enters the wrapper;
- who can borrow or use it;
- whether there is an outstanding-borrow flag or `Option`;
- how the cap is returned;
- what happens on migration/emergency path.

## Receipt structure

Receipts should encode enough to prevent substitution:

- wrapper ID;
- borrower/relayer address;
- borrowed cap/object ID or asset type;
- amount/value if funds are borrowed;
- nonce/version if multiple outstanding actions could conflict.

The receipt should not be droppable/storable/copyable unless the protocol has another enforcement mechanism.

## Borrow/return flow

```text
borrow → mark outstanding → return cap/object + receipt → verify receipt → clear outstanding → emit event
```

Abort on:

- already outstanding;
- wrong sender;
- wrong wrapper ID;
- wrong amount;
- wrong returned object;
- stale wrapper version.

## Strategy target checks

- Fixed strategy: hardcode or config-store exact target IDs.
- Multiple strategies: store allow-list and validate membership.
- Object relationship: cross-check target object fields point to expected market/reserve/pool.

## Test focus

- deposit/withdraw share math;
- rebalance after refresh;
- wrong relayer rejected;
- double borrow rejected;
- wrong receipt rejected;
- migration preserves or intentionally moves authority;
- fee extraction cannot drain principal unexpectedly.
