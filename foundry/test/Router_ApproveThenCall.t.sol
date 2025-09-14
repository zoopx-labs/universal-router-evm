// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/Router.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC4626.sol";
import "./mocks/FeeOnTransferMockERC20.sol";

contract RouterApproveThenCallTest is Test {
    Router router;
    MockERC20 token;
    MockERC4626 vault;

    address user = address(0xBEEF);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN", 18);
        vault = new MockERC4626("Vault", "vTKN", IERC20(address(token)));
        router = new Router(address(this), address(0xFEE), address(vault), 1);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function testApproveThenCallWorks() public {
        uint256 amount = 1e18;
        uint256 protocolFee = 1e18 / 2000;
        uint256 relayerFee = 0;
        uint256 forward = amount - (protocolFee + relayerFee);

        bytes memory payload = abi.encodeWithSelector(MockERC4626.deposit.selector, forward, user);

        vm.prank(user);
        router.universalBridgeApproveThenCall(
            Router.TransferArgs({
                token: address(token),
                amount: amount,
                protocolFee: protocolFee,
                relayerFee: relayerFee,
                payload: payload,
                target: address(vault),
                dstChainId: 2,
                nonce: 1
            })
        );

        // vault should have minted forward shares to user
        assertEq(vault.balanceOf(user), forward);
        // router should have zero balance
        assertEq(token.balanceOf(address(router)), 0);
    }

    function testApproveThenCallEOAReverts() public {
        vm.prank(user);
        vm.expectRevert();
        router.universalBridgeApproveThenCall(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: "",
                target: user,
                dstChainId: 2,
                nonce: 20
            })
        );
    }

    function testApproveThenCallRevokesAllowance() public {
        uint256 amount = 1e18;
        uint256 protocolFee = 1e18 / 2000;
        uint256 relayerFee = 0;
        uint256 forward = amount - (protocolFee + relayerFee);

        bytes memory payload = abi.encodeWithSelector(MockERC4626.deposit.selector, forward, user);

        vm.prank(user);
        router.universalBridgeApproveThenCall(
            Router.TransferArgs({
                token: address(token),
                amount: amount,
                protocolFee: protocolFee,
                relayerFee: relayerFee,
                payload: payload,
                target: address(vault),
                dstChainId: 2,
                nonce: 21
            })
        );

        // allowance should be zero
        assertEq(token.allowance(address(router), address(vault)), 0);
    }

    function testApproveThenCallNoResidue() public {
        uint256 balBefore = token.balanceOf(address(router));
        uint256 amount = 1e18;
        uint256 protocolFee = 1e18 / 2000;
        uint256 relayerFee = 0;
        uint256 forward = amount - (protocolFee + relayerFee);
        bytes memory payload = abi.encodeWithSelector(MockERC4626.deposit.selector, forward, user);

        vm.prank(user);
        router.universalBridgeApproveThenCall(
            Router.TransferArgs({
                token: address(token),
                amount: amount,
                protocolFee: protocolFee,
                relayerFee: relayerFee,
                payload: payload,
                target: address(vault),
                dstChainId: 2,
                nonce: 22
            })
        );

        assertEq(token.balanceOf(address(router)), balBefore);
    }

    function testFeeOnTransferReverts() public {
        // deploy fee-on-transfer token
        FeeOnTransferMockERC20 ftoken = new FeeOnTransferMockERC20("Ft", "FT", 18, 100); // 1% fee
        address user2 = address(0xDEAD);
        ftoken.mint(user2, 1e18);
        vm.prank(user2);
        ftoken.approve(address(router), 1e18);

        vm.prank(user2);
        vm.expectRevert();
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(ftoken),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: "",
                target: address(vault),
                dstChainId: 2,
                nonce: 23
            })
        );
    }
}
