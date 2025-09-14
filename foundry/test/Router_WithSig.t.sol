// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/Router.sol";
import "./mocks/MockERC20.sol";
import "./mocks/TargetAdapterMock.sol";

contract RouterWithSigTest is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock adapter;

    uint256 userKey = 0xA11CE;
    address user;

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("Tkn", "TKN", 18);
        adapter = new TargetAdapterMock();
        router = new Router(address(this), address(0xFEE), address(adapter), 1);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function _buildIntent(bytes32 routeId, bytes memory payload, uint64 nonce)
        internal
        view
        returns (Router.RouteIntent memory, bytes memory)
    {
        bytes32 payloadHash = keccak256(payload);
        bytes32 structHash = keccak256(
            abi.encode(
                router.ROUTE_INTENT_TYPEHASH_PUBLIC(),
                routeId,
                user,
                address(token),
                uint256(1e18),
                uint256(0),
                uint256(0),
                uint16(2),
                address(adapter),
                uint256(block.timestamp + 3600),
                payloadHash,
                nonce
            )
        );
        bytes32 EIP712_DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ZoopXRouter")),
                keccak256(bytes("1")),
                block.chainid,
                address(router)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        Router.RouteIntent memory intent = Router.RouteIntent({
            routeId: routeId,
            user: user,
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            dstChainId: 2,
            recipient: address(adapter),
            expiry: block.timestamp + 3600,
            payloadHash: payloadHash,
            nonce: nonce
        });
        return (intent, sig);
    }

    function testSignedHappyPath() public {
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));
        bytes memory payload = abi.encodePacked("payload");
        (Router.RouteIntent memory intent, bytes memory sig) = _buildIntent(routeId, payload, 1);

        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 1
            }),
            intent,
            sig
        );

        assertEq(adapter.callCount(), 1);
    }

    function testBadSignatureReverts() public {
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));
        bytes memory payload = abi.encodePacked("payload");
        (Router.RouteIntent memory intent, bytes memory sig) = _buildIntent(routeId, payload, 1);
        // flip one byte in sig
        sig[0] = bytes1(0xFF);
        vm.expectRevert();
        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 1
            }),
            intent,
            sig
        );
    }

    function testSignedReplayReverts() public {
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));
        bytes memory payload = abi.encodePacked("payload");
        (Router.RouteIntent memory intent, bytes memory sig) = _buildIntent(routeId, payload, 2);

        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 2
            }),
            intent,
            sig
        );

        // second call with same sig should revert
        vm.expectRevert();
        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 2
            }),
            intent,
            sig
        );
        // router must hold no residue
        assertEq(token.balanceOf(address(router)), 0);
    }

    function testSignedMismatchAmountReverts() public {
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));
        bytes memory payload = abi.encodePacked("payload");
        (Router.RouteIntent memory intent, bytes memory sig) = _buildIntent(routeId, payload, 3);

        vm.expectRevert();
        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18 - 1, // mismatch
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 3
            }),
            intent,
            sig
        );
    }

    function testSignedExpiredReverts() public {
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));
        bytes memory payload = abi.encodePacked("payload");
        // build intent with expired timestamp
        bytes32 payloadHash = keccak256(payload);
        Router.RouteIntent memory intent = Router.RouteIntent({
            routeId: routeId,
            user: user,
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            dstChainId: 2,
            recipient: address(adapter),
            expiry: block.timestamp - 1,
            payloadHash: payloadHash,
            nonce: 4
        });
        bytes32 structHash = keccak256(
            abi.encode(
                router.ROUTE_INTENT_TYPEHASH_PUBLIC(),
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
        bytes32 EIP712_DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ZoopXRouter")),
                keccak256(bytes("1")),
                block.chainid,
                address(router)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert();
        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 4
            }),
            intent,
            sig
        );
    }

    function testIntentConsumedEventEmitted() public {
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));
        bytes memory payload = abi.encodePacked("payload");
        (Router.RouteIntent memory intent, bytes memory sig) = _buildIntent(routeId, payload, 5);

        bytes32 structHash = keccak256(
            abi.encode(
                router.ROUTE_INTENT_TYPEHASH_PUBLIC(),
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
        bytes32 EIP712_DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ZoopXRouter")),
                keccak256(bytes("1")),
                block.chainid,
                address(router)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        vm.prank(address(uint160(0xCAFEFEED)));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 5
            }),
            intent,
            sig
        );

        // mapping must be set
        // no direct accessor to usedIntents in ABI, but public mapping exists; call it
        bool used = Router(address(router)).usedIntents(digest);
        assertEq(used ? 1 : 0, 1);
    }
}
