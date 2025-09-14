// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/Router.sol";

contract RouterAdminTest is Test {
    Router router;
    address admin;

    function setUp() public {
        admin = address(this);
        router = new Router(admin, address(0xFEE), address(0xCAFE), 1);
    }

    function testProposeAcceptAdmin() public {
        address newAdmin = address(0xBEEF);
        // propose
        router.proposeAdmin(newAdmin);
        // a non-proposed caller cannot accept
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        router.acceptAdmin();

        // accept as proposed newAdmin
        vm.prank(newAdmin);
        vm.expectRevert(); // accept should fail because pendingAdmin isn't set to newAdmin yet

        // propose again and accept properly
        router.proposeAdmin(newAdmin);
        vm.prank(newAdmin);
        router.acceptAdmin();
        assertEq(router.admin(), newAdmin);
    }

    function testSetFeeRecipientACL() public {
        // non-admin cannot set
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        router.setFeeRecipient(address(1));

        // admin can set
        router.setFeeRecipient(address(2));
        assertEq(router.feeRecipient(), address(2));
    }

    function testAllowlistSettersACL() public {
        // non-admin cannot toggle
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        router.setEnforceTargetAllowlist(true);

        // admin can toggle and set
        router.setEnforceTargetAllowlist(true);
        router.setAllowedTarget(address(0xCAFE), true);
        assertEq(router.enforceTargetAllowlist() ? 1 : 0, 1);
        assertEq(router.isAllowedTarget(address(0xCAFE)) ? 1 : 0, 1);
    }
}
