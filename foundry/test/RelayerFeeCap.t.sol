// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {MockERC20} from "contracts/MockERC20.sol";

contract RelayerFeeCapTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEE5);
    address target = address(0xBEEF);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, feeRecipient, target, uint16(111));
    token = new MockERC20("Mock", "MOCK");
        token.mint(address(this), 1_000 ether);
        token.approve(address(router), type(uint256).max);
        vm.prank(admin);
        router.setRelayerFeeBps(500); // 5%
    }

    function test_relayerFeeWithinCap_ok() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 100 ether,
            protocolFee: 0,
            relayerFee: 5 ether, // exactly 5%
            payload: "",
            target: target,
            dstChainId: 222,
            nonce: 1
        });
        router.universalBridgeTransfer(a); // should not revert
    }

    function test_relayerFeeAboveCap_reverts() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 100 ether,
            protocolFee: 0,
            relayerFee: 6 ether, // 6%
            payload: "",
            target: target,
            dstChainId: 222,
            nonce: 1
        });
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.universalBridgeTransfer(a);
    }
}
