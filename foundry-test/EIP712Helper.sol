// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract EIP712Helper is EIP712 {
    constructor() EIP712("Zoopx Router", "1") {}

    function hashStruct(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }
}
