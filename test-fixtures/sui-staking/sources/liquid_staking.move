module liquid_staking::liquid_staking {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // ── Errors ──────────────────────────────────────────────────────────────
    const EZeroAmount: u64 = 0;
    const EWrongEpoch: u64 = 1;
    const EInsufficientBalance: u64 = 2;

    // ── LST one-time witness ─────────────────────────────────────────────────

    public struct LST has drop {}

    // ── Structs ──────────────────────────────────────────────────────────────

    public struct LiquidStakingInfo has key {
        id: UID,
        sui_balance: Balance<SUI>,
        total_sui_supply: u64,
        lst_treasury_cap: TreasuryCap<LST>,
        current_epoch: u64,
        validators: vector<address>,
        // rewards accrued per epoch (basis points, 1 bp = 0.01%)
        reward_bps: u64,
    }

    public struct AdminCap has key, store {
        id: UID,
    }

    // ── Init ─────────────────────────────────────────────────────────────────

    fun init(witness: LST, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9,
            b"LST",
            b"Liquid Staked SUI",
            b"",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);

        let info = LiquidStakingInfo {
            id: object::new(ctx),
            sui_balance: balance::zero(),
            total_sui_supply: 0,
            lst_treasury_cap: treasury_cap,
            current_epoch: 0,
            validators: vector::empty(),
            reward_bps: 450, // 4.5% APR approximated
        };
        transfer::share_object(info);
        transfer::transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    // ── Core operations ───────────────────────────────────────────────────────

    /// Deposit SUI and receive LST tokens.
    public entry fun mint_lst(
        info: &mut LiquidStakingInfo,
        sui: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let sui_amount = coin::value(&sui);
        assert!(sui_amount > 0, EZeroAmount);

        let lst_supply = coin::total_supply(&info.lst_treasury_cap);

        // BUG: integer division truncates; when lst_supply == 0 this gives 0
        // (should special-case first mint to issue 1:1)
        let lst_amount = if (lst_supply == 0) {
            // BUG: still uses this formula when total_sui_supply may be 0 too
            sui_amount * lst_supply / (info.total_sui_supply + 1)
        } else {
            sui_amount * lst_supply / info.total_sui_supply
        };

        // BUG: sui coin value is read but the Coin itself is not consumed via
        // coin::into_balance — funds would be lost/leaked in a real compile
        // (this illustrates the pattern mistake; left as-is for agents to find)
        let sui_balance = coin::into_balance(sui);
        balance::join(&mut info.sui_balance, sui_balance);
        info.total_sui_supply = info.total_sui_supply + sui_amount;

        let lst_coin = coin::mint(&mut info.lst_treasury_cap, lst_amount, ctx);
        transfer::public_transfer(lst_coin, tx_context::sender(ctx));
    }

    /// Burn LST and receive SUI immediately.
    public entry fun redeem_lst(
        info: &mut LiquidStakingInfo,
        lst: Coin<LST>,
        ctx: &mut TxContext,
    ) {
        let lst_amount = coin::value(&lst);
        assert!(lst_amount > 0, EZeroAmount);

        let lst_supply = coin::total_supply(&info.lst_treasury_cap);
        // BUG: no epoch delay — real LST protocols queue redemptions and fulfill
        // after the next unstaking epoch; instant redemption breaks invariants
        let sui_amount = lst_amount * info.total_sui_supply / lst_supply;
        assert!(balance::value(&info.sui_balance) >= sui_amount, EInsufficientBalance);

        coin::burn(&mut info.lst_treasury_cap, lst);
        info.total_sui_supply = info.total_sui_supply - sui_amount;

        let sui_coin = coin::from_balance(
            balance::split(&mut info.sui_balance, sui_amount),
            ctx,
        );
        transfer::public_transfer(sui_coin, tx_context::sender(ctx));
    }

    /// Accrue staking rewards and update exchange rate.
    public entry fun refresh_epoch(
        info: &mut LiquidStakingInfo,
        new_epoch: u64,
        ctx: &mut TxContext,
    ) {
        // BUG: no AdminCap check — anyone can call this
        // BUG: can be called multiple times in the same epoch; each call
        // inflates total_sui_supply with rewards, causing double-counting
        let _ = ctx;
        assert!(new_epoch >= info.current_epoch, EWrongEpoch);

        let epochs_elapsed = new_epoch - info.current_epoch;
        if (epochs_elapsed == 0) {
            // BUG: returns without updating epoch, so same epoch can be
            // re-entered by calling with new_epoch == current_epoch + 1 next time
            return
        };

        // Accrue reward_bps per epoch (per year approximation ignored)
        let rewards = info.total_sui_supply * info.reward_bps * epochs_elapsed / 10_000;
        info.total_sui_supply = info.total_sui_supply + rewards;
        // BUG: current_epoch not updated here when epochs_elapsed == 0 branch skips,
        // and even in the happy path the update below is the only guard
        info.current_epoch = new_epoch;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    public entry fun add_validator(
        _: &AdminCap,
        info: &mut LiquidStakingInfo,
        validator: address,
    ) {
        vector::push_back(&mut info.validators, validator);
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    public fun exchange_rate(info: &LiquidStakingInfo): u64 {
        let lst_supply = coin::total_supply(&info.lst_treasury_cap);
        if (lst_supply == 0) return 1_000_000_000;
        info.total_sui_supply * 1_000_000_000 / lst_supply
    }
}
