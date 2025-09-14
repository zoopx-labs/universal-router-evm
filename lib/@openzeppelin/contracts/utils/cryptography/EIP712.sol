// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract EIP712 {
    bytes32 private _DOMAIN_SEPARATOR;

    constructor(string memory name, string memory version) {
        _DOMAIN_SEPARATOR = keccak256(abi.encodePacked(name, version));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, structHash));
    }
}
