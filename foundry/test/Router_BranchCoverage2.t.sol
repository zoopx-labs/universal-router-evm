// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RouterBranchCoverage2 is Test {
    Router router;
    MockERC20 token;
    address user = address(0xCAFE);
    address FEE = address(0xFEE);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN", 18);
        router = new Router(address(this), FEE, address(0), 1);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    function test_commonChecks_token_zero_reverts() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(0),
            amount: 1000,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: address(0x1),
            dstChainId: 2,
            nonce: 1
        });
        vm.prank(user);
        vm.expectRevert(Router.TokenZeroAddress.selector);
        router.universalBridgeTransfer(a);
    }

    function test_commonChecks_amount_zero_reverts() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 0,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: address(0x1),
            dstChainId: 2,
            nonce: 1
        });
        vm.prank(user);
        vm.expectRevert(Router.ZeroAmount.selector);
        router.universalBridgeTransfer(a);
    }

    function test_commonChecks_fees_exceed_amount_reverts() public {
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 100,
            protocolFee: 80,
            relayerFee: 40,
            payload: "",
            target: address(0x1),
            dstChainId: 2,
            nonce: 1
        });
        vm.prank(user);
        vm.expectRevert(Router.FeesExceedAmount.selector);
        router.universalBridgeTransfer(a);
    }

    function test_commonChecks_protocolFee_above_cap_reverts() public {
        // amount small so protocolFee > cap
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1000,
            protocolFee: 1,
            relayerFee: 0,
            payload: "",
            target: address(0x1),
            dstChainId: 2,
            nonce: 1
        });
        vm.prank(user);
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.universalBridgeTransfer(a);
    }

    function test_setRelayerFeeBps_too_high_reverts() public {
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.setRelayerFeeBps(2000); // > 1000 cap
    }

    function test_setFeeSplit_require_reverts() public {
        vm.expectRevert(bytes("Split!=100%"));
        router.setFeeSplit(1, 2);
    }

    function test_finalize_vault_zero_reverts() public {
        // prepare adapter role and router balance
        address adapter = address(0xAD0);
        router.addAdapter(adapter);
        token.mint(address(router), 1e18);
        bytes32 messageHash = keccak256(abi.encodePacked("v"));
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 1);

        vm.prank(adapter);
        vm.expectRevert(Router.ZeroAddress.selector);
        router.finalizeMessage(gri, messageHash, address(token), address(0), address(0x0), 1e18, 0, 0);
    }
}
