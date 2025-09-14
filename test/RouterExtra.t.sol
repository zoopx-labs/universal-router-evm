// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/Router.sol";
import "../contracts/MockERC20.sol";
import "./TestTarget.sol";

contract RouterExtraTest is Test {
    Router router;
    MockERC20 token;
    TestTarget target;

    function setUp() public {
        // Removed: Foundry test. Use files under foundry/test for Forge.
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            dstChainId: 2,
            recipient: address(target),
            expiry: block.timestamp + 3600,
            payloadHash: payloadHash,
            nonce: 1
        });

        vm.prank(address(this));
        try router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: abi.encodePacked("payload"),
                target: address(target),
                dstChainId: 2,
                nonce: 1
            }),
            intent,
            sig
        ) {
            revert("expected InvalidSignature() revert");
        } catch (bytes memory) {
            // expected
        }
    }

    function testExpiredIntent() public {
        uint256 userKey = 0xDAD;
        address user = vm.addr(userKey);
        token.mint(user, 1e18);

        vm.startPrank(user);
        token.approve(address(router), 1e18);
        vm.stopPrank();

        bytes32 payloadHash = keccak256(abi.encodePacked("payload"));
        bytes32 routeId = keccak256(abi.encodePacked("routePlan"));

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
                address(target),
                uint256(block.timestamp - 1),
                payloadHash,
                uint64(1)
            )
        );

        bytes32 EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(router)));
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
            recipient: address(target),
            expiry: block.timestamp - 1,
            payloadHash: payloadHash,
            nonce: 1
        });

        vm.prank(address(this));
        try router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: abi.encodePacked("payload"),
                target: address(target),
                dstChainId: 2,
                nonce: 1
            }),
            intent,
            sig
        ) {
            revert("expected ExpiredIntent() revert");
        } catch (bytes memory) {
            // expected
        }
    }

    function testFeeTooHigh() public {
        // amount 10000, fee 6 => fee cap exceeded (FEE_CAP_BPS = 5)
        token.mint(address(this), 10000);
        token.approve(address(router), 10000);

        try router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 10000,
                protocolFee: 6,
                relayerFee: 0,
                payload: "",
                target: address(0),
                dstChainId: 2,
                nonce: 1
            })
        ) {
            revert("expected FeeTooHigh() revert");
        } catch (bytes memory) {
            // expected
        }
    }

    function testPayloadTooLarge() public {
        uint256 userKey = 0xE0F;
        address user = vm.addr(userKey);
        token.mint(user, 1e18);

        vm.startPrank(user);
        token.approve(address(router), 1e18);
        vm.stopPrank();

        bytes memory big = new bytes(router.MAX_PAYLOAD_BYTES() + 1);
        vm.prank(address(this));
        try router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: big,
                target: address(0),
                dstChainId: 2,
                nonce: 1
            })
        ) {
            revert("expected PayloadTooLarge() revert");
        } catch (bytes memory) {
            // expected
        }
    }

    function testApproveThenCallUnsigned() public {
        TestVault vault = new TestVault();

        uint256 userKey = 0xF00D;
        address user = vm.addr(userKey);
        token.mint(user, 1e18);

        vm.startPrank(user);
        token.approve(address(router), 1e18);
        vm.stopPrank();

        uint256 amount = 1e18;
    uint256 protocolFee = 1e18 / 2000; // within FEE_CAP_BPS
        uint256 relayerFee = 0;
        uint256 forward = amount - (protocolFee + relayerFee);

        bytes memory payload = abi.encodeWithSelector(TestVault.pull.selector, address(token), forward);

        vm.prank(user);
        router.universalBridgeApproveThenCall(
            Router.TransferArgs({
                token: address(token),
                amount: amount,
                protocolFee: protocolFee,
                relayerFee: relayerFee,
                payload: payload,
                target: address(vault),
                dstChainId: 2,
                nonce: 1
            })
        );

    require(vault.received() == forward, "vault received mismatch");
    }

    function testApproveThenCallWithSig() public {
        TestVault vault = new TestVault();
        _doSignedApproveThenCall(0xF0E, vault, 1e18, 1e18 / 1000, 0);
    }

    function _doSignedApproveThenCall(uint256 userKey, TestVault vault, uint256 amount, uint256 protocolFee, uint256 relayerFee) internal {
        address user = vm.addr(userKey);
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(router), amount);
        vm.stopPrank();

        uint256 forward = amount - (protocolFee + relayerFee);
        bytes memory payload = abi.encodeWithSelector(TestVault.pull.selector, address(token), forward);

        (bytes memory sig, Router.RouteIntent memory intent) = _buildAndSignIntent(
            userKey,
            user,
            address(token),
            amount,
            protocolFee,
            relayerFee,
            uint16(2),
            address(vault),
            payload,
            uint64(1)
        );

        vm.prank(address(this));
        router.universalBridgeApproveThenCallWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: amount,
                protocolFee: protocolFee,
                relayerFee: relayerFee,
                payload: payload,
                target: address(vault),
                dstChainId: 2,
                nonce: 1
            }),
            intent,
            sig
        );

        require(vault.received() == forward, "vault received mismatch");
    }
}

// A simple vault that pulls approved tokens from the router when called
contract TestVault {
    uint256 public received;
    function pull(address token, uint256 amount) external {
        // router (msg.sender) should have approved this contract
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
        received = amount;
    }
}
