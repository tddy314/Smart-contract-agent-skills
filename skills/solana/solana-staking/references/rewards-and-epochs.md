# Rewards and Epochs

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- Exchange-rate rewards
- Reward debt / snapshot accounting
- Time-weighted rewards
- Epoch and time boundaries
- Merkle epoch claims
- What to checkpoint before state changes

---

## Exchange-rate rewards

In liquid staking, rewards usually appear as an improving conversion from the liquid token back to SOL or stake. There is no separate reward transfer to the user. The program needs to read the current redeemable value and account against that.

```rust
let exchange_rate = if total_pool_tokens == 0 || total_share_units == 0 {
    Fraction::ONE
} else {
    Fraction::from_num(total_redeemable_lamports)
        / Fraction::from_num(total_share_units)
};
```

The known anti-pattern here is computing this as `f64` and then dividing a user's amount by that float. Do not copy that. Use fixed-point or integer ratio math.

---

## Reward debt / snapshot accounting

The strongest generic staking pattern is a pool-level accumulator plus per-user reward debt:

```rust
pub struct StakingPool {
    pub total_staked: u128,
    pub reward_per_share_scaled: u128,
}

pub struct UserStake {
    pub staked_amount: u64,
    pub reward_debt_scaled: u128,
    pub pending_rewards: u64,
}

fn checkpoint_user(user: &mut UserStake, pool: &StakingPool) -> Result<()> {
    let accrued_scaled = u128::from(user.staked_amount)
        .checked_mul(pool.reward_per_share_scaled)
        .ok_or(StakingError::MathOverflow)?;
    let delta_scaled = accrued_scaled
        .checked_sub(user.reward_debt_scaled)
        .ok_or(StakingError::MathOverflow)?;
    let newly_earned = (delta_scaled / REWARD_SCALE) as u64;

    user.pending_rewards = user.pending_rewards
        .checked_add(newly_earned)
        .ok_or(StakingError::MathOverflow)?;
    user.reward_debt_scaled = accrued_scaled;
    Ok(())
}
```

This pattern matters because it makes claiming frequency-independent. Claiming once or ten times yields the same total as long as `reward_debt_scaled` is updated correctly.

---

## Time-weighted rewards

Some staking protocols intentionally give younger stake less weight to stop flash-stake reward capture. The weighting can be exponential, linear, or step-based. The important rule for a generic skill is not the exact formula - it is preserving the maturity model and checkpointing it before stake changes.

If a protocol uses time-weighted rewards, then pending reward depends on both amount and age. That means add-stake and partial-unstake operations must preserve maturity semantics; they cannot just overwrite the position with a new flat amount.

---

## Epoch and time boundaries

Epochs matter in staking even when the program does not expose them directly:

- reward distributions may apply from the next epoch;
- unstake completion may require an epoch or time delay;
- native stake activation and deactivation are epoch-based;
- fee or reward updates can have delayed effectiveness.

Read the current epoch or time once from `Clock::get()?`, store it in a local, and use that single value for the whole handler.

---

## Merkle epoch claims

Some protocols compute rewards offchain and publish an onchain epoch root. Users claim by proving inclusion for that epoch.

```rust
pub struct RewardsEpoch {
    pub epoch_index: u64,
    pub merkle_root: [u8; 32],
}

pub struct ClaimRecord {
    pub epoch: Pubkey,
    pub user: Pubkey,
}
```

The critical rule is permanent claim records. Without them, the same merkle proof can be replayed. The claim-record PDA should usually include both epoch and user in its seeds.

---

## What to checkpoint before state changes

Before any of these, checkpoint rewards first:

- increasing or decreasing a user's staked amount;
- changing the total staked amount;
- changing the reward rate or reward source;
- moving a user between staking tiers or validators;
- converting an active stake into a pending-unstake request.

This is the staking analogue of the lending refresh-before-act pattern. The numbers need to be current before the stake state mutates.
