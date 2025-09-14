// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TargetAdapterMock} from "./mocks/TargetAdapterMock.sol";

contract RouterSharesTest is Test {
    Router router;
    MockERC20 token;
    TargetAdapterMock adapter;

    address constant FEE = address(0xFEE);
    address user;
    address lp = address(0xDEADBEEF);

    function setUp() public {
        user = address(0xBEEF);
        token = new MockERC20("Tkn", "TKN", 18);
        adapter = new TargetAdapterMock();
        router = new Router(address(this), FEE, address(adapter), 1);
        router.setAdapter(address(adapter));
        router.setFeeCollector(FEE);

        // mint tokens and approve
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);
    }

    function testProtocolAndLPShareDistribution() public {
        // Set shares: protocol 1% (100 bps), LP 2% (200 bps)
        router.setProtocolShareBps(100);
        router.setLPShareBps(200);

        // fund router with amount
        uint256 amount = 10_000 ether; // large amount to avoid rounding issues
        token.mint(address(router), amount);

        bytes32 messageHash = router.computeMessageHash(1, 2, user, address(adapter), address(token), amount, 42, keccak256(abi.encodePacked("p")));
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 42);

        uint256 beforeCollector = token.balanceOf(FEE);
        uint256 beforeLP = token.balanceOf(lp);
        uint256 beforeAdapter = token.balanceOf(address(adapter));

        // finalize: protocolFee and relayerFee params set to zero for this test; relayer will be adapter
        vm.prank(address(adapter));
        router.finalizeMessage(gri, messageHash, address(token), address(adapter), lp, amount, 0, 0);

        uint256 protocolShare = (amount * 100) / 10000; // 1%
        uint256 lpShare = (amount * 200) / 10000; // 2%
        uint256 paidFees = protocolShare + lpShare;
        uint256 toVault = amount - paidFees; // since relayerFee = 0 and adapter == vault, adapter will receive toVault

        assertEq(token.balanceOf(FEE) - beforeCollector, protocolShare);
        assertEq(token.balanceOf(lp) - beforeLP, lpShare);
        assertEq(token.balanceOf(address(adapter)) - beforeAdapter, toVault);
        assertEq(token.balanceOf(address(router)), 0);
    }
}
