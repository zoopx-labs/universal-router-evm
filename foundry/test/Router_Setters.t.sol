// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RouterSettersTest is Test {
    Router router;
    address admin = address(this);
    address nonAdmin = address(0xBAD);

    function setUp() public {
        router = new Router(admin, address(0xFEE), address(0x0), 1);
    }

    function testOnlyAdminCanSetAdapter() public {
        router.setAdapter(address(0x123));
        vm.prank(nonAdmin);
        vm.expectRevert();
        router.setAdapter(address(0x456));
    }

    function testProtocolFeeBpsCapEnforced() public {
        // FEE_CAP_BPS is 5 (0.05%), so setting above should revert
        vm.expectRevert();
        router.setProtocolFeeBps(10);
    }

    function testRelayerFeeBpsCapEnforced() public {
        // relayer cap set to 1000 bps in contract
        vm.expectRevert();
        router.setRelayerFeeBps(2000);
    }

    function testShareBpsSumCannotExceed10000() public {
        router.setProtocolShareBps(9000);
        vm.expectRevert();
        router.setLPShareBps(2000); // would push sum to 11000
    }
}
