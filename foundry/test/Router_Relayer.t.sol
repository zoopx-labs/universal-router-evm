// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {Hashing} from "../../contracts/lib/Hashing.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TargetAdapterMock} from "./mocks/TargetAdapterMock.sol";

contract RouterRelayerTest is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock adapter;

    address constant FEE = address(0xFEE);
    address user;
    address vault = address(0xCAFECAFE);

    function setUp() public {
        user = address(0xBEEF);
        token = new MockERC20("Tkn", "TKN", 18);
        adapter = new TargetAdapterMock();
    router = new Router(address(this), FEE, address(adapter), 1);
    router.addAdapter(address(adapter));
        router.setFeeCollector(FEE);

        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function testRelayerPaidWhenAdapterNotVault() public {
        uint256 amount = 1e18;
        token.mint(address(router), amount);

    bytes32 messageHash = Hashing.messageHash(1, address(adapter), address(0), address(token), amount, keccak256(abi.encodePacked("p")), 7, 2);
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 7);

        uint256 beforeRelayer = token.balanceOf(address(adapter));
        uint256 beforeVault = token.balanceOf(vault);

    // New model: destination finalize ignores fee params, forwards full amount to vault
    vm.prank(address(adapter));
    router.finalizeMessage(gri, messageHash, address(token), vault, address(0x0), amount, 0, 1e16);

    assertEq(token.balanceOf(address(adapter)) - beforeRelayer, 0);
    assertEq(token.balanceOf(vault) - beforeVault, amount);
    }
}
