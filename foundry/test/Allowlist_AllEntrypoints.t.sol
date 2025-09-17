// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {MockERC20} from "contracts/MockERC20.sol";

contract Dummy { function ping() external {} }

contract AllowlistAllEntrypointsTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEE5);
    address allowedTarget = address(0xBEEF);
    address disallowedTarget; // deployed dummy contract

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, feeRecipient, allowedTarget, uint16(111));
        token = new MockERC20("Mock", "MOCK");
        token.mint(address(this), 1_000 ether);
        token.approve(address(router), type(uint256).max);
        // deploy disallowed contract target
        disallowedTarget = address(new Dummy());
    }

    function _args(address target) internal view returns (Router.TransferArgs memory a) {
        a = Router.TransferArgs({
            token: address(token),
            amount: 10 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: target,
            dstChainId: 222,
            nonce: 7
        });
    }

    function test_disallowedReverts_universal() public {
        vm.startPrank(admin);
        router.setEnforceTargetAllowlist(true);
        // allow only allowedTarget
        router.setAllowedTarget(allowedTarget, true);
        vm.stopPrank();
        Router.TransferArgs memory a = _args(disallowedTarget);
        vm.expectRevert();
        router.universalBridgeTransfer(a);
    }

    function test_allowedPasses_universal() public {
        vm.startPrank(admin);
        router.setEnforceTargetAllowlist(true);
        router.setAllowedTarget(allowedTarget, true);
        vm.stopPrank();
        Router.TransferArgs memory a = _args(allowedTarget);
        router.universalBridgeTransfer(a);
    }
}
