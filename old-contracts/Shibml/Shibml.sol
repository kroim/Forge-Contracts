// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapV2Factory.sol";
import "./uniswap/IUniswapV2Pair.sol";

contract Shibml is IERC20, Ownable {
    using SafeMath for uint256;

    address private constant DEAD = address(0xdead);
    address private constant ZERO = address(0);
    address private devAddress = address(0xdE186721df2D737c7d3cc578f324c856Fb9a1F7b);
    address private treasuryAddress = address(0xBB97a6BEbbECCD1617e7b402AAE9E9688E1C98F8);
    address private marketingAddress = address(0xBB97a6BEbbECCD1617e7b402AAE9E9688E1C98F8);
    address private liquidityAddress = address(0xBB97a6BEbbECCD1617e7b402AAE9E9688E1C98F8);
    /**
     * Token Assets
     * name, symbol, _decimals totalSupply
     * This will be defined when we deploy the contract.
     */
    string private _name = "Shibml";
    string private _symbol = "SHIL";
    uint8 private _decimals = 18;
    uint256 private _totalSupply = 1_000_000_000 * (10 ** _decimals);  // 1 billion

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    bool public enableTrading = true;
    bool public enableSwap = false;
    uint256 public maxBalance = _totalSupply * 2 / 100; // 2%
    uint256 public maxTx = _totalSupply * 2 / 100;  // 2%
    uint256 public swapThreshold = (_totalSupply * 4) / 10000;  // 0.04%

    uint256 _buyMarketingFee = 3;
    uint256 _buyLiquidityFee = 3;
    uint256 _buyReflectionFee = 3;
    uint256 _buyTreasuryFee = 3;

    uint256 _sellMarketingFee = 3;
    uint256 _sellLiquidityFee = 3;
    uint256 _sellReflectionFee = 3;
    uint256 _sellTreasuryFee = 3;

    uint256 public marketingDebt = 0;
    uint256 public liquidityDebt = 0;
    uint256 public treasuryDebt = 0;
    /**
     * Mode & Fee
     * mode0 = prefee system
     * mode1(BuyTax: treasury=2%, reflection=3%, SellTax: treasury=2%, reflection=3%)
     * mode2(BuyTax: 0, SellTax: treasury=2%, reflection=2%, luck holder reward=2%)
     * mode3(BuyTax: auto burn supply=1%, reflections to all top 50 holders=3%, 
     *       SellTax: treasury=2%, reflection=3%)
     * mode4(BuyTax: 0, SellTax: 0)
     * mode5(BuyTax: reflection=5%, SellTax: reflection=5%)
     * mode6(Buytax: 0, SellTax: reflection=5% to buyers of this mutation)
     */
    uint8 public mode = 0;  // current mode
    bool public isAutoMode = false;
    uint256 public modeStartTime = 0;
    uint256 public modePeriod = 2 hours;
    struct Fee {
        uint8 treasury;
        uint8 reflection;
        uint8 lucky;
        uint8 burn;
        uint8 total;
    }
    // mode == 0: pre fees
    // Mode 1
    Fee public mode1BuyTax = Fee({treasury: 2, reflection: 3, lucky: 0, burn: 0, total: 5});
    Fee public mode1SellTax = Fee({treasury: 2, reflection: 3, lucky: 0, burn: 0, total: 5});
    // Mode 2
    Fee public mode2BuyTax = Fee({treasury: 0, reflection: 0, lucky: 0, burn: 0, total: 0});
    Fee public mode2SellTax = Fee({treasury: 2, reflection: 2, lucky: 2, burn: 0, total: 6});
    // Mode 3
    Fee public mode3BuyTax = Fee({treasury: 0, reflection: 3, lucky: 0, burn: 1, total: 4});
    Fee public mode3SellTax = Fee({treasury: 2, reflection: 3, lucky: 0, burn: 0, total: 5});
    // Mode 4
    Fee public mode4BuyTax = Fee({treasury: 0, reflection: 0, lucky: 0, burn: 0, total: 0});
    Fee public mode4SellTax = Fee({treasury: 0, reflection: 0, lucky: 0, burn: 0, total: 0});
    // Mode 5
    Fee public mode5BuyTax = Fee({treasury: 0, reflection: 5, lucky: 0, burn: 0, total: 5});
    Fee public mode5SellTax = Fee({treasury: 0, reflection: 5, lucky: 0, burn: 0, total: 5});
    // Mode 6
    Fee public mode6BuyTax = Fee({treasury: 0, reflection: 0, lucky: 0, burn: 0, total: 0});
    Fee public mode6SellTax = Fee({treasury: 0, reflection: 5, lucky: 0, burn: 0, total: 5});
    uint256 public mode6ReflectionAmount = 0;
    uint256 public session = 0;
    // session => (buyer => true/false)
    mapping(uint256 => mapping(address => bool)) public isMode6Buyer;
    address[] public mode6Buyers;

    Fee public buyTax;
    Fee public sellTax;

    IUniswapV2Router02 public UNISWAP_V2_ROUTER;
    address public UNISWAP_V2_PAIR;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isReflectionExempt;
    mapping(address => bool) public isBalanceExempt;

    mapping(address => bool) public isHolder;
    address[] public holders;
    uint256 public totalReflectionAmount;
    uint256 public topHolderReflectionAmount;

    // events
    event UpdateMode(uint8 mode);
    event Reflection(uint256 amountAdded, uint256 totalAmountAccumulated);
    event TopHolderReflection(uint256 amountAdded, uint256 totalAmountAccumulated);
    event BuyerReflection(uint256 amountAdded, uint256 totalAmountAccumulated);
    event BuyerReflectionTransfer(address[] buyers, uint256 amount);
    event LuckyReward(address holder, uint256 amount);
    event ChangeTradingStatus(bool status);

    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor () {
        require(devAddress != msg.sender, "Please set a different wallet for devAddress");
        UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);  // mainnet = goerli
        UNISWAP_V2_PAIR = IUniswapV2Factory(UNISWAP_V2_ROUTER.factory()).createPair(address(this), UNISWAP_V2_ROUTER.WETH());
        _allowances[address(this)][address(UNISWAP_V2_ROUTER)] = _totalSupply;
        _allowances[address(this)][address(UNISWAP_V2_PAIR)] = _totalSupply;
        _allowances[address(this)][msg.sender] = _totalSupply;

        isFeeExempt[msg.sender] = true;
        isFeeExempt[devAddress] = true;
        isFeeExempt[treasuryAddress] = true;
        isFeeExempt[marketingAddress] = true;
        isFeeExempt[liquidityAddress] = true;
        isFeeExempt[ZERO] = true;
        isFeeExempt[DEAD] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[address(UNISWAP_V2_ROUTER)] = true;
        isFeeExempt[UNISWAP_V2_PAIR] = true;

        isReflectionExempt[address(this)] = true;
        isReflectionExempt[address(UNISWAP_V2_ROUTER)] = true;
        isReflectionExempt[UNISWAP_V2_PAIR] = true;
        isReflectionExempt[msg.sender] = true;
        isReflectionExempt[ZERO] = true;
        isReflectionExempt[DEAD] = true;

        isBalanceExempt[ZERO] = true;
        isBalanceExempt[DEAD] = true;
        isBalanceExempt[address(UNISWAP_V2_ROUTER)] = true;
        isBalanceExempt[address(UNISWAP_V2_PAIR)] = true;
        isBalanceExempt[devAddress] = true;
        isBalanceExempt[msg.sender] = true;
        isBalanceExempt[address(this)] = true;

        buyTax = mode1BuyTax;
        sellTax = mode1SellTax;

        uint256 devAmount = _totalSupply * 5 / 100;
        _balances[devAddress] = devAmount;
        emit Transfer(ZERO, devAddress, devAmount);
        isHolder[devAddress] = true;
        holders.push(devAddress);

        uint256 circulationAmount = _totalSupply - devAmount;
        _balances[msg.sender] = circulationAmount;
        emit Transfer(ZERO, msg.sender, circulationAmount);
        isHolder[msg.sender] = true;
        holders.push(msg.sender);
    }

    receive() external payable {}
    /**
     * ERC20 Standard methods with override
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 totalBalance = _balances[account];
        if (!isReflectionExempt[account] && totalReflectionAmount > 0 && holders.length > 2) {
            totalBalance += totalBalance / holders.length;
        }
        return totalBalance;
    }

    function allowance(address holder, address spender) external view override returns (uint256) {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, _totalSupply);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            require(_allowances[sender][msg.sender] >= amount, "ERC20: insufficient allowance");
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        _checkBuySell(sender, recipient);
        _checkLimitations(recipient, amount);
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }
        if (_shouldSwapBack()) {
            _swapBack();
        }
        if (!isReflectionExempt[sender]){
            _claim(sender);
        }
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _updateHolders(sender);
        uint256 amountReceived = _shouldTakeFee(sender, recipient) ? _takeFees(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);
        _updateHolders(recipient);
        emit Transfer(sender, recipient, amount);

        if (isAutoMode) {
            autoUpdateMode();
        }

        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _updateHolders(sender);
        _balances[recipient] = _balances[recipient].add(amount);
        _updateHolders(recipient);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function getRandomHolderIndex(uint256 _numToFetch, uint256 _i) internal view returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    msg.sender,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    blockhash(block.number - 1),
                    _numToFetch,
                    _i
                )
            )
        );
        uint256 randomIndex = (randomNum % holders.length);
        return randomIndex;
    }

    function _takePreFees(address sender, uint256 amount) internal returns (uint256) {
        uint256 _marketingFee = _sellMarketingFee;
        uint256 _liquidityFee = _sellLiquidityFee;
        uint256 _reflectionFee = _sellReflectionFee;
        uint256 _treasuryFee = _sellTreasuryFee;
        if (sender == UNISWAP_V2_PAIR) {
            _marketingFee = _buyMarketingFee;
            _liquidityFee = _buyLiquidityFee;
            _reflectionFee = _buyReflectionFee;
            _treasuryFee = _buyTreasuryFee;
        }
        uint256 _marketingAmount = amount * _marketingFee / 100;
        uint256 _liquidityAmount = amount * _liquidityFee / 100;
        uint256 _treasuryAmount = amount * _treasuryFee / 100;
        uint256 _reflectionFeeAmount = amount * _reflectionFee / 100;
        if (_reflectionFee > 0) {
            totalReflectionAmount += _reflectionFeeAmount;
            emit Reflection(_reflectionFeeAmount, totalReflectionAmount);
        }
        marketingDebt += _marketingAmount;
        liquidityDebt += _liquidityAmount;
        treasuryDebt += _treasuryAmount;
        _balances[address(this)] += _marketingAmount + _liquidityAmount + _treasuryAmount;
        uint256 _totalFeeAmount = _marketingAmount + _liquidityAmount + _treasuryAmount + _reflectionFeeAmount;
        return amount.sub(_totalFeeAmount);
    }

    function _takeModeFees(address sender, address recipient, uint256 amount) internal returns (uint256) {
        Fee memory _feeTax = sellTax;
        bool _isBuy = false;
        if (sender == UNISWAP_V2_PAIR) {
            _feeTax = buyTax;
            _isBuy = true;
        }
        uint256 feeAmount = amount * _feeTax.total / 100;
        if (_feeTax.treasury > 0) {
            uint256 _treasuryFeeAmount = feeAmount * _feeTax.treasury / _feeTax.total;
            treasuryDebt += _treasuryFeeAmount;
            _balances[address(this)] += _treasuryFeeAmount;
        }
        if (_feeTax.reflection > 0) {
            uint256 _reflectionFeeAmount = feeAmount * _feeTax.reflection / _feeTax.total;
            if (mode == 3) {
                topHolderReflectionAmount += _reflectionFeeAmount;
                emit TopHolderReflection(_reflectionFeeAmount, topHolderReflectionAmount);
            } else if (mode == 6) {
                mode6ReflectionAmount += _reflectionFeeAmount;
                if (!_isBuy) {
                    emit BuyerReflection(_reflectionFeeAmount, mode6ReflectionAmount);
                } else if (_isBuy && !isMode6Buyer[session][recipient]) {
                    isMode6Buyer[session][recipient] = true;
                    mode6Buyers.push(recipient);
                }
            } else {
                totalReflectionAmount += _reflectionFeeAmount;
                emit Reflection(_reflectionFeeAmount, totalReflectionAmount);
            }
        }
        if (_feeTax.lucky > 0) {
            uint256 _luckyFeeAmount = feeAmount * _feeTax.lucky / _feeTax.total;
            _luckyReward(_luckyFeeAmount);
        }
        if (_feeTax.burn > 0) {
            uint256 _burnFeeAmount = feeAmount * _feeTax.burn / _feeTax.total;
            _balances[DEAD] += _burnFeeAmount;
            emit Transfer(address(this), DEAD, _burnFeeAmount);
        }

        return amount.sub(feeAmount);
    }

    function _takeFees(address sender, address recipient, uint256 amount) internal returns (uint256) {
        if (mode > 0) {
            return _takeModeFees(sender, recipient, amount);
        } else {
            return _takePreFees(sender, amount);
        }
    }

    function _shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        return !isFeeExempt[sender] || !isFeeExempt[recipient];
    }

    function _checkBuySell(address sender, address recipient) internal view {
        if (!enableTrading) {
            require(sender != UNISWAP_V2_PAIR && recipient != UNISWAP_V2_PAIR, "Trading is disabled!");
        }
    }

    function _checkLimitations(address recipient, uint256 amount) internal view {
        if (!isBalanceExempt[recipient]) {
            require(amount <= maxTx, "Max transaction amount is limited!");
            uint256 suggestBalance = balanceOf(recipient) + amount;
            require(suggestBalance <= maxBalance, "Max balance is limited!");
        }
    }

    function _luckyReward(uint256 amount) internal {
        uint256 randomIndex = getRandomHolderIndex(1, 1);
        address luckyHolder = holders[randomIndex];
        if (
            luckyHolder != ZERO && 
            luckyHolder != DEAD && 
            luckyHolder != address(UNISWAP_V2_ROUTER) && 
            luckyHolder != UNISWAP_V2_PAIR
        ) {
            _balances[luckyHolder] += amount;
            emit LuckyReward(luckyHolder, amount);
            emit Transfer(address(this), luckyHolder, amount);
        }
    }
    
    function _updateHolders(address holder) internal {
        uint256 balance = balanceOf(holder);
        if (balance > 0) {
            if (!isHolder[holder]) {
                isHolder[holder] = true;
                holders.push(holder);
            }
        } else {
            if (isHolder[holder]) {
                isHolder[holder] = false;
                for(uint256 i = 0; i < holders.length - 1; i++) {
                    if (holders[i] == holder) {
                        holders[i] = holders[holders.length - 1];
                    }
                }
                holders.pop();
            }
        }
    }

    function _claim(address holder) internal {
        if (totalReflectionAmount > 0) {
            uint256 oneReflection = totalReflectionAmount / holders.length;
            totalReflectionAmount -= oneReflection;
            _balances[holder] += oneReflection;
        }
    }

    function _shouldSwapBack() internal view returns (bool) {
        return msg.sender != UNISWAP_V2_PAIR && 
            enableSwap && 
            !inSwap && 
            balanceOf(address(this)) >= swapThreshold;
    }

    function _swapBack() internal swapping {
        uint256 amountToSwap = balanceOf(address(this));
        approve(address(UNISWAP_V2_ROUTER), amountToSwap);
        // swap
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = UNISWAP_V2_ROUTER.WETH();
        UNISWAP_V2_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap, 0, path, address(this), block.timestamp
        );
        uint256 amountETH = address(this).balance;
        _sendFeeETH(amountETH, amountToSwap);
    }

    function _sendFeeETH(uint256 amount, uint256 swapAmount) internal {
        uint256 totalDebt = marketingDebt + liquidityDebt + treasuryDebt;
        uint256 marketingProfit = amount * marketingDebt / totalDebt;
        uint256 marketingSwapAmount = swapAmount * marketingDebt / totalDebt;
        uint256 liquidityProfit = amount * liquidityDebt / totalDebt;
        uint256 liquiditySwapAmount = swapAmount * liquidityDebt / totalDebt;
        uint256 treasuryProfit = amount - marketingProfit - liquidityProfit;
        uint256 treasurySwapAmount = swapAmount - marketingSwapAmount - liquiditySwapAmount;
        if (marketingProfit > 0) {
            payable(marketingAddress).transfer(marketingProfit);
            marketingDebt -= marketingSwapAmount;
        }
        if (liquidityProfit > 0) {
            payable(liquidityAddress).transfer(liquidityProfit);
            liquidityDebt -= liquiditySwapAmount;
        }
        if (treasuryProfit > 0) {
            payable(treasuryAddress).transfer(treasuryProfit);
            treasuryDebt -= treasurySwapAmount;
        }
    }

    function _mode6Distribution() internal {
        session += 1;
        uint256 _buyersLen = mode6Buyers.length;
        if (mode6ReflectionAmount == 0 || _buyersLen == 0) return;
        uint256 _buyerReflection = mode6ReflectionAmount / _buyersLen;
        for (uint256 i = 0; i < _buyersLen; i++) {
            address _buyer = mode6Buyers[i];
            _balances[_buyer] += _buyerReflection;
        }
        mode6ReflectionAmount = 0;
        delete mode6Buyers;
        emit BuyerReflectionTransfer(mode6Buyers, _buyerReflection);
    }

    function _changeMode(uint8 mode_) internal {
        if (mode == 6 && mode_ != 6) {
            _mode6Distribution();
        }
        if (mode_ == 2) {
            buyTax = mode2BuyTax;
            sellTax = mode2SellTax;
        } else if (mode_ == 3) {
            buyTax = mode3BuyTax;
            sellTax = mode3SellTax;
        } else if (mode_ == 4) {
            buyTax = mode4BuyTax;
            sellTax = mode4SellTax;
        } else if (mode_ == 5) {
            buyTax = mode5BuyTax;
            sellTax = mode5SellTax;
        } else if (mode_ == 6) {
            buyTax = mode6BuyTax;
            sellTax = mode6SellTax;
        } else {
            buyTax = mode1BuyTax;
            sellTax = mode1SellTax;
        }
        mode = mode_;
        modeStartTime = block.timestamp;
        emit UpdateMode(mode_);
    }

    function autoUpdateMode() internal {
        uint8 _currentMode = mode;
        if (_currentMode == 0) {
            return;
        }
        uint256 deltaTime = block.timestamp - modeStartTime;
        if (deltaTime < modePeriod) {
            return;
        }
        _currentMode += 1;
        if (_currentMode > 6) {
            _currentMode = 1;
        }
        _changeMode(_currentMode);
    }

    function manualUpdateMode(uint8 mode_) external onlyOwner {
        _changeMode(mode_);
    }

    function setAutoMode(bool isAuto_) external onlyOwner {
        isAutoMode = isAuto_;
    }

    function rewardTopHolders(address[] calldata _topHolders) public onlyOwner {
        require(topHolderReflectionAmount > 0, "Reward should be available");
        uint256 oneReward = topHolderReflectionAmount / _topHolders.length;
        topHolderReflectionAmount = 0;
        for (uint8 i = 0; i < _topHolders.length; i++) {
            _balances[_topHolders[i]] += oneReward;
            emit Transfer(address(this), _topHolders[i], oneReward);
        }
    }

    function setFeeReceivers(address treasury_) external onlyOwner {
        treasuryAddress = treasury_;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setIsReflectionExempt(address holder, bool exempt) external onlyOwner {
        isReflectionExempt[holder] = exempt;
    }

    function setIsBalanceExempt(address holder, bool exempt) external onlyOwner {
        isBalanceExempt[holder] = exempt;
    }

    function changeTradingStatus(bool _status) external onlyOwner {
        enableTrading = _status;
        emit ChangeTradingStatus(_status);
    }

    function updatePreFees(
        uint256 buyMarketingFee_,
        uint256 buyLiquidityFee_,
        uint256 buyReflectionFee_,
        uint256 buyTreasuryFee_,
        uint256 sellMarketingFee_,
        uint256 sellLiquidityFee_,
        uint256 sellReflectionFee_,
        uint256 sellTreasuryFee_
    ) external onlyOwner {
        _buyMarketingFee = buyMarketingFee_;
        _buyLiquidityFee = buyLiquidityFee_;
        _buyReflectionFee = buyReflectionFee_;
        _buyTreasuryFee = buyTreasuryFee_;

        _sellMarketingFee = sellMarketingFee_;
        _sellLiquidityFee = sellLiquidityFee_;
        _sellReflectionFee = sellReflectionFee_;
        _sellTreasuryFee = sellTreasuryFee_;
    }

    function updateSwapThreshold(uint256 _swapThreshold) external onlyOwner {
        swapThreshold = _swapThreshold;
    }

    function manualSwapBack() external onlyOwner {
        if (_shouldSwapBack()) {
            _swapBack();
        }
    }

    function changeSwapStatus(bool _enableSwap) external onlyOwner {
        enableSwap = _enableSwap;
    }
}