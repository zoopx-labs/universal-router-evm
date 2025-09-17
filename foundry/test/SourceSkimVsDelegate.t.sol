// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {MockERC20} from "contracts/MockERC20.sol";

contract SourceSkimVsDelegateTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEE5);
    address target = address(0xBEEF);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, feeRecipient, target, uint16(111));
    token = new MockERC20("Mock", "MOCK");
        token.mint(address(this), 1_000 ether);
        token.approve(address(router), type(uint256).max);
        // grant adapter role to a fake adapter for finalize
        vm.prank(admin);
        router.addAdapter(address(this));
    }

    function _transfer(bool delegate) internal returns (uint256 forwarded) {
        vm.prank(admin);
        router.setDelegateFeeToTarget(target, delegate);
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 100 ether,
            protocolFee: 0.02 ether, // 0.02% of 100? actually 0.02 ether = 0.02%? 0.02/100 =0.0002 = 2 bps < cap
            relayerFee: 0.03 ether,
            payload: "",
            target: target,
            dstChainId: 222,
            nonce: 1
        });
        // perform transfer
        router.universalBridgeTransfer(a);
        return token.balanceOf(target);
    }

    function test_sourceSkim() public {
        uint256 bal = _transfer(false); // skim
        assertEq(bal, 100 ether - 0.02 ether - 0.03 ether);
    }

    function test_delegateNoSkim() public {
        uint256 bal = _transfer(true); // delegation -> full amount
        assertEq(bal, 100 ether);
    }
}
