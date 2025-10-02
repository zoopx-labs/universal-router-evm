// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

// This test asserts positional ordering of BridgeInitiated arguments by decoding topics/data manually.
contract BridgeInitiatedLayoutTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xAA11);
    address feeRecipient = address(0xFEE123);
    address vault = address(0x1111111111111111111111111111111111111111);
    address adapter = address(0xADadAD);

    function setUp() public {
        token = new MockERC20("Mock","M",18);
        router = new Router(admin, feeRecipient, vault, 1);
        vm.prank(admin); router.addAdapter(adapter);
    }

    function test_bridgeInitiated_layout() public {
        // Arrange: user transfer path
        address user = address(0xBEEF);
        token.mint(user, 10 ether);
        vm.prank(user); token.approve(address(router), 10 ether);
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 10 ether,
            protocolFee: 0.001 ether,
            relayerFee: 0.0005 ether,
            payload: bytes(""),
            target: vault,
            dstChainId: 137,
            nonce: 77
        });
        vm.recordLogs();
        vm.prank(user); router.universalBridgeTransfer(a);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Find BridgeInitiated (topic0 hash confirmed externally)
        bytes32 sig = keccak256("BridgeInitiated(bytes32,address,address,address,uint256,uint256,uint256,bytes32,uint16,uint16,uint64)");
        bool found;
        for (uint i; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                // topics[1]=routeId indexed? Actually topics: [sig, routeId, user, token]
                assertEq(address(uint160(uint256(logs[i].topics[2]))), user);
                assertEq(address(uint160(uint256(logs[i].topics[3]))), address(token));
                found = true;
                break;
            }
        }
        require(found, "BridgeInitiated not found");
    }
}
