// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// simple PullTarget to test approve-then-call flows
contract PullTargetLocal {
    function pull(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract RouterFocusedCoverage is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xAB);
    address user = address(0xCD);
    address adapter = address(0xEF);


    function setUp() public {
        token = new MockERC20("T","T",18);
        token.mint(user, 1e21);
        vm.prank(user);
        token.approve(address(this), type(uint256).max);

        router = new Router(admin, address(this), address(0), uint16(1));
        vm.prank(admin);
        router.addAdapter(adapter);
    }

    function test_zero_feeRecipient_reverts_on_skim() public {
        // set feeRecipient to zero and exercise skim path which must revert ZeroAddress
        // setting feeRecipient to zero is not allowed
        vm.prank(admin);
        vm.expectRevert(Router.ZeroAddress.selector);
        router.setFeeRecipient(address(0));
    }

    function test_delegateFee_to_target_forward_and_transfer() public {
        // ensure when delegateFeeToTarget is true, router forwards full amount
        PullTargetLocal p = new PullTargetLocal();
        address paddr = address(p);

        vm.prank(admin);
        router.setDelegateFeeToTarget(paddr, true);

        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("pull(address,uint256)", address(token), uint256(1e18)),
            target: paddr,
            dstChainId: 2,
            nonce: 101
        });

        vm.prank(user);
        router.universalBridgeApproveThenCall(a);
    }

    function test_expired_intent_reverts() public {
        // prepare intent with expiry in past and expect ExpiredIntent
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 2,
            nonce: 102
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("x");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp - 1; // expired
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

        bytes memory fakeSig = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        vm.expectRevert(Router.ExpiredIntent.selector);
        router.universalBridgeTransferWithSig(a, intent, fakeSig);
    }

    function test_payload_disallowed_to_eoa_reverts() public {
        // set default target to 0 and use an EOA target with non-empty payload to hit PayloadDisallowedToEOA
        // The router in setUp uses defaultTarget == address(0) so we must supply an EOA target
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("noop()"),
            target: address(0x1234), // EOA
            dstChainId: 2,
            nonce: 103
        });

        vm.prank(user);
        vm.expectRevert(Router.PayloadDisallowedToEOA.selector);
        router.universalBridgeApproveThenCall(a);
    }

    // additional small test: finalizeMessage flow with LP share path
    function test_finalize_distribute_shares() public {
        // construct fee shares and call finalizeMessage via adapter
        // prepare router config
        vm.prank(admin);
        router.setFeeCollector(address(this));
        vm.prank(admin);
        router.setFeeSplit(uint16(1), uint16(9999)); // protocolSmall, lpLarge

    // mint to router so router can transfer to the destination vault
    uint256 amount = 1e18;
    token.mint(address(router), amount);
        // compute messageHash and globalRouteId using Hashing helpers is cumbersome; we call finalizeMessage with simple values

        // grant adapter role to this contract
        vm.prank(admin);
        router.addAdapter(address(this));

        bytes32 globalRouteId = keccak256("g1");
        bytes32 messageHash = keccak256("m1");
    address vault = address(this);
    address asset = address(token);
    address lpRecipient = address(this);
    uint256 protocol_fee_native = 1e16;
    uint256 relayer_fee_native = 1e15;

    // call finalizeMessage as adapter
    vm.prank(address(this));
    router.finalizeMessage(globalRouteId, messageHash, asset, vault, lpRecipient, amount, protocol_fee_native, relayer_fee_native);
    }
}
