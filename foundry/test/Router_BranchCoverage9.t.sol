// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {MockERC20} from "foundry/test/mocks/MockERC20.sol";
import {ERC20PermitMock} from "foundry/test/mocks/ERC20PermitMock.sol";
import {DAIPermitMock} from "foundry/test/mocks/DAIPermitMock.sol";

contract NopTarget {
    event Ping();
    function ping() external {
        emit Ping();
    }
}

contract Router_BranchCoverage9 is Test {
    Router router;
    MockERC20 token;
    address admin = address(this);
    address fee = address(0xFEE9);
    address user;
    uint256 userKey = 0xC0FFEE;

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("T9", "T9", 18);
        router = new Router(admin, fee, address(0), 1); // defaultTarget zero for some tests
        token.mint(user, 1_000 ether);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    // --- unsigned universal transfer TargetNotSet ---
    function test_unsigned_transfer_TargetNotSet_reverts() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: address(0),
            dstChainId: 2,
            nonce: 1
        });
        vm.prank(user);
        vm.expectRevert(Router.TargetNotSet.selector);
        router.universalBridgeTransfer(a);
    }

    // --- signed transfer FeeAppliedSource emit path ---
    function _domainSeparator(Router _router) internal view returns (bytes32) {
        bytes32 domainType = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(abi.encode(domainType, keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(_router)));
    }

    function _signIntent(Router _router, Router.RouteIntent memory intent, uint256 key) internal view returns (bytes memory) {
        bytes32 typehash = _router.ROUTE_INTENT_TYPEHASH_PUBLIC();
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(_router), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_signed_transfer_feeAppliedSource_emits_and_call_branch() public {
        // fresh router with non-zero defaultTarget for this test
        Router r = new Router(admin, fee, address(0), 1);
        NopTarget t = new NopTarget();
        r.setAllowedTarget(address(t), true);
        r.setEnforceTargetAllowlist(true);
        r.setRelayerFeeBps(1000);

        token.mint(user, 100 ether);
        vm.prank(user);
        token.approve(address(r), type(uint256).max);

        uint256 amount = 10 ether;
        uint256 protocolFee = 0.005 ether; // within 0.05%
        uint256 relayerFee = 0.01 ether;   // within 10%

        bytes memory payload = abi.encodeWithSignature("ping()");
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: 123
        });
        Router.RouteIntent memory intent;
        intent.routeId = keccak256("bc9");
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
        bytes memory sig = _signIntent(r, intent, userKey);

        uint256 feeBalBefore = token.balanceOf(fee);
        vm.prank(user);
        r.universalBridgeTransferWithSig(a, intent, sig);
        // source skim path should have sent fees to feeRecipient
        assertEq(token.balanceOf(fee) - feeBalBefore, protocolFee + relayerFee);
    }

    // --- Permit variants coverage ---
    function test_permit_EOA_payload_disallowed() public {
        ERC20PermitMock p = new ERC20PermitMock("Permit", "PRM");
        address holder = vm.addr(0xBEEF);
        p.mint(holder, 10 ether);
        Router r = new Router(admin, fee, address(0), 1);
        // sign permit
        vm.startPrank(holder);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                p.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        p.PERMIT_TYPEHASH(),
                        holder,
                        address(r),
                        10 ether,
                        p.nonces(holder),
                        block.timestamp + 1 days
                    )
                )
            )
        );
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(0xBEEF, digest);
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(p),
            amount: 10 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: hex"01",
            target: address(0xCAFE), // EOA
            dstChainId: 2,
            nonce: 1
        });
        vm.expectRevert(Router.PayloadDisallowedToEOA.selector);
        r.universalBridgeTransferWithPermit(a, block.timestamp + 1 days, v, rr, ss);
        vm.stopPrank();
    }

    function test_permit_call_branch_and_fee_emit() public {
        ERC20PermitMock p = new ERC20PermitMock("Permit", "PRM");
        NopTarget t = new NopTarget();
        Router r = new Router(admin, fee, address(0), 1);
        r.setAllowedTarget(address(t), true);
        r.setEnforceTargetAllowlist(true);
        r.setRelayerFeeBps(1000);

        address holder = vm.addr(1234);
        p.mint(holder, 100 ether);
        vm.startPrank(holder);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                p.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        p.PERMIT_TYPEHASH(),
                        holder,
                        address(r),
                        10 ether,
                        p.nonces(holder),
                        block.timestamp + 1 days
                    )
                )
            )
        );
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(1234, digest);

        uint256 amount = 10 ether;
        uint256 protocolFee = 0.005 ether;
        uint256 relayerFee = 0.002 ether;
        bytes memory payload = abi.encodeWithSignature("ping()");
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(p),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: 7
        });
        uint256 feeBalBefore = p.balanceOf(fee);
        r.universalBridgeTransferWithPermit(a, block.timestamp + 1 days, v, rr, ss);
        // fees skimmed to feeRecipient
        assertEq(p.balanceOf(fee) - feeBalBefore, protocolFee + relayerFee);
        vm.stopPrank();
    }

    function test_daiPermit_call_branch_and_fee_emit() public {
        DAIPermitMock d = new DAIPermitMock("DAI", "DAI");
        NopTarget t = new NopTarget();
        Router r = new Router(admin, fee, address(0), 1);
        r.setAllowedTarget(address(t), true);
        r.setEnforceTargetAllowlist(true);
        r.setRelayerFeeBps(1000);

        address holder = vm.addr(4321);
        d.mint(holder, 100 ether);
        vm.startPrank(holder);
        // Build and sign a valid DAI-style permit for holder -> router
        uint256 nonce = 0;
        uint256 expiry = block.timestamp + 1 days;
        bool allowed = true;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                d.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        d.PERMIT_TYPEHASH(),
                        holder,
                        address(r),
                        nonce,
                        expiry,
                        allowed
                    )
                )
            )
        );
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(4321, digest);
        uint256 amount = 10 ether;
        uint256 protocolFee = 0.005 ether;
        uint256 relayerFee = 0.002 ether;
        bytes memory payload = abi.encodeWithSignature("ping()");
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(d),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: payload,
            target: address(t),
            dstChainId: 2,
            nonce: 8
        });
        uint256 feeBalBefore = d.balanceOf(fee);
        r.universalBridgeTransferWithDAIPermit(a, nonce, expiry, allowed, v, rr, ss);
        assertEq(d.balanceOf(fee) - feeBalBefore, protocolFee + relayerFee);
        vm.stopPrank();
    }
}
