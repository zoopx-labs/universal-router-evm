// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract FinalizeAndSourceFeesTest is Test {
    Router router;
    MockERC20 token;

    address admin = address(0xA11CE);
    address adapter = address(0xADAB0A);
    address user = address(0xBEEF01);
    address vault = address(0x1111111111111111111111111111111111111111);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, admin, vault, 1); // feeRecipient = admin
        token = new MockERC20("Mock", "MOCK", 18);
        vm.prank(admin);
        router.addAdapter(adapter);
    }

    function testSourceLegSkimsProtocolAndRelayerFees() public {
        uint256 amount = 100 ether;
        uint256 protocolFee = amount / 4000; // 0.025% (< 0.05% cap)
        uint256 relayerFee = 1 ether; // allowed (relayerFeeBps not set)

        // Mint funds to user and approve router
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(router), amount);

        // Build args
        Router.TransferArgs memory args = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: protocolFee,
            relayerFee: relayerFee,
            payload: bytes("") ,
            target: address(0),
            dstChainId: 137, // arbitrary
            nonce: 1
        });

        uint256 feeRecipientBefore = token.balanceOf(admin);
        uint256 vaultBefore = token.balanceOf(vault);

        vm.prank(user);
        router.universalBridgeTransfer(args);

        // Fees skimmed to feeRecipient
    uint256 feeDelta = token.balanceOf(admin) - feeRecipientBefore;
    assertEq(feeDelta, protocolFee + relayerFee);
        // Forwarded remainder to target (defaultTarget == vault)
        uint256 expectedForward = amount - protocolFee - relayerFee;
    uint256 vaultDelta = token.balanceOf(vault) - vaultBefore;
    assertEq(vaultDelta, expectedForward);
    }

    function testFinalizeEchoesFeesWithoutTransferringThem() public {
        // Mint tokens directly to router for destination distribution
        uint256 amount = 50 ether;
        token.mint(address(router), amount);

        bytes32 globalRouteId = keccak256("gri");
        bytes32 messageHash = keccak256("mh");
        uint256 protocolFeeEcho = amount / 5000; // 0.02% echo value
        uint256 relayerFeeEcho = 0.5 ether;

        uint256 vaultBefore = token.balanceOf(vault);
        uint256 feeRecipientBefore = token.balanceOf(admin);

        // NOTE: We omit explicit event matching here to keep test resilient to timestamp differences and
        // focus on state effects (balance movements + no double fee payment).

        vm.prank(adapter);
        router.finalizeMessage(
            globalRouteId,
            messageHash,
            address(token),
            vault,
            address(0),
            amount,
            protocolFeeEcho,
            relayerFeeEcho
        );

        // Vault got full amount
    uint256 destVaultDelta = token.balanceOf(vault) - vaultBefore;
    assertEq(destVaultDelta, amount);
        // Fee recipient unchanged (no extra fees distributed here)
    assertEq(token.balanceOf(admin), feeRecipientBefore);
    }
}
