// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract Globals {
  bytes32 public constant   VERIFIED_ROLE = keccak256("VERIFIED_ROLE");
  uint256 internal constant DECIMALS = 18;
  uint256 internal constant NUMERATOR = 10 ** DECIMALS;
  uint256 internal constant defaultThreshold = 129600;
}