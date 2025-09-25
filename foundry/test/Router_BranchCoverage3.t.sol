// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AllowlistTarget {
    fallback() external payable {}
}

contract RouterBranchCoverage3 is Test {
    Router router;
    MockERC20 token;
    uint256 userKey = 0xBEEF;
    address user;
    address FEE = address(0xFEE);

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("Tkn", "TKN", 18);
        router = new Router(address(this), FEE, address(0), 1);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    function signIntent(Router.RouteIntent memory intent, uint256 key) internal view returns (bytes memory) {
        bytes32 typehash = router.ROUTE_INTENT_TYPEHASH_PUBLIC();
        bytes32 structHash = keccak256(
            abi.encode(
                typehash,
                intent.routeId,
                intent.user,
                intent.token,
                intent.amount,
                intent.protocolFee,
                intent.relayerFee,
                intent.dstChainId,
                intent.recipient,
                intent.expiry,
                intent.payloadHash,
                intent.nonce
            )
        );
        bytes32 domain = keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(router)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_allowlist_enforce_blocks_and_allows() public {
        AllowlistTarget t = new AllowlistTarget();
        address target = address(t);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1000,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: target,
            dstChainId: 2,
            nonce: 1
        });

        // when enforce is off, should allow contract target
        vm.prank(user);
        router.universalBridgeTransfer(a);

        // enable allowlist and do not add target -> should revert
        router.setEnforceTargetAllowlist(true);
        vm.prank(user);
        vm.expectRevert(Router.TargetNotContract.selector);
        router.universalBridgeTransfer(a);

        // add to allowlist and succeed
        router.setAllowedTarget(target, true);
        vm.prank(user);
        router.universalBridgeTransfer(a);
    }

    function test_finalize_with_nonzero_shares_emits_correctly() public {
        // give adapter role
        address adapter = address(0xAD1);
        router.addAdapter(adapter);
        // set feeCollector and shares
        router.setFeeCollector(FEE);
        // set fee split so protocolShareBps + lpShareBps = 10000
        vm.prank(address(this));
        router.setFeeSplit(5000, 5000);

        // mint router balance and call finalize
        token.mint(address(router), 1e18);
        bytes32 messageHash = keccak256(abi.encodePacked("finalize-shares"));
        bytes32 gri = router.computeGlobalRouteId(1, 2, user, messageHash, 1);

        vm.prank(adapter);
        router.finalizeMessage(gri, messageHash, address(token), address(0xBEEF), address(0xC0FF), 1e18, 1, 2);

        // verify forwarded to vault
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function test_signed_payloadHash_zero_reverts() public {
        // build intent with payloadHash == bytes32(0)
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: address(this),
            dstChainId: 2,
            nonce: 7
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("r");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1000;
        intent.payloadHash = bytes32(0);
        intent.nonce = a.nonce;

        bytes memory sig = signIntent(intent, userKey);

        vm.prank(user);
        token.approve(address(router), a.amount);
        vm.prank(user);
        vm.expectRevert(Router.PayloadTooLarge.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    function test_setDelegateFeeToTarget_zero_reverts() public {
        vm.expectRevert(bytes("zero target"));
        router.setDelegateFeeToTarget(address(0), true);
    }
}
