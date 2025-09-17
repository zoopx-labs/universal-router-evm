// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {Hashing} from "../../contracts/lib/Hashing.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TargetAdapterMock} from "./mocks/TargetAdapterMock.sol";

contract RouterFinalizeTest is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock adapter;

    address constant FEE = address(0xFEE);
    address user;

    function setUp() public {
        user = address(0xBEEF);
        token = new MockERC20("Tkn", "TKN", 18);
        adapter = new TargetAdapterMock();
        // Router constructor: (admin, feeRecipient, defaultTarget, srcChainId)
        router = new Router(address(this), FEE, address(adapter), 1);

    // grant adapter role for finalize authority
    router.addAdapter(address(adapter));

        // configure fee collector
        router.setFeeCollector(FEE);

        // mint tokens for user and approve if needed in other flows
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function testAdapterCanFinalizeAndDistributeFees() public {
        // simulate forwarded amount available in router
        token.mint(address(router), 1e18);

    bytes32 messageHash = Hashing.messageHash(1, address(adapter), address(0), address(token), 1e18, keccak256(abi.encodePacked("p")), 1, 2);
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 1);

        // call finalize as adapter
        vm.prank(address(adapter));
        router.finalizeMessage(gri, messageHash, address(token), address(adapter), address(0xABC), 1e18, 1e16, 2e16);

    // adapter is both vault and relayer here, so it receives relayerFee and the remaining forwarded amount
    // relayerFee = 2e16, protocolFee param is for read-side only (not deducted on-chain here), protocolShare/LPShare default 0
    // since vault == adapter and relayer fee is paid to msg.sender (adapter), adapter should receive the full amount
    uint256 adapterBal = token.balanceOf(address(adapter));
    assertEq(adapterBal, 1e18);
        // router should have zero balance
        assertEq(token.balanceOf(address(router)), 0);
    }

    function testNonAdapterCannotFinalize() public {
        token.mint(address(router), 1e18);
    bytes32 messageHash = Hashing.messageHash(1, address(adapter), address(0), address(token), 1e18, keccak256(abi.encodePacked("p2")), 2, 2);
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 2);

    vm.prank(address(0xBAD));
    vm.expectRevert(Router.NotAdapter.selector);
        router.finalizeMessage(gri, messageHash, address(token), address(adapter), address(0x0), 1e18, 0, 0);
    }

    function testReplayPrevention() public {
        token.mint(address(router), 1e18);
    bytes32 messageHash = Hashing.messageHash(1, address(adapter), address(0), address(token), 1e18, keccak256(abi.encodePacked("p3")), 3, 2);
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 3);

    vm.prank(address(adapter));
    router.finalizeMessage(gri, messageHash, address(token), address(adapter), address(0x0), 1e18, 0, 0);

        // second call should revert
    vm.prank(address(adapter));
    vm.expectRevert(Router.MessageAlreadyUsed.selector);
        router.finalizeMessage(gri, messageHash, address(token), address(adapter), address(0x0), 1e18, 0, 0);
    }
}
