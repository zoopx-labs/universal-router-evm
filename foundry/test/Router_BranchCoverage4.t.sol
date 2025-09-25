// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RouterBranchCoverage4 is Test {
    Router router;
    MockERC20 token;
    address user = address(0xD00D);
    address FEE = address(0xFEE);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN", 18);
        router = new Router(address(this), FEE, address(0), 1);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    function test_relayerFeeBps_zero_and_nonzero_paths() public {
        // simplify: exercise setter paths for relayerFeeBps (0 and non-zero)
    router.setRelayerFeeBps(0);
    assertEq(router.relayerFeeBps(), uint16(0));

    router.setRelayerFeeBps(1000);
    assertEq(router.relayerFeeBps(), uint16(1000));
    }

    function test_feeRecipient_zero_revert_on_skim() public {
        // setting feeRecipient to zero is not allowed via setter
        vm.prank(address(this));
        vm.expectRevert(Router.ZeroAddress.selector);
        router.setFeeRecipient(address(0));
    }
}
