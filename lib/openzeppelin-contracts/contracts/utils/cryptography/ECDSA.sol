// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ECDSA {
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Very small implementation: supports r,s,v (65 bytes)
        if (signature.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        // solhint-disable-next-line no-inline-assembly
        address signer;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1901)
            signer := call(0, 0x01, 0, ptr, 0, ptr, 0)
        }
        // fallback: use ecrecover
        return ecrecover(hash, v, r, s);
    }
}
