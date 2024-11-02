// SPDX-License-Identifier: MIT









pragma solidity 0.8.26;


import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./Globals.sol";
import "./INode.sol";
import "./IReceiver.sol";

contract USDReceiver is IReceiver, Globals, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Strings for string;

    struct Token {
        bool defined;
        uint256 totalRaised;
    }

    mapping(address => Token) private _tokens;
    
    INode private _node;

    event TokensPayed (
        address indexed payer,
        address indexed token,
        string code,
        uint256 amount,
        INode.Variant variant,
        uint256 liquidity,
        uint256 usdAmount,
        uint256 cell
    );

    constructor(address node_, address[] memory tokens_) {
        require(node_ != address(0), ZeroAddressError());

        for (uint256 index = 0; index < tokens_.length; index++) {
            require(tokens_[index] != address(0), ZeroAddressError());
            _tokens[tokens_[index]] = Token({defined: true, totalRaised: 0});
        }
        _node = INode(node_);

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function payUSD(
        address token_,
        uint256 amount_,
        INode.Variant variant_,
        string calldata code_
    ) external nonReentrant {
        _payUSD(token_, amount_, variant_, _msgSender(), code_, false);
    }

    function payUSDFor(
        address token_,
        uint256 amount_,
        INode.Variant variant_,
        address payer_,
        string calldata code_
    ) external nonReentrant onlyRole(VERIFIED_ROLE) {
        _payUSD(token_, amount_, variant_, payer_, code_, true);
    }

    function recoverErc20(address token_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token_).safeTransfer(_msgSender(), amount_);
    }

    function isToken(address token_) external view returns (bool) {
        return _tokens[token_].defined;
    }

    function getNode() external view returns (address) {
        return address(_node);
    }

    function getTotalRaised(address token_) external view returns (uint256) {
        return _tokens[token_].totalRaised;
    }

    function _payUSD(
        address token_,
        uint256 amount_,
        INode.Variant variant_,
        address payer_,
        string calldata code_,
        bool max_
    ) internal whenNotPaused {
        require(payer_ != address(0), PayerZeroAddressError());

        require(amount_ > 0, AmountZeroError());
        require(_tokens[token_].defined, TokenNotAddedError());
        require(_node.getGlobalStatus() == INode.CellState.Opened, GlobalClosedError());

        INode.Cell memory cell = _node.getCell(_node.getCurrentCell());
        require(cell.cellState == INode.CellState.Opened, CellClosedError());
        (uint256 liquidity, uint256 usdAmount) = _getLiquidity(token_, amount_, variant_);
        liquidity = _addAdditionalReward(liquidity, usdAmount);

        require(cell.supply >= cell.sold + liquidity, CellAllocationError());
        uint256 decimals = IERC20Metadata(token_).decimals();
        uint256 funds = (amount_ * NUMERATOR) / (10 ** decimals);

        require(_node.getMinAmountIn() <= funds, MinAmountInError());

        uint256 limit = max_ ? _node.maxLimitOf(payer_) : _node.limitOf(payer_);

        require(limit >= funds, MaxAmountInError());

        (string memory code, uint256 fTokenFunds, uint256 sTokenFunds) = _getRefCode(
            payer_,
            token_,
            code_,
            variant_,
            amount_
        );
        _purchase(_msgSender(), token_, amount_, fTokenFunds);

        _tokens[token_].totalRaised = _tokens[token_].totalRaised + amount_;
//        (uint256 liquidity, uint256 usdAmount) = _getLiquidity(token_, amount_, variant_);

        _node.setCellState(payer_, token_, funds, liquidity, code, fTokenFunds, sTokenFunds);

        emit TokensPayed(
            payer_,
            token_,
            code,
            amount_,
            variant_,
            liquidity,
            usdAmount,
            _node.getCurrentCell()
        );
    }

    function _purchase(address payer_, address token_, uint256 amount_, uint256 reward_) internal {
        address treasury = _node.getTreasury();
        IERC20(token_).safeTransferFrom(payer_, treasury, amount_ - reward_);
        if (reward_ > 0) {
            IERC20(token_).safeTransferFrom(payer_, address(_node), reward_);
        }
    }

    function _getRefCode(
        address payer_,
        address token_,
        string calldata code_,
        INode.Variant variant_,
        uint256 amount_
    ) internal view returns (string memory, uint256, uint256) {
        string memory code = _node.getRefCode(payer_, code_);
        if (code.equal("")) {
            return (code, 0, 0);
        }
        (uint256 fReward_, uint256 secondaryReward_) = _node.getRefCodeRates(code);
        uint256 fTokenFunds = (amount_ * fReward_) / 1000;
        uint256 sTokenFunds = (amount_ * secondaryReward_) / 1000;
        (uint256 liquidity,) = _getLiquidity(token_, sTokenFunds, variant_);

        return (code, fTokenFunds, liquidity);
    }

    function _getLiquidity(
        address token_,
        uint256 amount_,
        INode.Variant variant_
    ) internal view returns (uint256 tokenAmount, uint256 amountInUSD) {
        uint8 decimals = IERC20Metadata(token_).decimals();

        amountInUSD = (amount_ * 10 ** DECIMALS) / 10 ** decimals;
        tokenAmount = amountInUSD * NUMERATOR / _node.getPrice(variant_);
    }

    function _addAdditionalReward(uint256 tokenAmount, uint256 amountInUSD) internal view returns(uint256) {
        uint256 bonus = _node.calculateAdditionalReward(amountInUSD, tokenAmount);
        return tokenAmount + bonus;
    }
}