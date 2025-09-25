// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PullTarget8 {
    function pull(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract Router_BranchCoverage8 is Test {
    Router router;
    MockERC20 token;
    address user;
    uint256 userKey = 0xBABA;
    address fee = address(0xFEE8);

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("T8", "T8", 18);
        router = new Router(address(this), fee, address(0), 1);
        token.mint(user, 1_000 ether);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 domainType = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(abi.encode(domainType, keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(router)));
    }

    function _signIntent(Router.RouteIntent memory intent, uint256 key) internal view returns (bytes memory) {
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_unsigned_approveThenCall_with_fees_skim_and_emit() public {
        PullTarget8 t = new PullTarget8();
        // allowlist target
        router.setAllowedTarget(address(t), true);
        router.setEnforceTargetAllowlist(true);

        uint256 amount = 100 ether;
        uint256 protocolFee = 0.05 ether; // within 0.05% cap of 100 ether
        router.setRelayerFeeBps(1000); // 10%
        uint256 relayerFee = 0.02 ether; // within cap

        bytes memory payload = abi.encodeWithSignature("pull(address,uint256)", address(token), amount - (protocolFee + relayerFee));

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: uint64(block.timestamp)
        });

        uint256 feeBalBefore = token.balanceOf(fee);
        vm.prank(user);
        router.universalBridgeApproveThenCall(a);
        // fees skimmed and sent
        assertEq(token.balanceOf(fee) - feeBalBefore, protocolFee + relayerFee);
        // target pulled forwardAmount
        assertEq(token.balanceOf(address(t)), amount - (protocolFee + relayerFee));
    }

    function test_unsigned_approveThenCall_delegate_true_no_skim() public {
        PullTarget8 t = new PullTarget8();
        router.setAllowedTarget(address(t), true);
        router.setEnforceTargetAllowlist(true);
        router.setDelegateFeeToTarget(address(t), true);

        uint256 amount = 50 ether;
        uint256 protocolFee = 0.025 ether; // within cap
        router.setRelayerFeeBps(1000);
        uint256 relayerFee = 0.01 ether;

        bytes memory payload = abi.encodeWithSignature("pull(address,uint256)", address(token), amount);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: uint64(block.timestamp + 1)
        });

        uint256 feeBalBefore = token.balanceOf(fee);
        vm.prank(user);
        router.universalBridgeApproveThenCall(a);
        // no skim: feeRecipient unchanged
        assertEq(token.balanceOf(fee), feeBalBefore);
        // target pulled full amount
        assertEq(token.balanceOf(address(t)), amount);
    }

    function test_signed_approveThenCall_with_fees_skim_and_emit() public {
        PullTarget8 t = new PullTarget8();
        router.setAllowedTarget(address(t), true);
        router.setEnforceTargetAllowlist(true);

        uint256 amount = 30 ether;
        uint256 protocolFee = 0.015 ether; // 0.05% cap of 30 ether is 0.015 ether
        router.setRelayerFeeBps(1000);
        uint256 relayerFee = 0.01 ether;

        bytes memory payload = abi.encodeWithSignature("pull(address,uint256)", address(token), amount - (protocolFee + relayerFee));

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: uint64(1001)
        });
        Router.RouteIntent memory intent;
        intent.routeId = keccak256("u1");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1 days;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;
        bytes memory sig = _signIntent(intent, userKey);

        uint256 feeBalBefore = token.balanceOf(fee);
        vm.prank(user);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
        assertEq(token.balanceOf(fee) - feeBalBefore, protocolFee + relayerFee);
        assertEq(token.balanceOf(address(t)), amount - (protocolFee + relayerFee));
    }

    function test_signed_approveThenCall_delegate_true_no_skim() public {
        PullTarget8 t = new PullTarget8();
        router.setAllowedTarget(address(t), true);
        router.setEnforceTargetAllowlist(true);
        router.setDelegateFeeToTarget(address(t), true);

        uint256 amount = 40 ether;
        uint256 protocolFee = 0.02 ether; // within cap (0.05% of 40)
        router.setRelayerFeeBps(1000);
        uint256 relayerFee = 0.01 ether;

        bytes memory payload = abi.encodeWithSignature("pull(address,uint256)", address(token), amount);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: uint64(1002)
        });
        Router.RouteIntent memory intent;
        intent.routeId = keccak256("u2");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1 days;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;
        bytes memory sig = _signIntent(intent, userKey);

        uint256 feeBalBefore = token.balanceOf(fee);
        vm.prank(user);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
        // delegate: feeRecipient unchanged; target received full amount
        assertEq(token.balanceOf(fee), feeBalBefore);
        assertEq(token.balanceOf(address(t)), amount);
    }
}
