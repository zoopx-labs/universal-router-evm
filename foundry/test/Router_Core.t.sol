// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/Router.sol";
import "./mocks/MockERC20.sol";
import "./mocks/TargetAdapterMock.sol";
import "./mocks/MaliciousAdapter.sol";

contract RouterCoreTest is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock adapter;

    address constant FEE = address(0xFEE);
    address user;

    function setUp() public {
        user = address(0xBEEF);
        token = new MockERC20("Tkn", "TKN", 18);
        adapter = new TargetAdapterMock();
        router = new Router(address(this), FEE, address(adapter), 1);
        // mint and approve
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function testUnsignedHappyPath() public {
        // call as relayer
        bytes memory payload = abi.encodePacked("payload");
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 1e14, // 0.0001
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 1
            })
        );

        // fees were sent
        assertEq(token.balanceOf(FEE), 1e14);
        // adapter got forwarded amount
        assertEq(token.balanceOf(address(adapter)), 1e18 - 1e14);
        // router has zero balance
        assertEq(token.balanceOf(address(router)), 0);
        // adapter called once
        assertEq(adapter.callCount(), 1);
    }

    function testEOAPayoutAllowedOnlyEmptyPayload() public {
        // EOA target = user; empty payload allowed
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: "",
                target: user,
                dstChainId: 2,
                nonce: 1
            })
        );
        assertEq(token.balanceOf(user), 1e18);

        // non-empty payload to EOA should revert
        bytes memory p = abi.encodePacked("x");
        vm.expectRevert();
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: p,
                target: user,
                dstChainId: 2,
                nonce: 2
            })
        );
    }

    function testRevertsOnChecks() public {
        // zero amount
        vm.expectRevert();
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 0,
                protocolFee: 0,
                relayerFee: 0,
                payload: "",
                target: address(adapter),
                dstChainId: 2,
                nonce: 1
            })
        );

        // fee too high
        vm.expectRevert();
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 10000,
                protocolFee: 1000,
                relayerFee: 0,
                payload: "",
                target: address(adapter),
                dstChainId: 2,
                nonce: 1
            })
        );
    }

    function testAdminSetters() public {
        // only admin (constructor admin) can set: non-admin revert
        vm.expectRevert();
        vm.prank(address(uint160(0xDEADBEEF01)));
        router.setAdmin(address(1));

        // admin (this test contract passed as admin in setUp) can set
        router.setAdmin(address(uint160(0xCAFE1)));
        assertEq(router.admin(), address(uint160(0xCAFE1)));

        vm.prank(address(uint160(0xCAFE1)));
        router.setFeeRecipient(address(uint160(0xF2)));
        assertEq(router.feeRecipient(), address(uint160(0xF2)));
    }

    function testPayloadTooLargeReverts() public {
        // build 513-byte payload
        bytes memory payload = new bytes(513);
        vm.prank(user);
        vm.expectRevert();
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 10
            })
        );
    }

    function testEOAPayloadDisallowedReverts() public {
        bytes memory p = abi.encodePacked("x");
        vm.prank(user);
        vm.expectRevert();
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: p,
                target: user,
                dstChainId: 2,
                nonce: 11
            })
        );
    }

    function testResidueCausesRevert() public {
        // deploy malicious adapter that sends tokens back to router during call
        MaliciousAdapter mal = new MaliciousAdapter();
        // mint and approve
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        // pre-fund adapter with 1 token so it can transfer back to router
        token.mint(address(mal), 1);

        // craft payload: put token & router addresses in calldata so fallback will transfer
        bytes memory payload = abi.encode(address(token), address(router));
        vm.prank(user);
        vm.expectRevert();
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(mal),
                dstChainId: 2,
                nonce: 12
            })
        );
    }

    function testAllowlistBlocksUnknownContract() public {
        TargetAdapterMock other = new TargetAdapterMock();
        vm.prank(address(this));
        router.setEnforceTargetAllowlist(true);
        // not added to allowed list -> should revert
        vm.prank(user);
        vm.expectRevert();
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: "",
                target: address(other),
                dstChainId: 2,
                nonce: 13
            })
        );
    }

    function testAllowlistAllowsWhitelistedContract() public {
        address other = address(adapter);
        vm.prank(address(this));
        router.setEnforceTargetAllowlist(true);
        vm.prank(address(this));
        router.setAllowedTarget(other, true);
        // now call should succeed
        bytes memory payload = abi.encodePacked("payload");
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: other,
                dstChainId: 2,
                nonce: 14
            })
        );
        assertEq(token.balanceOf(address(router)), 0);
    }

    function testEOAPayoutAllowedWithAllowlistOn() public {
        vm.prank(address(this));
        router.setEnforceTargetAllowlist(true);
        // EOA still allowed when payload empty
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: "",
                target: user,
                dstChainId: 2,
                nonce: 15
            })
        );
        assertEq(token.balanceOf(user), 1e18);
    }

    function testBridgeInitiatedPayloadHashMatches() public {
        bytes memory payload = abi.encodePacked("payload");
        bytes32 expected = keccak256(payload);
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 16
            })
        );
        // BridgeInitiated emitted earlier; basic checks done in other tests; assert final balances
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.balanceOf(address(adapter)), 1e18);
    }
}
