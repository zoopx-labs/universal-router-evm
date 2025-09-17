// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AllowedTargetMock {
    event Ping();
    function ping() external { emit Ping(); }
}

contract TargetAllowlistTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, admin, address(0), 1);
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(address(this), 100 ether);
        token.approve(address(router), type(uint256).max);
    }

    function testAllowlistBlocksAndAllows() public {
        AllowedTargetMock t = new AllowedTargetMock();
        vm.prank(admin);
        router.setEnforceTargetAllowlist(true);
        Router.TransferArgs memory args = Router.TransferArgs({
            token: address(token),
            amount: 1 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("ping()"),
            target: address(t),
            dstChainId: 2,
            nonce: 1
        });
        vm.expectRevert(Router.TargetNotContract.selector);
        router.universalBridgeTransfer(args);
        vm.prank(admin);
        router.setAllowedTarget(address(t), true);
        router.universalBridgeTransfer(args);
    }
}
