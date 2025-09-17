// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {MockERC20} from "contracts/MockERC20.sol";

contract AdminHandoverAccessControlTest is Test {
    Router router;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEE5);
    address target = address(0xBEEF);
    address newAdmin = address(0xB0B);

    function setUp() public {
        vm.prank(admin);
    router = new Router(admin, feeRecipient, target, uint16(111));
    }

    function test_adminHandoverTransfersRole() public {
        vm.prank(admin);
        router.proposeAdmin(newAdmin);
        vm.prank(newAdmin);
        router.acceptAdmin();
        // old admin should not be able to set fee recipient now
        vm.prank(admin);
        vm.expectRevert();
        router.setFeeRecipient(address(0x1234));
        // new admin can
        vm.prank(newAdmin);
        router.setFeeRecipient(address(0x1234));
    }
}
