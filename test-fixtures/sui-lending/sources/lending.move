module lending::lending {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    // ── Errors ──────────────────────────────────────────────────────────────
    const EInsufficientLiquidity: u64 = 0;
    const EInsufficientCollateral: u64 = 1;
    const ENotOwner: u64 = 2;
    const EObligationHealthy: u64 = 3;

    // ── Structs ──────────────────────────────────────────────────────────────

    public struct Reserve<phantom T> has key {
        id: UID,
        balance: Balance<T>,
        total_deposits: u64,
        total_borrows: u64,
        deposit_share_value: u64,   // scaled 1e9
        borrow_share_value: u64,    // scaled 1e9
        last_refresh_ms: u64,
        oracle_id: ID,
    }

    public struct Obligation has key {
        id: UID,
        collaterals: vector<u64>,   // share amounts per reserve index
        debts: vector<u64>,         // share amounts per reserve index
        owner: address,
    }

    public struct ObligationKey has key, store {
        id: UID,
    }

    public struct AdminCap has key, store {
        id: UID,
    }

    // ── Init ─────────────────────────────────────────────────────────────────

    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    // ── Reserve management ───────────────────────────────────────────────────

    public entry fun create_reserve<T>(
        _: &AdminCap,
        oracle_id: ID,
        ctx: &mut TxContext,
    ) {
        let reserve = Reserve<T> {
            id: object::new(ctx),
            balance: balance::zero(),
            total_deposits: 0,
            total_borrows: 0,
            deposit_share_value: 1_000_000_000,
            borrow_share_value: 1_000_000_000,
            last_refresh_ms: 0,
            oracle_id,
        };
        transfer::share_object(reserve);
    }

    /// Update interest indices. Should be called before any state-changing operation.
    public fun refresh_reserve<T>(reserve: &mut Reserve<T>, clock_ms: u64) {
        let elapsed = clock_ms - reserve.last_refresh_ms;
        if (elapsed == 0) return;

        // Simplified: 5% APR linearly approximated per ms
        let interest_per_ms: u64 = 5_000_000_000 / (365 * 24 * 3_600_000);
        let accrued = reserve.total_borrows * interest_per_ms * elapsed / 1_000_000_000;

        reserve.total_deposits = reserve.total_deposits + accrued;
        reserve.borrow_share_value = reserve.borrow_share_value
            + accrued * 1_000_000_000 / (reserve.total_borrows + 1);
        reserve.last_refresh_ms = clock_ms;
    }

    // ── Obligation management ─────────────────────────────────────────────────

    public entry fun create_obligation(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let obligation = Obligation {
            id: object::new(ctx),
            collaterals: vector::empty(),
            debts: vector::empty(),
            owner: sender,
        };
        let key = ObligationKey { id: object::new(ctx) };
        transfer::share_object(obligation);
        transfer::transfer(key, sender);
    }

    // ── Core operations ───────────────────────────────────────────────────────

    public entry fun deposit_collateral<T>(
        reserve: &mut Reserve<T>,
        obligation: &mut Obligation,
        coin: Coin<T>,
        ctx: &mut TxContext,
    ) {
        // BUG: no owner check — anyone can deposit into any obligation
        let amount = coin::value(&coin);
        let shares = amount * 1_000_000_000 / reserve.deposit_share_value;
        balance::join(&mut reserve.balance, coin::into_balance(coin));
        reserve.total_deposits = reserve.total_deposits + amount;
        vector::push_back(&mut obligation.collaterals, shares);
    }

    public entry fun withdraw_collateral<T>(
        reserve: &mut Reserve<T>,
        obligation: &mut Obligation,
        shares: u64,
        ctx: &mut TxContext,
    ) {
        // BUG: should verify ObligationKey capability, not sender == owner
        assert!(tx_context::sender(ctx) == obligation.owner, ENotOwner);

        let amount = shares * reserve.deposit_share_value / 1_000_000_000;
        reserve.total_deposits = reserve.total_deposits - amount;
        let withdrawn = balance::split(&mut reserve.balance, amount);

        // BUG: transfer::transfer only works for objects without store — should use public_transfer
        transfer::transfer(coin::from_balance(withdrawn, ctx), obligation.owner);
    }

    public entry fun borrow<T>(
        reserve: &mut Reserve<T>,
        obligation: &mut Obligation,
        amount: u64,
        // BUG: oracle price passed as raw u64, no staleness check
        oracle_price: u64,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == obligation.owner, ENotOwner);

        // BUG: refresh_reserve not called — stale indices used for liquidity check
        let available = balance::value(&reserve.balance);
        assert!(available >= amount, EInsufficientLiquidity);

        // Simplified collateral check using passed price
        let collateral_value = total_collateral_value(obligation, oracle_price);
        let borrow_value = (reserve.total_borrows + amount) * oracle_price / 1_000_000_000;
        assert!(collateral_value * 75 / 100 >= borrow_value, EInsufficientCollateral);

        let borrow_shares = amount * 1_000_000_000 / reserve.borrow_share_value;
        reserve.total_borrows = reserve.total_borrows + amount;
        vector::push_back(&mut obligation.debts, borrow_shares);

        let borrowed = balance::split(&mut reserve.balance, amount);
        transfer::transfer(coin::from_balance(borrowed, ctx), tx_context::sender(ctx));
    }

    public entry fun repay<T>(
        reserve: &mut Reserve<T>,
        obligation: &mut Obligation,
        coin: Coin<T>,
        _ctx: &mut TxContext,
    ) {
        let amount = coin::value(&coin);
        let shares = amount * 1_000_000_000 / reserve.borrow_share_value;
        balance::join(&mut reserve.balance, coin::into_balance(coin));
        reserve.total_borrows = reserve.total_borrows - amount;
        // BUG: pops last debt entry regardless of which debt is being repaid
        if (!vector::is_empty(&obligation.debts)) {
            vector::pop_back(&mut obligation.debts);
        };
        let _ = shares;
    }

    public entry fun liquidate<T>(
        reserve: &mut Reserve<T>,
        obligation: &mut Obligation,
        repay_coin: Coin<T>,
        oracle_price: u64,
        ctx: &mut TxContext,
    ) {
        // BUG: no health check — any obligation can be liquidated regardless of LTV
        let repay_amount = coin::value(&repay_coin);
        balance::join(&mut reserve.balance, coin::into_balance(repay_coin));
        reserve.total_borrows = reserve.total_borrows - repay_amount;

        // Give liquidator 5% bonus collateral
        let collateral_amount = repay_amount * oracle_price * 105 / (100 * 1_000_000_000);
        let collateral = balance::split(&mut reserve.balance, collateral_amount);
        transfer::transfer(
            coin::from_balance(collateral, ctx),
            tx_context::sender(ctx),
        );
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    fun total_collateral_value(obligation: &Obligation, price: u64): u64 {
        let mut total = 0u64;
        let mut i = 0;
        while (i < vector::length(&obligation.collaterals)) {
            total = total + *vector::borrow(&obligation.collaterals, i) * price / 1_000_000_000;
            i = i + 1;
        };
        total
    }
}
