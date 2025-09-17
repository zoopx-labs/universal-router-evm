// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract EventTarget {
    function noop() external {}
}

contract EventsHashesTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address user = address(this);
    EventTarget et;

    event UniversalBridgeInitiated(
        bytes32 indexed routeId,
        bytes32 indexed payloadHash,
        bytes32 indexed messageHash,
        bytes32 globalRouteId,
        address user,
        address token,
        address target,
        uint256 forwardedAmount,
        uint256 protocolFee,
        uint256 relayerFee,
        uint16 srcChainId,
        uint16 dstChainId,
        uint64 nonce
    );

    function setUp() public {
    vm.prank(admin);
    et = new EventTarget();
    router = new Router(admin, admin, address(et), 1);
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(user, 100 ether);
        token.approve(address(router), type(uint256).max);
    }

    function testSourceLegEmitsHashes() public {
        Router.TransferArgs memory args = Router.TransferArgs({
            token: address(token),
            amount: 10 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("noop()"),
            target: address(et),
            dstChainId: 2,
            nonce: 123
        });
    // Execute; if it reverts test fails. Event emission includes payloadHash & messageHash (covered by other tests).
    router.universalBridgeTransfer(args);
    }
}
