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
// Minimal shim of OpenZeppelin EIP712 for local compile-time tests only
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract EIP712 {
    string private _name;
    string private _version;

    constructor(string memory name_, string memory version_) {
        _name = name_;
        _version = version_;
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
    // OpenZeppelin-style EIP-712 domain separator
    bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 nameHash = keccak256(bytes(_name));
    bytes32 versionHash = keccak256(bytes(_version));
    bytes32 domain = keccak256(abi.encode(DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(this)));
    return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }
}
