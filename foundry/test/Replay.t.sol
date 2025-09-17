// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

// Thin wrapper to explicitly test replay of finalizeMessage via messageHash
contract ReplayTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address adapter = address(0xADAB0A);
    address vault = address(0x1111111111111111111111111111111111111111);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, admin, vault, 1);
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(address(router), 100 ether);
        vm.prank(admin);
        router.addAdapter(adapter);
    }

    function testFinalizeReplay() public {
        bytes32 gr = keccak256("route");
        bytes32 mh = keccak256("message");
        vm.prank(adapter);
        router.finalizeMessage(gr, mh, address(token), vault, address(0), 10 ether, 0, 0);
        vm.prank(adapter);
        vm.expectRevert(Router.MessageAlreadyUsed.selector);
        router.finalizeMessage(gr, mh, address(token), vault, address(0), 10 ether, 0, 0);
    }
}
