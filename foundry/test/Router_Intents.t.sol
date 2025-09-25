// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RouterIntents is Test {
    Router router;
    MockERC20 token;
    uint256 userKey = 0xBEEF;
    address user;
    address admin = address(0xCAFE);

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("T", "T", 18);
        router = new Router(admin, address(this), address(0), uint16(1));
        token.mint(user, 1e20);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
        vm.prank(admin);
        router.addAdapter(address(this));
    }

    function signIntent(Router.RouteIntent memory intent, uint256 key) internal view returns (bytes memory) {
        bytes32 typehash = router.ROUTE_INTENT_TYPEHASH_PUBLIC();
        bytes32 structHash = keccak256(
            abi.encode(
                typehash,
                intent.routeId,
                intent.user,
                intent.token,
                intent.amount,
                intent.protocolFee,
                intent.relayerFee,
                intent.dstChainId,
                intent.recipient,
                intent.expiry,
                intent.payloadHash,
                intent.nonce
            )
        );
        bytes32 domain = keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(router)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_intent_mismatch_fields_transferWithSig() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 1,
            relayerFee: 2,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 2,
            nonce: 1
        });

        Router.RouteIntent memory intent = Router.RouteIntent({
            routeId: keccak256("r"),
            user: user,
            token: address(0), // mismatch token
            amount: 0,
            protocolFee: 0,
            relayerFee: 0,
            dstChainId: 0,
            recipient: address(0),
            expiry: block.timestamp + 1000,
            payloadHash: keccak256(a.payload),
            nonce: a.nonce
        });

        bytes memory sig = signIntent(intent, userKey);
        vm.prank(user);
        token.approve(address(router), a.amount);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // fix token, mismatch amount
        intent.token = a.token;
        intent.amount = a.amount + 1;
        sig = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // mismatch protocolFee
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee + 10;
        sig = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // mismatch relayerFee
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee + 1;
        sig = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // mismatch dstChainId
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId + 1;
        sig = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // mismatch payloadHash
        intent.dstChainId = a.dstChainId;
        intent.payloadHash = keccak256("x");
        sig = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // recipient mismatch: set recipient non-zero and not equal target
        intent.payloadHash = keccak256(a.payload);
        intent.recipient = address(0x1234);
        sig = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    function test_intent_already_used_and_approveThenCallWithSig_mismatch() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 2,
            nonce: 10
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("u");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1000;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

        bytes memory sig = signIntent(intent, userKey);
        vm.prank(user);
        token.approve(address(router), a.amount);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // replay same intent should revert IntentAlreadyUsed
        vm.prank(user);
        token.approve(address(router), a.amount);
        vm.expectRevert(Router.IntentAlreadyUsed.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // approveThenCallWithSig mismatches: change routeId in intent
        intent.routeId = keccak256("v");
        bytes memory badSig = signIntent(intent, userKey);
        vm.prank(user);
        token.approve(address(router), a.amount);
        // craft a mismatched intent: token mismatch
        intent.token = address(0x1);
        bytes memory sig2 = signIntent(intent, userKey);
        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig2);
    }
}
