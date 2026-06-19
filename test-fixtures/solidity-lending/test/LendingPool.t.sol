// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";

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

contract MockOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getPrice(address asset) external view returns (uint256 price, uint256 updatedAt) {
        // BUG: updatedAt always returns current time — staleness never surfaced to caller
        return (prices[asset], block.timestamp);
    }
}

contract LendingPoolTest is Test {
    LendingPool public pool;
    MockERC20 public token;
    MockOracle public oracle;

    address public alice = makeAddr("alice");

    function setUp() public {
        oracle = new MockOracle();
        token = new MockERC20();
        pool = new LendingPool(address(oracle));

        oracle.setPrice(address(token), 1e18); // $1 per token
        pool.initReserve(address(token));
    }

    function test_supply() public {
        token.mint(alice, 500e18);

        vm.startPrank(alice);
        token.approve(address(pool), 500e18);
        pool.supply(address(token), 500e18);
        vm.stopPrank();

        (uint256 supplied,) = pool.userAccounts(address(token), alice);
        assertEq(supplied, 500e18);
        assertEq(token.balanceOf(address(pool)), 500e18);
    }

    // NOTE: no tests for:
    // - liquidate() called when healthFactor >= 1 (should revert but doesn't)
    // - liquidate() with 100% repayment (close factor not enforced)
    // - stale oracle prices
    // - borrow without sufficient collateral
    // - updateIndexes not called before supply (stale index)
    // - first deposit after time has elapsed
}
