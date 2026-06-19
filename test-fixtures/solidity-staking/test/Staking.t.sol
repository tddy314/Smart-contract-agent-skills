// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract StakingTest is Test {
    StakingRewards public staking;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    address public alice = makeAddr("alice");

    function setUp() public {
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));

        // fund alice with staking tokens
        stakingToken.mint(alice, 1000e18);
        // fund contract with reward tokens
        rewardToken.mint(address(staking), 1000e18);
    }

    function test_stakeAndWithdraw() public {
        vm.startPrank(alice);
        stakingToken.approve(address(staking), 100e18);
        staking.stake(100e18);
        assertEq(staking.balanceOf(alice), 100e18);
        assertEq(staking.totalSupply(), 100e18);

        staking.withdraw(100e18);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(staking.totalSupply(), 0);
        vm.stopPrank();
    }

    function test_getRewardAfterPeriod() public {
        // owner notifies rewards
        staking.notifyRewardAmount(700e18);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 100e18);
        staking.stake(100e18);

        // warp to end of reward period
        vm.warp(block.timestamp + 7 days);

        uint256 earnedAmount = staking.earned(alice);
        assertGt(earnedAmount, 0, "should have earned rewards");

        staking.getReward();
        assertEq(staking.rewards(alice), 0);
        assertGt(rewardToken.balanceOf(alice), 0, "should have received reward tokens");
        vm.stopPrank();
    }

    // NOTE: no tests for:
    // - staking zero amount (should revert but doesn't)
    // - reentrancy on stake/withdraw/getReward
    // - reward rate accuracy over partial periods
    // - multiple stakers share proportionally
    // - notifyRewardAmount with rewardsDuration == 0
    // - withdraw more than staked (underflow revert)
    // - getReward with malicious reward token (reentrancy)
}
