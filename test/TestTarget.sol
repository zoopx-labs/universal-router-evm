// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract TestTarget {
    // Accept any calldata; do nothing
    fallback() external payable {}
    receive() external payable {}
}
