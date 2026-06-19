// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracle {
    // BUG: no staleness check — caller never validates answeredInRound or updatedAt
    function getPrice(address asset) external view returns (uint256 price, uint256 updatedAt);
}

contract LendingPool {
    struct ReserveData {
        uint256 liquidityIndex;       // scaled by 1e27
        uint256 variableBorrowIndex;  // scaled by 1e27
        uint256 lastUpdateTimestamp;
        uint256 totalLiquidity;
        uint256 totalBorrows;
        address aTokenAddress;        // receipt token (not implemented here)
        address debtTokenAddress;     // debt token (not implemented here)
    }

    struct UserAccountData {
        uint256 supplied;   // in underlying units
        uint256 borrowed;   // in underlying units
    }

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;
    uint256 public constant LTV = 0.75e18; // 75% loan-to-value
    uint256 public constant BASE_RATE = 0.02e27; // 2% annual base rate (ray)
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    IPriceOracle public oracle;

    mapping(address => ReserveData) public reserves;
    mapping(address => mapping(address => UserAccountData)) public userAccounts; // asset => user => data

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _oracle) {
        oracle = IPriceOracle(_oracle);
        owner = msg.sender;
    }

    function initReserve(address asset) external onlyOwner {
        reserves[asset].liquidityIndex = 1e27;
        reserves[asset].variableBorrowIndex = 1e27;
        reserves[asset].lastUpdateTimestamp = block.timestamp;
    }

    // BUG: updateIndexes() not called before modifying state — indexes are stale
    function supply(address asset, uint256 amount) external {
        // BUG: no first-deposit edge case handling (liquidityIndex starts at 1e27 but
        //      if first supply arrives after time passes, shares could be miscalculated)
        ReserveData storage reserve = reserves[asset];
        require(reserve.liquidityIndex > 0, "reserve not initialized");

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        reserve.totalLiquidity += amount;
        userAccounts[asset][msg.sender].supplied += amount;
    }

    function borrow(address asset, uint256 amount) external {
        updateIndexes(asset);
        ReserveData storage reserve = reserves[asset];
        require(reserve.totalLiquidity >= amount, "insufficient liquidity");

        require(healthFactor(msg.sender, asset) >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD, "undercollateralized");

        reserve.totalLiquidity -= amount;
        reserve.totalBorrows += amount;
        userAccounts[asset][msg.sender].borrowed += amount;
        IERC20(asset).transfer(msg.sender, amount);
    }

    function repay(address asset, uint256 amount) external {
        updateIndexes(asset);
        ReserveData storage reserve = reserves[asset];
        UserAccountData storage account = userAccounts[asset][msg.sender];
        require(account.borrowed >= amount, "repay exceeds debt");

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        account.borrowed -= amount;
        reserve.totalBorrows -= amount;
        reserve.totalLiquidity += amount;
    }

    // BUG: does not check healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD before proceeding
    // BUG: no close factor — liquidator can repay 100% of the debt
    function liquidate(address asset, address borrower, uint256 repayAmount) external {
        updateIndexes(asset);
        ReserveData storage reserve = reserves[asset];
        UserAccountData storage account = userAccounts[asset][borrower];

        require(account.borrowed >= repayAmount, "repay exceeds debt");

        IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);

        uint256 bonus = (repayAmount * 1.05e18) / 1e18; // 5% liquidation bonus
        account.borrowed -= repayAmount;
        account.supplied -= bonus;
        reserve.totalBorrows -= repayAmount;
        reserve.totalLiquidity += repayAmount;

        IERC20(asset).transfer(msg.sender, bonus);
    }

    function updateIndexes(address asset) public {
        ReserveData storage reserve = reserves[asset];
        uint256 elapsed = block.timestamp - reserve.lastUpdateTimestamp;
        if (elapsed == 0) return;

        uint256 borrowRate = BASE_RATE;
        uint256 interestFactor = (borrowRate * elapsed) / SECONDS_PER_YEAR;

        reserve.variableBorrowIndex =
            (reserve.variableBorrowIndex * (1e27 + interestFactor)) / 1e27;
        reserve.liquidityIndex =
            (reserve.liquidityIndex * (1e27 + interestFactor)) / 1e27;
        reserve.lastUpdateTimestamp = block.timestamp;
    }

    function healthFactor(address user, address asset) public view returns (uint256) {
        UserAccountData storage account = userAccounts[asset][user];
        if (account.borrowed == 0) return type(uint256).max;

        (uint256 price,) = oracle.getPrice(asset);
        uint256 collateralValue = (account.supplied * price) / 1e18;
        uint256 borrowValue = (account.borrowed * price) / 1e18;
        uint256 adjustedCollateral = (collateralValue * LTV) / 1e18;

        return (adjustedCollateral * 1e18) / borrowValue;
    }
}
