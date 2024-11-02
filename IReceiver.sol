// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IReceiver {
  error GlobalClosedError();
  error CellClosedError();
  error ZeroAddressError();
  error PayerZeroAddressError();
  error CellAllocationError();
  error PriceThresholdError();
  error UserZeroAddressError();
  error AmountZeroError();
  error RecommenderError();
  error TransferNativeError();
  error MinAmountInError();
  error MaxAmountInError();
  error ArrayLengthError();
  error TokenAlreadyAddedError();
  error TokenNotAddedError();

}