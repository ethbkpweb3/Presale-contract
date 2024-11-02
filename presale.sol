// SPDX-License-Identifier: MIT





pragma solidity 0.8.26;

import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./Globalsd.sol";
import "./INodeP.sol";

contract NodeP23 is Globals, EIP712, AccessControl, ReentrancyGuard, INode {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using Strings for string;

    address private _treasury;
    uint256 private _totalRaised;
    uint256 private _currentCell;
    uint256 private _maxAmountIn;
    uint256 private _minAmountIn;
    uint256 private _validatedLimit;
    uint256 private _refCodeRate1;
    uint256 private _refCodeRate2;
    AdditionalRewardInfoCell[] private _additionalRewards;
    address private _signer;
    CellState private _globalCellState;

    mapping(address => bool) private _validated;
    mapping(address => uint256) private _userFunds;
    mapping(address => mapping(uint256 => uint256)) private _fundsByCell;
    mapping(address => string) private _referralCodeUsers;
    mapping(string => mapping(address => uint256)) private _referralCodeAmount;
    mapping(string => RefData) private _refData;
    mapping(bytes32 => bool) private _used;
    Cell[] private _cells;

    bool public trustRefData;

    constructor(address treasury_, address signer_) EIP712("Node", "1") {
        require(treasury_ != address(0), ZeroAddressError());

        _treasury = treasury_;
        _signer = signer_;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(NODE_OPERATOR_ROLE, _msgSender());
        _grantRole(NODE_RUNNER_ROLE, _msgSender());
        _grantRole(RECEIVER_ROLE, _msgSender());
    }

    function globalOpen() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_globalCellState == CellState.None, OpenedError());
        _globalCellState = CellState.Opened;

        emit CellStateUpdated(_globalCellState);
    }

    function globalClose() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_globalCellState == CellState.Opened, ClosedError());
        _globalCellState = CellState.Closed;

        emit CellStateUpdated(_globalCellState);
    }

    function addNewCell(
        uint256 sPrice_,
        uint256 lPrice_,
        uint256 supply_
    ) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_globalCellState != CellState.Closed, ClosedError());

        _cells.push(
            Cell({
                defined: true,
                cellState: CellState.None,
                sPrice: sPrice_,
                lPrice: lPrice_,
                sold: 0,
                supply: supply_
            })
        );

        emit CellAdded(sPrice_, lPrice_, supply_);
    }

    function setupRefCodeRate(
        uint256 refCodeRate1_,
        uint256 refCodeRate2_
    ) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_globalCellState != CellState.Closed, ClosedError());
        require(refCodeRate1_ <= 1000, FirstRefCodeFundsError());
        require(refCodeRate2_ <= 1000, SecondRefCodeFundsError());

        _refCodeRate1 = refCodeRate1_;
        _refCodeRate2 = refCodeRate2_;

        emit RefCodeRateSetup(_refCodeRate1, _refCodeRate2);
    }

    function setupRefData(
        string[] calldata referralCode_,
        uint256[] calldata firstRefCodeRate_,
        uint256[] calldata secondRefCodeRate_
    ) external onlyRole(NODE_RUNNER_ROLE) {
        require(_globalCellState != CellState.Closed, ClosedError());
        require(referralCode_.length == firstRefCodeRate_.length && referralCode_.length == secondRefCodeRate_.length, ParamsInvalidError());

        for (uint256 index = 0; index < referralCode_.length; index++) {
            _refData[referralCode_[index]] = RefData({
                defined: true,
                enabled: true,
                firstRefCodeRate: firstRefCodeRate_[index],
                secondRefCodeRate: secondRefCodeRate_[index]
            });

            emit RefDataSetup(referralCode_[index], firstRefCodeRate_[index], secondRefCodeRate_[index]);
        }
    }

    function updateCellPrice(
        uint256 index_,
        uint256 sPrice_,
        uint256 lPrice_
    ) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_globalCellState == CellState.Opened, ClosedError());
        require(_cells[index_].defined, CellUndefinedError());
        require(_cells[index_].cellState == CellState.None, CellStartedError());

        _cells[index_].sPrice = sPrice_;
        _cells[index_].lPrice = lPrice_;

        emit CellPriceUpdated(index_, sPrice_, lPrice_);
    }

    function updateCellSupply(
        uint256 index_,
        uint256 supply_
    ) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_globalCellState != CellState.Closed, ClosedError());
        require(_cells[index_].defined, CellUndefinedError());
        require(_cells[index_].cellState != CellState.Closed, CellClosedError());
        require(_cells[index_].sold <= supply_, CellSupplyError());

        _cells[index_].supply = supply_;

        emit CellSupplyUpdated(index_, supply_);
    }

    function openCell(uint256 index_) external onlyRole(NODE_RUNNER_ROLE) {
        require(_globalCellState == CellState.Opened, ClosedError());
        require(_cells[index_].defined, CellUndefinedError());
        require(_cells[index_].cellState == CellState.None, CellStartedError());

        if (_cells[_currentCell].cellState == CellState.Opened) {
            _cells[_currentCell].cellState = CellState.Closed;
        }
        _cells[index_].cellState = CellState.Opened;
        _currentCell = index_;

        emit CellOpened(index_);
    }

    function closeCell(uint256 index_) external onlyRole(NODE_RUNNER_ROLE) {
        require(_cells[index_].defined, CellUndefinedError());
        require(_cells[index_].cellState == CellState.Opened, CellClosedError());

        _cells[index_].cellState = CellState.Closed;

        emit CellClosed(index_);
    }

    function addValidated(address user_, bool value_) external onlyRole(NODE_RUNNER_ROLE) {
        _validated[user_] = value_;

        emit VerifiedUserUpdated(user_, value_);
    }

    function addValidatedBatch(
        address[] calldata users_,
        bool[] calldata values_
    ) external onlyRole(NODE_RUNNER_ROLE) {
        require(users_.length == values_.length, ParamsInvalidError());

        for (uint256 index = 0; index < users_.length; index++) {
            _validated[users_[index]] = values_[index];

            emit VerifiedUserUpdated(users_[index], values_[index]);
        }
    }

    function setMaxAmountIn(uint256 amount_) external onlyRole(NODE_OPERATOR_ROLE) {
        require(amount_ <= MAX, MaxAmountInError());
        require(amount_ >= _minAmountIn, MinAmountInError());

        _maxAmountIn = amount_;

        emit MaxAmountInUpdated(_maxAmountIn);
    }

    function setMinAmountIn(uint256 amount_) external onlyRole(NODE_OPERATOR_ROLE) {
      require(amount_ >= MIN, MinAmountInError());
      require(amount_ <= _maxAmountIn, MaxAmountInError());

        _minAmountIn = amount_;

        emit MinAmountInUpdated(_minAmountIn);
    }

    function setValidatedLimit(uint256 amount_) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_minAmountIn <= amount_ && amount_ <= _maxAmountIn, ValidatedLimitError());

        _validatedLimit = amount_;

        emit VerifiedLimitUpdated(amount_);
    }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(treasury_ != address(0), ZeroAddressError());

        _treasury = treasury_;

        emit TreasuryUpdated(_treasury);
    }

    function setSigner(address signer_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _signer = signer_;

        emit SignerSet(signer_);
    }

    function setCellState(
        address user_,
        address token_,
        uint256 amount_,
        uint256 sold_,
        string calldata referralCode_,
        uint256 fReward_,
        uint256 sReward_
    ) external onlyRole(RECEIVER_ROLE) {
        _userFunds[user_] = _userFunds[user_] + amount_;
        _totalRaised = _totalRaised + sold_;
        _cells[_currentCell].sold = _cells[_currentCell].sold + sold_;
        _fundsByCell[user_][_currentCell] = _fundsByCell[user_][_currentCell] + sold_;

        if (!referralCode_.equal("")) {
            if (!_refData[referralCode_].defined) {
                _refData[referralCode_].defined = true;
                _refData[referralCode_].enabled = true;

                emit RefDataSetup(referralCode_, _refCodeRate1, _refCodeRate2);
            }
            _referralCodeAmount[referralCode_][token_] += fReward_;
            _referralCodeAmount[referralCode_][TOKEN] += sReward_;
            _referralCodeUsers[user_] = referralCode_;
        }
    }

    function setTrustRefData(bool value) external onlyRole(NODE_OPERATOR_ROLE) {
      trustRefData = value;
    }

    function setAdditionalInfo(uint256[] calldata percents_, uint256[] calldata limits_) external onlyRole(NODE_OPERATOR_ROLE) {
        require(percents_.length == limits_.length, InvalidArrayLengthError());

        delete _additionalRewards;

        for (uint256 idx = 0; idx < percents_.length; idx++) {
            if (idx == 0) {
                require(percents_[0] != 0 && limits_[0] != 0, InvalidAdditionalRewardArraysValue());
            } else {
                require(percents_[idx - 1] < percents_[idx] && limits_[idx - 1] < limits_[idx], InvalidAdditionalRewardArraysValue());
            }

            _additionalRewards.push(AdditionalRewardInfoCell({
                limit: limits_[idx],
                percent: percents_[idx]
            }));
        }
    }

    function enableRefData(string calldata referralCode_) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_refData[referralCode_].defined, RefCodeUndefinedError());
        require(!_refData[referralCode_].enabled, RefCodeEnabledError());

        _refData[referralCode_].enabled = true;

        emit RefDataEnabled(referralCode_);
    }

    function disableRefData(string calldata referralCode_) external onlyRole(NODE_OPERATOR_ROLE) {
        require(_refData[referralCode_].defined, RefCodeUndefinedError());
        require(_refData[referralCode_].enabled, RefCodeDisabledError());

        _refData[referralCode_].enabled = false;

        emit RefDataDisabled(referralCode_);
    }

    function _buildHash(address[] memory tokens_, string memory referralCode_, address receiver_, uint256 deadline_) pure private returns(bytes32) {
       return keccak256(
         abi.encode(
           CLAIM_REF_CODE_TYPEHASH,
           keccak256(abi.encodePacked(tokens_)),
           keccak256(bytes(referralCode_)),
           receiver_,
           deadline_
         )
       );
    }

  function claimRefCode(address[] memory tokens_, string memory referralCode_, uint256 deadline_, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
      address receiver_ = _msgSender();
      require(_signer != address(0), SignerNotSetError());
      require(deadline_ > block.timestamp, TransactionExpiredError());

      for (uint256 i = 0; i < tokens_.length; i++) {
        address token = tokens_[i];
        uint256 balance = _referralCodeAmount[referralCode_][token];
        if (balance == 0) {
          continue;
        }

        _referralCodeAmount[referralCode_][token] = 0;
        if (token == ETH_ADDRESS) {
          (bool success, ) = receiver_.call{value: balance}("");
          require(success, EthCallError());
        } else {
          IERC20(token).safeTransfer(receiver_, balance);
        }

        emit RefCodeRewardsClaimed(referralCode_, token, balance);
      }
    }

    function recoverETH() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        _msgSender().call{value: balance}("");

        emit CoinRefRecovered(balance);
    }

    function recoverERC20(address token_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token_).safeTransfer(_msgSender(), amount_);

        emit Erc20RefRecovered(token_, amount_);
    }

    function getTreasury() external view returns (address) {
        return _treasury;
    }

    function getMaxAmountIn() external view returns (uint256) {
        return _maxAmountIn;
    }

    function getMinAmountIn() external view returns (uint256) {
        return _minAmountIn;
    }

    function getCellsCount() external view returns (uint256) {
        return _cells.length;
    }

    function getCurrentCell() external view returns (uint256) {
        return _currentCell;
    }

    function getCell(uint256 index_) external view returns (Cell memory) {
        return _cells[index_];
    }

    function getTotalRaised() external view returns (uint256) {
        return _totalRaised;
    }

    function userFundsByCell(uint256 cell_, address user_) external view returns (uint256) {
        return _fundsByCell[user_][cell_];
    }

    function codeBalanceOf(address token_, string calldata referralCode_) external view returns (uint256) {
        return _referralCodeAmount[referralCode_][token_];
    }

    function limitOf(address user_) external view returns (uint256) {
        uint256 amount = _userFunds[user_];
        uint256 limit = _validatedLimit;
        if (isValidated(user_)) {
            limit = _maxAmountIn;
        }
        return amount < limit ? limit - amount : 0;
    }

    function maxLimitOf(address user_) external view returns (uint256) {
        uint256 amount = _userFunds[user_];
        return amount < _maxAmountIn ? _maxAmountIn - amount : 0;
    }

    function getValidatedLimit() external view returns (uint256) {
        return _validatedLimit;
    }

    function getRates() external view returns (uint256, uint256) {
        return (_refCodeRate1, _refCodeRate2);
    }

    function getRefCode(address user_, string calldata referralCode_) external view returns (string memory) {
        if (trustRefData) {
          return referralCode_;
        }

        RefData memory referralCode = _refData[_referralCodeUsers[user_]];
        if (referralCode.defined && referralCode.enabled) {
            return _referralCodeUsers[user_];
        }
        referralCode = _refData[referralCode_];
        if (!referralCode.defined || referralCode.enabled) {
            return referralCode_;
        }
        return "";
    }

    function getRefCodeRates(string calldata referralCode_) external view returns (uint256, uint256) {
        RefData memory referralCode = _refData[referralCode_];
        if (referralCode.defined) {
            return (
                Math.max(referralCode.firstRefCodeRate, _refCodeRate1),
                Math.max(referralCode.secondRefCodeRate, _refCodeRate2)
            );
        }
        return (_refCodeRate1, _refCodeRate2);
    }

    function getGlobalStatus() public view returns (INode.CellState) {
        return _globalCellState;
    }

    function getPrice(Variant type_) public view returns (uint256) {
        if (_cells[_currentCell].cellState == CellState.Opened) {
            return
                type_ == Variant.Short
                    ? _cells[_currentCell].sPrice
                    : _cells[_currentCell].lPrice;
        }
        return 0;
    }

    function isValidated(address user_) public view returns (bool) {
        return _validated[user_];
    }

    function getAdditionalRewardInfo() external view returns (AdditionalRewardInfoCell[] memory) {
        return _additionalRewards;
    }

    function calculateAdditionalReward(uint256 usdAmount_, uint256 tokenAmount_) external view returns(uint256) {
        if (_additionalRewards.length == 0) {
            return 0;
        }
        
        int256 target = -1;

        for (uint256 idx = 0; idx < _additionalRewards.length; idx++) {
            if (usdAmount_ >= _additionalRewards[idx].limit) {
                target = int256(idx);
            } else {
                break;
            }
        }

        if (target == -1) {
            return 0;
        }

        return tokenAmount_ * _additionalRewards[uint256(target)].percent / (10 ** PRECISION);
    }

    receive() external payable {}
}