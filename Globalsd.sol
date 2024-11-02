// SPDX-License-Identifier: MIT


pragma solidity ^0.8.26;

contract Globals {
  bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");
  bytes32 public constant NODE_OPERATOR_ROLE = keccak256("NODE_OPERATOR_ROLE");
  bytes32 public constant NODE_RUNNER_ROLE = keccak256("NODE_RUNNER_ROLE");

  bytes32 internal constant CLAIM_REF_CODE_TYPEHASH = keccak256("ClaimRefCode(address[] tokens_,string referralCode_,address receiver_,uint256 deadline_)");
  address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address internal constant TOKEN = 0xE5e5E5E5e5e5E5E5E5E5e5E5e5e5e5E5e5e5e5e5;
  uint256 internal constant MAX = 100000000000000000000000000;
  uint256 internal constant MIN = 1000;
  uint256 internal constant PRECISION = 18;
}