// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StrategyVault.sol";

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

contract StrategyVaultTest is Test {
    StrategyVault public vault;
    MockERC20 public token;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        token = new MockERC20();
        vault = new StrategyVault(address(token), "Test Vault", "tvTKN");
    }

    function test_depositAndWithdraw() public {
        token.mint(alice, 1000e18);

        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        uint256 shares = vault.deposit(1000e18, alice);
        assertEq(shares, 1000e18, "first deposit should be 1:1");
        assertEq(vault.balanceOf(alice), 1000e18);
        assertEq(vault.totalAssets(), 1000e18);

        vault.withdraw(1000e18, alice, alice);
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(vault.totalSupply(), 0);
        vm.stopPrank();
    }

    function test_multipleDepositors() public {
        token.mint(alice, 500e18);
        token.mint(bob, 500e18);

        vm.startPrank(alice);
        token.approve(address(vault), 500e18);
        vault.deposit(500e18, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(vault), 500e18);
        vault.deposit(500e18, bob);
        vm.stopPrank();

        assertEq(vault.totalSupply(), 1000e18);
        assertEq(vault.balanceOf(alice), 500e18);
        assertEq(vault.balanceOf(bob), 500e18);
    }

    // NOTE: no tests for:
    // - first deposit when totalAssets > 0 and totalSupply == 0 (donation attack / divide-by-zero)
    // - addStrategy by non-owner (access control missing)
    // - removeStrategy with outstanding debt
    // - withdraw when strategy returns less than requested (no max_loss check)
    // - rounding direction on deposit vs withdraw (both round up — should be opposite)
    // - redeem with shares > balance
}
