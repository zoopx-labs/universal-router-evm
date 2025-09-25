// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RevertingTarget {
    fallback() external payable {
        revert("boom");
    }
}

contract AcceptingTarget {
    // Accept tokens via ERC20 transfer by simply holding balance
    fallback() external payable {}
}

contract DummyAdapter {}

contract RouterBranchCoverage is Test {
    Router router;
    MockERC20 token;
    address user = address(0xCAFE);
    address FEE = address(0xFEE);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN", 18);
        // router admin = this, feeRecipient = FEE, defaultTarget = address(0) to force explicit target
        router = new Router(address(this), FEE, address(0), 1);

        // fund and approve user
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    function test_setAdmin_zero_reverts() public {
        // calling setAdmin as admin (this) but with zero address should revert ZeroAddress
        vm.expectRevert(Router.ZeroAddress.selector);
        router.setAdmin(address(0));
    }

    function test_relayerFeeCap_reverts_in_commonChecks() public {
        // set a tiny relayer fee bps so any non-zero relayerFee is over cap
        router.setRelayerFeeBps(1); // 0.01%

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1000,
            protocolFee: 0,
            relayerFee: 50, // will exceed cap for small amount
            payload: "",
            target: address(0x1),
            dstChainId: 2,
            nonce: 1
        });

        vm.prank(user);
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.universalBridgeTransfer(a);
    }

    function test_payload_too_large_reverts() public {
        // create payload > MAX_PAYLOAD_BYTES (512)
        bytes memory big = new bytes(513);
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1000,
            protocolFee: 0,
            relayerFee: 0,
            payload: big,
            target: address(this),
            dstChainId: 2,
            nonce: 1
        });

        vm.prank(user);
        vm.expectRevert(Router.PayloadTooLarge.selector);
        router.universalBridgeTransfer(a);
    }

    function test_callTarget_revert_triggers_target_call_failed() public {
        // Deploy a target whose call will revert
        RevertingTarget t = new RevertingTarget();

        // mint enough to user and ensure approve done in setUp
        uint256 amount = 1e6;
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodePacked(uint8(1)), // non-empty payload forces call
            target: address(t),
            dstChainId: 2,
            nonce: 1
        });

        vm.prank(user);
        // the internal target call will bubble up as a require failure with message "target call failed"
        vm.expectRevert(bytes("target call failed"));
        router.universalBridgeTransfer(a);
    }

    function test_delegate_fee_forward_to_target() public {
        AcceptingTarget t = new AcceptingTarget();
        address target = address(t);

        // register and set delegate to target via admin (this)
        router.setDelegateFeeToTarget(target, true);

        uint256 amount = 1e18;
        // mint tokens to user for the amount
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(router), amount);

        // choose protocol/relayer fees below FEE_CAP_BPS (5 bps) for amount=1e18 => cap = 5e13
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: 1e13, // below cap
            relayerFee: 2e13,
            payload: "",
            target: target,
            dstChainId: 2,
            nonce: 1
        });

        // call - delegate path forwards full amount to target
        vm.prank(user);
        router.universalBridgeTransfer(a);

        // target should have received full amount
        assertEq(token.balanceOf(target), amount);
    }

    function test_freezeAdapter_adapter_frozen_reverts_in_onlyAdapter() public {
        DummyAdapter d = new DummyAdapter();
        address adapter = address(d);
        // grant adapter role
        router.addAdapter(adapter);
        // freeze adapter
        router.freezeAdapter(adapter, true);

        // prepare a minimal finalize call; need token balance in router
        token.mint(address(router), 1e18);
        bytes32 messageHash = keccak256(abi.encodePacked("x"));
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 1);

        vm.prank(adapter);
        vm.expectRevert(Router.AdapterFrozenErr.selector);
        router.finalizeMessage(gri, messageHash, address(token), adapter, address(0x0), 1e18, 0, 0);
    }
}
