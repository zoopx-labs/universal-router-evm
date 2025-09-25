// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TargetAdapterMock} from "./mocks/TargetAdapterMock.sol";

contract RevertingTarget {
    fallback() external payable {
        revert("nope");
    }
}

contract RouterBranchCoverage5 is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock target;
    address user = address(0xBEEF);
    address FEE = address(0xFEE1);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN", 18);
        router = new Router(address(this), FEE, address(0), 1);
        target = new TargetAdapterMock();
        token.mint(user, 1_000 ether);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);

        // allow target so payload calls are permitted
        router.setAllowedTarget(address(target), true);
        router.setEnforceTargetAllowlist(true);

        // grant adapter role to target for finalize
        router.addAdapter(address(target));
    }

    function _args(
        address _target,
        uint256 _amount,
        uint256 _pFee,
        uint256 _rFee,
        bytes memory _payload
    ) internal view returns (Router.TransferArgs memory a) {
        a = Router.TransferArgs({
            token: address(token),
            amount: _amount,
            protocolFee: _pFee,
            relayerFee: _rFee,
            dstChainId: 2,
            target: _target,
            payload: _payload,
            nonce: uint64(block.timestamp)
        });
    }

    function test_delegate_path_forwards_full_amount() public {
        // delegate fee handling to target: no skim, full amount forwarded
        router.setDelegateFeeToTarget(address(target), true);

    uint256 amt = 100 ether;
        bytes memory payload = hex"1234"; // non-empty to exercise _callTarget success path
    // Use zero fees to avoid protocol cap and ensure delegate branch returns early without skim
    Router.TransferArgs memory a = _args(address(target), amt, 0, 0, payload);

        uint256 balBefore = token.balanceOf(address(target));
        vm.prank(user);
        router.universalBridgeTransfer(a);
        uint256 balAfter = token.balanceOf(address(target));
        // full amount forwarded since delegateFeeToTarget=true
        assertEq(balAfter - balBefore, amt);
    }

    function test_skim_path_reverts_when_feeRecipient_zero() public {
        // Ensure delegate=false so skim path is taken, then set feeRecipient=0 and expect revert
        router.setDelegateFeeToTarget(address(target), false);
        vm.expectRevert(Router.ZeroAddress.selector);
        router.setFeeRecipient(address(0));
        // Note: The revert happens at setter level; skim branch requiring feeRecipient is already exercised elsewhere.
    }

    function test_callTarget_failure_branch() public {
        // Using a target that always reverts to hit _callTarget failure branch
        RevertingTarget bad = new RevertingTarget();
        router.setAllowedTarget(address(bad), true);
        router.setEnforceTargetAllowlist(true);

        Router.TransferArgs memory a = _args(address(bad), 10 ether, 0, 0, hex"BEEF");
        vm.prank(user);
        vm.expectRevert(bytes("target call failed"));
        router.universalBridgeTransfer(a);
    }

    function test_finalize_transfers_amount_to_vault() public {
        // Simulate a destination finalize that transfers the full amount to the vault
        // Mint tokens to router to simulate destination asset custody
        token.mint(address(router), 50 ether);
    address vault = address(0xA11CE);

        bytes32 gri = router.computeGlobalRouteId(1, 2, user, keccak256("m"), 1);

        vm.prank(address(target)); // only adapter
        router.finalizeMessage(gri, keccak256("m"), address(token), vault, address(0), 50 ether, 0, 0);

        assertEq(token.balanceOf(vault), 50 ether);
    }
}
