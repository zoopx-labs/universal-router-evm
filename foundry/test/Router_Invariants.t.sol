// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/Router.sol";
import "./mocks/MockERC20.sol";
import "./mocks/TargetAdapterMock.sol";

contract RouterInvariants is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock adapter;
    address user = address(0xBEEF);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN", 18);
        adapter = new TargetAdapterMock();
        router = new Router(address(this), address(0xFEE), address(adapter), 1);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function test_noResidualBalance_after_unsigned() public {
        bytes memory payload = abi.encodePacked("payload");
        vm.prank(user);
        router.universalBridgeTransfer(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 1e14,
                relayerFee: 0,
                payload: payload,
                target: address(adapter),
                dstChainId: 2,
                nonce: 1
            })
        );
        assertEq(token.balanceOf(address(router)), 0);
    }
}
