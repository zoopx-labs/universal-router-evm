// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PullTarget7 {
    function pull(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract Router_BranchCoverage7 is Test {
    Router router;
    MockERC20 token;
    uint256 userKey = 0xABCD;
    address user;
    address admin = address(this);
    address fee = address(0xFEE7);

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("T7", "T7", 18);
        router = new Router(admin, fee, address(0), uint16(1));
        token.mint(user, 1_000 ether);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 domainType = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(abi.encode(domainType, keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(router)));
    }

    function _signIntent(Router.RouteIntent memory intent, uint256 key) internal view returns (bytes memory) {
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _baseArgs(address target, uint256 amount, bytes memory payload) internal pure returns (Router.TransferArgs memory a) {
        a = Router.TransferArgs({
            token: address(0), // to be set by caller
            amount: amount,
            protocolFee: 0,
            relayerFee: 0,
            payload: payload,
            target: target,
            dstChainId: 2,
            nonce: uint64(123)
        });
    }

    function _intentFromArgs(Router.TransferArgs memory a, address u, address recp, bytes32 route, uint64 nonce) internal view returns (Router.RouteIntent memory intent) {
        intent.routeId = route;
        intent.user = u;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = recp;
        intent.expiry = block.timestamp + 1 days;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = nonce;
    }

    // 1) recipient mismatch reverts (IntentMismatch)
    function test_signedTransfer_recipient_mismatch_reverts() public {
        address target = address(this); // contract
        Router.TransferArgs memory a = _baseArgs(target, 10 ether, hex"01");
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, address(0xBADD), keccak256("r7"), a.nonce);
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.IntentMismatch.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    // 2) allowlist blocks unapproved target
    function test_signedTransfer_allowlist_blocks_unapproved_target() public {
        router.setEnforceTargetAllowlist(true);
        address unapproved = address(new PullTarget7());
        Router.TransferArgs memory a = _baseArgs(unapproved, 1 ether, hex"00");
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, unapproved, keccak256("r8"), a.nonce);
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.TargetNotContract.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    // 3) payload to EOA disallowed
    function test_signedTransfer_payload_to_EOA_disallowed() public {
        address eoa = vm.addr(0xDEAD);
        Router.TransferArgs memory a = _baseArgs(eoa, 1 ether, hex"01"); // non-empty payload
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, eoa, keccak256("r9"), a.nonce);
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.PayloadDisallowedToEOA.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    // 4) expired intent reverts
    function test_signedTransfer_expired_reverts() public {
        address target = address(this);
        Router.TransferArgs memory a = _baseArgs(target, 1 ether, hex"00");
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, target, keccak256("ra"), a.nonce);
        intent.expiry = block.timestamp - 1; // expired
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.ExpiredIntent.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    // 5) payloadHash == 0 reverts in _verifyIntentReturningDigest
    function test_signedTransfer_payloadHash_zero_reverts() public {
        address target = address(this);
        Router.TransferArgs memory a = _baseArgs(target, 1 ether, hex"");
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, target, keccak256("rb"), a.nonce);
        intent.payloadHash = bytes32(0); // trigger revert path
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.PayloadTooLarge.selector);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }

    // 6) approve-then-call with sig: EOA + payload disallowed, and EOA + empty payload ok
    function test_signedApproveThenCall_EOA_payload_disallowed() public {
        address eoa = vm.addr(0xB0B0);
        Router.TransferArgs memory a = _baseArgs(eoa, 2 ether, hex"CAFE");
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, eoa, keccak256("rc"), a.nonce);
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.PayloadDisallowedToEOA.selector);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
    }

    function test_signedApproveThenCall_EOA_emptyPayload_residue_reverts() public {
        address eoa = vm.addr(0xB0B1);
        Router.TransferArgs memory a = _baseArgs(eoa, 2 ether, hex"");
        a.token = address(token);
        Router.RouteIntent memory intent = _intentFromArgs(a, user, eoa, keccak256("rd"), a.nonce);
        bytes memory sig = _signIntent(intent, userKey);

    vm.prank(user);
    // Pre-checks pass, but since EOA won't pull, residue check should revert
    vm.expectRevert(Router.ResidueLeft.selector);
    router.universalBridgeApproveThenCallWithSig(a, intent, sig);
    }

    // 7) approve-then-call with sig: relayer cap enforcement
    function test_signedApproveThenCall_relayerCap_reverts() public {
        // Set relayer cap to 10%
        router.setRelayerFeeBps(1000);
        address target = address(new PullTarget7());
        Router.TransferArgs memory a = _baseArgs(target, 100 ether, hex"00");
        a.token = address(token);
        a.relayerFee = 11 ether; // above 10%
        Router.RouteIntent memory intent = _intentFromArgs(a, user, target, keccak256("re"), a.nonce);
        bytes memory sig = _signIntent(intent, userKey);

        vm.prank(user);
        vm.expectRevert(Router.FeeTooHigh.selector);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
    }

    // 8) approve-then-call with sig: call branch (payload) vs skip (empty payload)
    function test_signedApproveThenCall_call_branch_and_skip() public {
        PullTarget7 t = new PullTarget7();
        address target = address(t);
        bytes memory payload = abi.encodeWithSignature("pull(address,uint256)", address(token), uint256(1 ether));

        // with payload: should call target and transfer 1 ether
        Router.TransferArgs memory a1 = _baseArgs(target, 1 ether, payload);
        a1.token = address(token);
        Router.RouteIntent memory i1 = _intentFromArgs(a1, user, target, keccak256("rf"), a1.nonce);
        bytes memory s1 = _signIntent(i1, userKey);
        vm.prank(user);
        router.universalBridgeApproveThenCallWithSig(a1, i1, s1);
        assertEq(token.balanceOf(target), 1 ether);

        // without payload: skip call branch
        Router.TransferArgs memory a2 = _baseArgs(target, 1 ether, hex"");
        a2.token = address(token);
        Router.RouteIntent memory i2 = _intentFromArgs(a2, user, target, keccak256("rg"), a2.nonce);
        bytes memory s2 = _signIntent(i2, userKey);
    vm.prank(user);
    // Without payload, target won't pull; residue check should revert
    vm.expectRevert(Router.ResidueLeft.selector);
    router.universalBridgeApproveThenCallWithSig(a2, i2, s2);
    }
}
