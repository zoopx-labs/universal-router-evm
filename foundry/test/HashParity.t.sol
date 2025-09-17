// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Hashing} from "contracts/lib/Hashing.sol";

contract HashParityTest is Test {
    function test_hashParity_golden() public {
        uint64 src = 111;
        uint64 dst = 222;
        address adapter = address(0xAAA1);
        address recipient = address(0xBBBB);
        address asset = address(0xCCCC);
        uint256 amount = 123456789;
        bytes32 payloadHash = keccak256(abi.encode("payload"));
        uint64 nonce = 42;
        bytes32 h = Hashing.messageHash(src, adapter, recipient, asset, amount, payloadHash, nonce, dst);
        // golden re-derived manually
        bytes32 manual = keccak256(
            bytes.concat(
                abi.encodePacked(src),
                abi.encodePacked(bytes32(uint256(uint160(adapter)))),
                abi.encodePacked(bytes32(uint256(uint160(recipient)))),
                abi.encodePacked(bytes32(uint256(uint160(asset)))),
                abi.encodePacked(amount),
                abi.encodePacked(payloadHash),
                abi.encodePacked(nonce),
                abi.encodePacked(dst)
            )
        );
    assertEq(h, manual);
    }
}
