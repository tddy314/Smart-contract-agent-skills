// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IStrategy {
    function totalAssets() external view returns (uint256);
    function withdraw(uint256 amount) external returns (uint256 loss);
    function deposit(uint256 amount) external;
}

contract StrategyVault {
    struct Strategy {
        uint256 currentDebt;  // assets currently deployed to strategy
        uint256 maxDebt;      // ceiling for this strategy
        bool active;
    }

    IERC20 public immutable asset;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => Strategy) public strategies;
    address[] public withdrawalQueue;

    uint256 public totalDebt;  // total deployed to strategies
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _asset, string memory _name, string memory _symbol) {
        asset = IERC20(_asset);
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + totalDebt;
    }

    // BUG: when totalSupply == 0 and totalAssets == 0, convertToShares returns 0
    //      but first depositor should get shares 1:1 — divide-by-zero not the issue here,
    //      but if totalAssets > 0 and totalSupply == 0 (e.g. donated tokens), this reverts.
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        // BUG: rounds UP on deposit — should round DOWN to protect existing shareholders
        return supply == 0 ? assets : (assets * supply + totalAssets() - 1) / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        // BUG: rounds UP on withdraw — should round DOWN to protect the vault
        return supply == 0 ? shares : (shares * totalAssets() + supply - 1) / supply;
    }

    // BUG: no max_loss / slippage check — user cannot specify acceptable loss
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "zero shares");
        asset.transferFrom(msg.sender, address(this), assets);
        totalSupply += shares;
        balanceOf[receiver] += shares;
    }

    // BUG: no max_loss parameter — strategies may return assets < requested, user gets less
    function withdraw(uint256 assets, address receiver, address vaultOwner)
        external
        returns (uint256 shares)
    {
        shares = convertToShares(assets);
        require(balanceOf[vaultOwner] >= shares, "insufficient shares");

        balanceOf[vaultOwner] -= shares;
        totalSupply -= shares;

        uint256 idle = asset.balanceOf(address(this));
        if (assets <= idle) {
            asset.transfer(receiver, assets);
        } else {
            uint256 needed = assets - idle;
            _withdrawFromStrategies(needed);
            asset.transfer(receiver, asset.balanceOf(address(this)));
        }
    }

    function redeem(uint256 shares, address receiver, address vaultOwner)
        external
        returns (uint256 assets)
    {
        assets = convertToAssets(shares);
        require(balanceOf[vaultOwner] >= shares, "insufficient shares");

        balanceOf[vaultOwner] -= shares;
        totalSupply -= shares;
        asset.transfer(receiver, assets);
    }

    // BUG: no access control — anyone can add a strategy
    function addStrategy(address strategy, uint256 maxDebt) external {
        require(!strategies[strategy].active, "already added");
        strategies[strategy] = Strategy({ currentDebt: 0, maxDebt: maxDebt, active: true });
        withdrawalQueue.push(strategy);
    }

    // BUG: does not check if strategy has outstanding debt before removal
    function removeStrategy(address strategy) external onlyOwner {
        require(strategies[strategy].active, "not active");
        strategies[strategy].active = false;
        // does not drain currentDebt before deactivating
    }

    function allocate(address strategy, uint256 amount) external onlyOwner {
        Strategy storage s = strategies[strategy];
        require(s.active, "strategy not active");
        require(s.currentDebt + amount <= s.maxDebt, "exceeds max debt");

        asset.transfer(strategy, amount);
        IStrategy(strategy).deposit(amount);
        s.currentDebt += amount;
        totalDebt += amount;
    }

    function _withdrawFromStrategies(uint256 needed) internal {
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            if (needed == 0) break;
            address strategyAddr = withdrawalQueue[i];
            Strategy storage s = strategies[strategyAddr];
            if (!s.active || s.currentDebt == 0) continue;

            uint256 toWithdraw = needed > s.currentDebt ? s.currentDebt : needed;
            uint256 loss = IStrategy(strategyAddr).withdraw(toWithdraw);
            uint256 received = toWithdraw - loss;

            s.currentDebt -= toWithdraw;
            totalDebt -= toWithdraw;
            if (received < needed) {
                needed -= received;
            } else {
                needed = 0;
            }
        }
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
