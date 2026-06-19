// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract StakingRewards {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    address public owner;
    uint256 public rewardsDuration = 7 days;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balanceOf;

    uint256 public totalSupply;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerTokenStored;
        return rewardPerTokenStored
            + (rewardRate * (lastTimeRewardApplicable() - lastUpdateTime) * 1e18) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18
            + rewards[account];
    }

    // BUG: no require(amount > 0)
    // BUG: no ReentrancyGuard — external call happens, then state updates (CEI violation)
    function stake(uint256 amount) external updateReward(msg.sender) {
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
        // missing: emit Staked(msg.sender, amount)
    }

    // BUG: no require(amount > 0)
    // BUG: no ReentrancyGuard — transfers before state update below
    function withdraw(uint256 amount) external updateReward(msg.sender) {
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        // missing: emit Withdrawn(msg.sender, amount)
    }

    // BUG: transfers reward BEFORE zeroing rewards[msg.sender] (CEI violation)
    function getReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewardToken.transfer(msg.sender, reward);
            rewards[msg.sender] = 0;
            // missing: emit RewardPaid(msg.sender, reward)
        }
    }

    // BUG: no check that rewardsDuration > 0 (would divide by zero)
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
    }

    function setRewardsDuration(uint256 _duration) external onlyOwner {
        require(block.timestamp > periodFinish, "period not finished");
        rewardsDuration = _duration;
    }
}
