// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TargetAdapterMock} from "./mocks/TargetAdapterMock.sol";

contract RouterBranchCoverage6 is Test {
    MockERC20 token;
    TargetAdapterMock target;
    address user = address(0xD00D);
    address FEE = address(0xFEE2);

    function setUp() public {
        token = new MockERC20("T", "T", 18);
        target = new TargetAdapterMock();
        token.mint(user, 100 ether);
    }

    function test_constructor_reverts_on_zero_admin() public {
        vm.expectRevert(bytes("bad admin"));
        new Router(address(0), FEE, address(0), 1);
    }

    function test_constructor_reverts_on_zero_feeRecipient() public {
        vm.expectRevert(bytes("bad feeRecipient"));
        new Router(address(this), address(0), address(0), 1);
    }

    function test_proposeAdmin_zero_reverts() public {
        Router r = new Router(address(this), FEE, address(0), 1);
        vm.expectRevert(Router.ZeroAddress.selector);
        r.proposeAdmin(address(0));
    }

    function test_setFeeCollector_zero_reverts() public {
        Router r = new Router(address(this), FEE, address(0), 1);
        vm.expectRevert(Router.ZeroAddress.selector);
        r.setFeeCollector(address(0));
    }

    function test_defaultTarget_branch_universal_transfer() public {
        // Deploy router with defaultTarget set, pass zero target in args to hit ternary's else branch
        Router r = new Router(address(this), FEE, address(target), 1);
        r.setAllowedTarget(address(target), true);
        r.setEnforceTargetAllowlist(true);

        // prep funds and approval
        vm.prank(user);
        token.approve(address(r), type(uint256).max);

        vm.prank(user);
        r.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 10 ether,
                protocolFee: 0,
                relayerFee: 0,
                dstChainId: 2,
                target: address(0), // defaultTarget path
                payload: hex"01",
                nonce: uint64(block.timestamp)
            })
        );
        // success path; token should arrive at target
        assertEq(token.balanceOf(address(target)), 10 ether);
    }

    function test_defaultTarget_branch_approve_then_call_residue_reverts() public {
        // For approve-then-call, our TargetAdapterMock doesn't pull tokens; expect ResidueLeft
        Router r = new Router(address(this), FEE, address(target), 1);
        r.setAllowedTarget(address(target), true);
        r.setEnforceTargetAllowlist(true);

        vm.startPrank(user);
        token.approve(address(r), type(uint256).max);
        vm.expectRevert(Router.ResidueLeft.selector);
        r.universalBridgeApproveThenCall(
            Router.TransferArgs({
                token: address(token),
                amount: 5 ether,
                protocolFee: 0,
                relayerFee: 0,
                dstChainId: 2,
                target: address(0), // defaultTarget path
                payload: hex"", // no call; target won't pull
                nonce: uint64(block.timestamp)
            })
        );
        vm.stopPrank();
    }
}
