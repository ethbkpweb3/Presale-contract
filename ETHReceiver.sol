// SPDX-License-Identifier: MIT



pragma solidity 0.8.26;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import "./Globals2.sol";
import "./INodes.sol";
import "./IReceivers.sol";

contract ETHReceiver is IReceiver, Globals, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using Strings for string;

    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 private _totalRaised;
    INode private _node;

    IPyth private _priceFeed;
    bytes32 private _priceFeedID;
    uint256 private _priceThreshold;

    event PriceThresholdUpdated(uint256 priceFeedTimeThreshold);
    event Erc20Recovered(address token, uint256 amount);
    event ETHRecovered(uint256 amount);
    event ETHPayed(
        address indexed payer,
        string code,
        uint256 amount,
        INode.Variant indexed variant,
        uint256 liquidity,
        uint256 usdAmount,
        uint256 cell
    );

    constructor(
        address payable node_,
        address priceFeed_,
        bytes32 priceFeedID_,
        uint256 priceThreshold_
    ) {
        require(node_ != address(0) && priceFeed_ != address(0), ZeroAddressError());
        require(priceThreshold_ != 0, PriceThresholdError());

        _node = INode(node_);
        _priceFeed = IPyth(priceFeed_);
        _priceThreshold = priceThreshold_;
        _priceFeedID = priceFeedID_;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setPriceFeedAddress(address priceFeed_) external onlyRole(DEFAULT_ADMIN_ROLE) {
      _priceFeed = IPyth(priceFeed_);
    }

    function setPriceFeedID(bytes32 pythPriceFeedID_) external onlyRole(DEFAULT_ADMIN_ROLE) {
      _priceFeedID = pythPriceFeedID_;
    }

    function payETH(INode.Variant variant_, string calldata code_) external payable nonReentrant {
        _pay(variant_, _msgSender(), code_, false);
    }

    function payETHFor(
        INode.Variant variant_,
        address payer_,
        string calldata code_
    ) external payable onlyRole(VERIFIED_ROLE) nonReentrant {
        _pay(variant_, payer_, code_, true);
    }

    function setPriceThreshold(uint256 priceThreshold_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(priceThreshold_ > 0, PriceThresholdError());
        _priceThreshold = priceThreshold_;

        emit PriceThresholdUpdated(priceThreshold_);
    }

function recoverETH() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 balance = address(this).balance;

    // Perform the ETH transfer and capture the success status
    (bool success, ) = _msgSender().call{value: balance}("");

    // Check if the call was successful
    require(success, "ETH transfer failed");

    // Emit the event after the successful transfer
    emit ETHRecovered(balance);
}


    function recoverErc20(address token_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token_).safeTransfer(_msgSender(), amount_);

        emit Erc20Recovered(token_, amount_);
    }

    function getNode() external view returns (address) {
        return address(_node);
    }

    function getTotalRaised() external view returns (uint256) {
        return _totalRaised;
    }

    function getPriceThreshold() external view returns (uint256) {
        return _priceThreshold;
    }

    function _pay(
        INode.Variant variant_,
        address payer_,
        string memory code_,
        bool max_
    ) internal whenNotPaused {
        uint256 amount = msg.value;
        require(payer_ != address(0), PayerZeroAddressError());
        require(amount > 0, AmountZeroError());
        require(_node.getGlobalStatus() == INode.CellState.Opened, GlobalClosedError());

        PythStructs.Price memory PFData = _priceFeed.getPriceUnsafe(_priceFeedID);
        INode.Cell memory cell = _node.getCell(_node.getCurrentCell());

        require(cell.cellState == INode.CellState.Opened, CellClosedError());
        (uint256 liquidity, uint256 usdAmount) = _getLiquidity(amount, variant_, PFData);
        liquidity = _addAdditionalReward(liquidity, usdAmount);
        require(cell.supply >= cell.sold + liquidity, CellAllocationError());

        uint8 decimals = uint8(uint32(-1 * PFData.expo));
        uint256 price = uint256(uint64(PFData.price));

        require(block.timestamp - PFData.publishTime <= _priceThreshold, PriceThresholdError());

        uint256 funds = (amount * price * NUMERATOR) / (10 ** (DECIMALS + decimals));
        require(_node.getMinAmountIn() <= funds, MinAmountInError());

        uint256 limit = max_ ? _node.maxLimitOf(payer_) : _node.limitOf(payer_);
        require(limit >= funds, MaxAmountInError());

        (string memory code, uint256 coinFunds, uint256 tokenFunds) = _getRefCode(
            payer_,
            code_,
            variant_,
            amount,
            PFData
        );
        _purchase(amount, coinFunds);

        _totalRaised = _totalRaised + amount;
//        (uint256 liquidity, uint256 usdAmount) = _getLiquidity(amount, variant_, PFData);
        _node.setCellState(payer_, ETH_ADDRESS, funds, liquidity, code, coinFunds, tokenFunds);

        emit ETHPayed(payer_, code, amount, variant_, liquidity, usdAmount, _node.getCurrentCell());
    }

    function _purchase(uint256 amount_, uint256 reward_) internal {
        address treasury = _node.getTreasury();
        (bool success, ) = treasury.call{value: amount_ - reward_}("");
        require(success, TransferNativeError());

        if (reward_ > 0) {
            (success, ) = address(_node).call{value: reward_}("");
            require(success, TransferNativeError());
        }
    }

    function _getRefCode(
        address payer_,
        string memory code_,
        INode.Variant variant_,
        uint256 amount_,
        PythStructs.Price memory PFData
    ) internal view returns (string memory code, uint256, uint256) {
        code = _node.getRefCode(payer_, code_);
        if (code.equal("")) {
            return (code, 0, 0);
        }
        (uint256 fRate, uint256 sRate) = _node.getRefCodeRates(code);
        uint256 coinFunds = (amount_ * fRate) / 1000;
        uint256 tokenFunds = (amount_ * sRate) / 1000;

        (uint256 liquidity,) = _getLiquidity(tokenFunds, variant_, PFData);

        return (code, coinFunds, liquidity);
    }

    function _getLiquidity(
        uint256 amount_,
        INode.Variant variant_,
        PythStructs.Price memory PFData
    ) internal view returns (uint256 tokenAmount, uint256 amountInUSD) {
        require(block.timestamp - PFData.publishTime <= _priceThreshold, PriceThresholdError());
        amountInUSD = (amount_ * uint256(uint64(PFData.price))) / (10 ** uint8(uint32(-1 * PFData.expo)));
        tokenAmount = amountInUSD * NUMERATOR / _node.getPrice(variant_);
    }

    function _addAdditionalReward(uint256 tokenAmount, uint256 amountInUSD) internal view returns(uint256) {
        uint256 bonus = _node.calculateAdditionalReward(amountInUSD, tokenAmount);
        return tokenAmount + bonus;
    }

    receive() external payable {}
}