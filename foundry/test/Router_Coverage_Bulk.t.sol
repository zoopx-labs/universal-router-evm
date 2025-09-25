// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FeeOnTransferMockERC20} from "./mocks/FeeOnTransferMockERC20.sol";

contract RevertingTarget {
    fallback() external payable {
        revert("boom");
    }
}

contract RouterCoverageBulk is Test {
    Router router;
    MockERC20 token;
    FeeOnTransferMockERC20 feeToken;
    address admin = address(0xBEEF);
    address feeRecipient = address(0xCAFE);
    address user = address(0xF00D);
    address adapter = address(0xDAD1);

    function setUp() public {
        token = new MockERC20("T", "T", 18);
        feeToken = new FeeOnTransferMockERC20("FT", "FT", 18, 10); // 10 wei fee on transfer
        router = new Router(admin, feeRecipient, address(0), uint16(1));

        // fund user and approve router
        token.mint(user, 1e20);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);

        feeToken.mint(user, 1e20);
        vm.prank(user);
        feeToken.approve(address(router), type(uint256).max);

        // grant adapter role
        vm.prank(admin);
        router.addAdapter(adapter);
    }

    function test_commonChecks_errors() public {
        // Token zero
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(0),
            amount: 1,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 1,
            nonce: 1
        });
        vm.expectRevert(Router.TokenZeroAddress.selector);
        router.universalBridgeTransfer(a);

        // Zero amount
        a.token = address(token);
        a.amount = 0;
        vm.expectRevert(Router.ZeroAmount.selector);
        router.universalBridgeTransfer(a);

        // Fees exceed amount
        a.amount = 100;
        a.protocolFee = 200;
        vm.expectRevert(Router.FeesExceedAmount.selector);
        router.universalBridgeTransfer(a);

        // Protocol fee too high relative to FEE_CAP_BPS (FEE_CAP_BPS is tiny)
        a.amount = 1e6;
        a.protocolFee = type(uint256).max / 2; // large
        a.protocolFee = uint256(1e6); // ensure > cap
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.universalBridgeTransfer(a);
    }

    function test_delegate_and_skim_paths_and_relayer_cap() public {
        // delegate path: set target to delegate and ensure router forwards full amount
        address target = address(0x1111);
        vm.prank(admin);
        router.setDelegateFeeToTarget(target, true);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: target,
            dstChainId: 2,
            nonce: 2
        });

        // mint user funds again and approve as test runs in same address context
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        // call should forward full amount (no revert)
        vm.prank(user);
        router.universalBridgeTransfer(a);

        // test relayer fee cap enforcement
        vm.prank(admin);
        router.setRelayerFeeBps(500); // 5%

        a.target = address(this);
        a.amount = 10000;
        a.relayerFee = 600; // > 5% of 10000 -> should revert
        vm.prank(user);
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.universalBridgeTransfer(a);
    }

    function test_fee_on_transfer_revert_and_callTarget_revert() public {
        // fee-on-transfer token should revert
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(feeToken),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 1,
            nonce: 3
        });
        vm.prank(user);
        vm.expectRevert(Router.FeeOnTransferNotSupported.selector);
        router.universalBridgeTransfer(a);

        // target call revert path
        RevertingTarget bad = new RevertingTarget();
        bytes memory payload = abi.encodeWithSignature("doesNotExist()");
        Router.TransferArgs memory b = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: payload,
            target: address(bad),
            dstChainId: 1,
            nonce: 4
        });
        // fund user and approve
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        vm.prank(user);
        vm.expectRevert(bytes("target call failed"));
        router.universalBridgeTransfer(b);
    }

    function test_verifyIntent_and_finalize_edges_and_setters() public {
        // Expired intent path: craft minimal RouteIntent with expiry in past
        Router.RouteIntent memory intent;
        intent.expiry = 0; // expired
    intent.payloadHash = keccak256("intent1");
    intent.routeId = keccak256("route1");
        intent.user = user;

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 1,
            nonce: 5
        });

        bytes memory sig = new bytes(65);
        vm.expectRevert(Router.ExpiredIntent.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // payloadHash zero triggers PayloadTooLarge
        intent.expiry = block.timestamp + 1000;
        intent.payloadHash = bytes32(0);
        vm.expectRevert(Router.PayloadTooLarge.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // finalizeMessage zero-vault and replay
        bytes32 mh = keccak256("fc1");
        bytes32 gri = router.computeGlobalRouteId(uint16(1), uint16(1), address(this), mh, uint64(1));

        // attempt finalize with vault zero
        vm.prank(adapter);
        vm.expectRevert(Router.ZeroAddress.selector);
        router.finalizeMessage(gri, mh, address(token), address(0), address(0), 1e18, 0, 0);

        // proper finalize and replay
        // fund router with token
        token.mint(address(router), 1e18);
        vm.prank(adapter);
        router.finalizeMessage(gri, mh, address(token), address(this), address(0), 1e18, 0, 0);

        vm.prank(adapter);
        vm.expectRevert(Router.MessageAlreadyUsed.selector);
        router.finalizeMessage(gri, mh, address(token), address(this), address(0), 1e18, 0, 0);

        // setters reverts
        vm.prank(admin);
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.setProtocolFeeBps(uint16(100));

        vm.prank(admin);
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.setRelayerFeeBps(uint16(2000));

        vm.prank(admin);
        vm.expectRevert(bytes("zero target"));
        router.setDelegateFeeToTarget(address(0), true);

        vm.prank(admin);
        vm.expectRevert(bytes("Split!=100%"));
        router.setFeeSplit(uint16(1000), uint16(1000));
    }

    function test_adapter_freeze_blocks_finalize() public {
        // freeze adapter and assert AdapterFrozenErr on finalize
        vm.prank(admin);
        router.freezeAdapter(adapter, true);

        bytes32 mh = keccak256("ff1");
        bytes32 gri = router.computeGlobalRouteId(uint16(1), uint16(1), address(this), mh, uint64(2));

        vm.prank(adapter);
        vm.expectRevert(Router.AdapterFrozenErr.selector);
        router.finalizeMessage(gri, mh, address(token), address(this), address(0), 1e18, 0, 0);
    }
}
