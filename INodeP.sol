// SPDX-License-Identifier: MIT


pragma solidity ^0.8.26;

interface INode {
    enum Variant {
        Short,
        Long
    }
    enum CellState {
        None,
        Opened,
        Closed
    }

    struct Cell {
        bool defined;
        CellState cellState;
        uint256 sPrice;
        uint256 lPrice;
        uint256 sold;
        uint256 supply;
    }

    struct RefData {
        bool defined;
        bool enabled;
        uint256 firstRefCodeRate;
        uint256 secondRefCodeRate;
    }

    struct AdditionalRewardInfoCell {
        uint256 percent;
        uint256 limit;
    }

    event CellStateUpdated(CellState cellState);
    event CellOpened(uint256 indexed cell);
    event CellClosed(uint256 indexed cell);
    event CellAdded(uint256 sPrice, uint256 lPrice, uint256 supply);
    event CellPriceUpdated(uint256 indexed cell, uint256 sPrice, uint256 lPrice);
    event CellSupplyUpdated(uint256 indexed cell, uint256 supply);
    event Erc20RefRecovered(address token, uint256 amount);
    event CoinRefRecovered(uint256 amount);
    event VerifiedLimitUpdated(uint256 limit);
    event VerifiedUserUpdated(address indexed user, bool value);
    event MaxAmountInUpdated(uint256 amount);
    event MinAmountInUpdated(uint256 amount);
    event TreasuryUpdated(address indexed treasury);
    event RefCodeRateSetup(uint256 firstRefCodeRate, uint256 secondRefCodeRate);
    event RefDataSetup(string code, uint256 firstRefCodeRate, uint256 secondRefCodeRate);
    event RefDataEnabled(string code);
    event RefDataDisabled(string code);
    event RefCodeRewardsClaimed(string code, address indexed token, uint256 amount);
    event SignerSet(address signer);

    error ParamsInvalidError();
    error OpenedError();
    error ClosedError();
    error ZeroAddressError();
    error CellUndefinedError();
    error CellStartedError();
    error CellClosedError();
    error CellSupplyError();
    error MinAmountInError();
    error MaxAmountInError();
    error ValidatedLimitError();
    error FirstRefCodeFundsError();
    error SecondRefCodeFundsError();
    error RefCodeUndefinedError();
    error RefCodeEnabledError();
    error RefCodeDisabledError();
    error TokenUndefinedError();
    error TransferNativeError();
    error SignerNotSetError();
    error TransactionExpiredError();
    error InvalidSignerError();
    error HashAlreadyUsedError();
    error InvalidArrayLengthError();
    error EthCallError();
    error InvalidAdditionalRewardArraysValue();

    function globalOpen() external;
    function globalClose() external;
    function addNewCell(uint256 sPrice_, uint256 lPrice_, uint256 supply_) external;
    function setupRefCodeRate(uint256 firstRefCodeRate_, uint256 secondRefCodeRate_) external;
    function setupRefData(
        string[] calldata refs_,
        uint256[] calldata firstRefCodeRate_,
        uint256[] calldata secodRefCodeFunds_
    ) external;
    function updateCellPrice(uint256 index_, uint256 sPrice_, uint256 lPrice_) external;
    function updateCellSupply(uint256 index_, uint256 supply_) external;
    function openCell(uint256 index_) external;
    function closeCell(uint256 index_) external;
    function addValidated(address user_, bool value_) external;
    function addValidatedBatch(address[] calldata users_, bool[] calldata values_) external;
    function setMaxAmountIn(uint256 amount_) external;
    function setMinAmountIn(uint256 amount_) external;
    function setValidatedLimit(uint256 amount_) external;
    function setTreasury(address treasury_) external;
    function setCellState(
        address user_,
        address token_,
        uint256 amount_,
        uint256 sold_,
        string calldata code_,
        uint256 fReward_,
        uint256 sReward_
    ) external;
    function enableRefData(string calldata code_) external;
    function disableRefData(string calldata code_) external;
    function claimRefCode(address[] memory tokens_, string memory code_, uint256 deadline_, uint8 v, bytes32 r, bytes32 s) external;
    function recoverETH() external;
    function recoverERC20(address token_, uint256 amount_) external;
    function getTreasury() external view returns (address);
    function getMaxAmountIn() external  view returns (uint256);
    function getMinAmountIn() external view returns (uint256);
    function getCellsCount() external view returns (uint256);
    function getCurrentCell() external view returns (uint256);
    function getCell(uint256 index_) external view returns (Cell memory);
    function getTotalRaised() external view returns (uint256);
    function userFundsByCell(uint256 turn_, address user_) external view returns (uint256);
    function codeBalanceOf(address token_, string calldata user_) external view returns (uint256);
    function limitOf(address user_) external view returns (uint256);
    function maxLimitOf(address user_) external view returns (uint256);
    function getValidatedLimit() external view returns (uint256);
    function getRates() external view returns (uint256, uint256);
    function getRefCode(address user_, string calldata code_) external view returns (string memory);
    function getRefCodeRates(string calldata code_) external view returns (uint256, uint256);
    function getPrice(Variant type_) external view returns (uint256);
    function getGlobalStatus() external view returns (INode.CellState);
    function isValidated(address user_) external view returns (bool);
    function setTrustRefData(bool value) external;
    function getAdditionalRewardInfo() external view returns(AdditionalRewardInfoCell[] memory);
    function setAdditionalInfo(uint256[] calldata percents_, uint256[] calldata limits_) external;
    function calculateAdditionalReward(uint256 usdAmount_, uint256 tokenAmount_) external view returns(uint256);
}