module vault::vault {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // ── Errors ──────────────────────────────────────────────────────────────
    const EZeroAmount: u64 = 0;
    const EInsufficientShares: u64 = 1;
    const EReceiptMismatch: u64 = 2;
    const EMidRebalance: u64 = 3;

    // ── Structs ──────────────────────────────────────────────────────────────

    public struct Vault has key {
        id: UID,
        balance: Balance<SUI>,
        total_shares: u64,
        strategies: vector<address>,
        // tracks outstanding rebalance borrow; 0 means idle
        pending_rebalance: u64,
    }

    public struct AdminCap has key, store {
        id: UID,
    }

    public struct RelayerCap has key, store {
        id: UID,
    }

    // BUG: has `drop` — a hot-potato receipt MUST have no abilities so it
    // cannot be silently discarded; `drop` lets callers abandon the receipt
    // without ever calling return_from_rebalance, leaking vault funds.
    public struct RebalanceReceipt has drop {
        vault_id: ID,
        borrowed_amount: u64,
    }

    // ── Init ─────────────────────────────────────────────────────────────────

    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let vault = Vault {
            id: object::new(ctx),
            balance: balance::zero(),
            total_shares: 0,
            strategies: vector::empty(),
            pending_rebalance: 0,
        };
        transfer::share_object(vault);
        transfer::transfer(AdminCap { id: object::new(ctx) }, sender);
        transfer::transfer(RelayerCap { id: object::new(ctx) }, sender);
    }

    // ── Core operations ───────────────────────────────────────────────────────

    /// Deposit SUI and receive vault shares.
    public entry fun deposit(
        vault: &mut Vault,
        coin: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let amount = coin::value(&coin);
        assert!(amount > 0, EZeroAmount);

        // BUG: uses current balance AFTER any rebalance borrow has been
        // removed from vault.balance; share price is deflated mid-rebalance,
        // letting depositors buy in cheap while funds are deployed externally
        let current_balance = balance::value(&vault.balance);
        let shares = if (vault.total_shares == 0 || current_balance == 0) {
            amount
        } else {
            amount * vault.total_shares / current_balance
        };

        balance::join(&mut vault.balance, coin::into_balance(coin));
        vault.total_shares = vault.total_shares + shares;

        // Represent shares as a u64 — no share token minted for simplicity
        // (in production you'd mint a coin; here we just transfer a phantom)
        let _ = shares;
        let _ = ctx;
    }

    /// Burn shares and withdraw SUI.
    public entry fun withdraw(
        vault: &mut Vault,
        shares: u64,
        ctx: &mut TxContext,
    ) {
        assert!(shares > 0 && shares <= vault.total_shares, EInsufficientShares);

        // BUG: no mid-rebalance guard — withdrawals during an active rebalance
        // could drain funds that are already lent out, causing insolvency
        let current_balance = balance::value(&vault.balance);
        let amount = shares * current_balance / vault.total_shares;

        vault.total_shares = vault.total_shares - shares;
        let out = balance::split(&mut vault.balance, amount);
        transfer::public_transfer(coin::from_balance(out, ctx), tx_context::sender(ctx));
    }

    // ── Rebalance flow ────────────────────────────────────────────────────────

    /// Relayer borrows funds from the vault to deploy into a strategy.
    /// Returns a RebalanceReceipt hot-potato that MUST be consumed by
    /// return_from_rebalance — except the `drop` ability defeats this.
    public fun borrow_for_rebalance(
        // BUG: RelayerCap not required — any caller can borrow vault funds
        vault: &mut Vault,
        amount: u64,
        ctx: &mut TxContext,
    ): (Coin<SUI>, RebalanceReceipt) {
        assert!(amount > 0, EZeroAmount);
        assert!(balance::value(&vault.balance) >= amount, EInsufficientShares);

        vault.pending_rebalance = vault.pending_rebalance + amount;
        let funds = balance::split(&mut vault.balance, amount);

        let receipt = RebalanceReceipt {
            vault_id: object::uid_to_inner(&vault.id),
            borrowed_amount: amount,
        };
        (coin::from_balance(funds, ctx), receipt)
    }

    /// Relayer returns funds to the vault and consumes the receipt.
    public fun return_from_rebalance(
        vault: &mut Vault,
        receipt: RebalanceReceipt,
        returned: Coin<SUI>,
        _ctx: &mut TxContext,
    ) {
        let RebalanceReceipt { vault_id, borrowed_amount } = receipt;

        // BUG: vault_id from receipt is not checked against the actual vault's
        // ID — a receipt from vault A could be used to "settle" vault B
        let _ = vault_id;

        let returned_amount = coin::value(&returned);
        vault.pending_rebalance = vault.pending_rebalance - borrowed_amount;
        balance::join(&mut vault.balance, coin::into_balance(returned));
        let _ = returned_amount;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    public entry fun add_strategy(
        _: &AdminCap,
        vault: &mut Vault,
        strategy: address,
    ) {
        // BUG: no dedup — same strategy can be added multiple times
        vector::push_back(&mut vault.strategies, strategy);
    }

    // ── View ──────────────────────────────────────────────────────────────────

    public fun share_price(vault: &Vault): u64 {
        if (vault.total_shares == 0) return 1_000_000_000;
        balance::value(&vault.balance) * 1_000_000_000 / vault.total_shares
    }

    public fun pending_rebalance(vault: &Vault): u64 {
        vault.pending_rebalance
    }
}
