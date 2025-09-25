// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Minimal pull target used by approve-then-call flows
contract PullTargetForDefault {
    function pull(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract Router_BranchCoverage11_DefaultTargetAndRelayer is Test {
    Router router;
    MockERC20 token;
    PullTargetForDefault pullTarget;

    address admin = address(0xAD);
    address feeRecipient = address(0xFEE5);
    address signer; // for signed flows
    uint256 signerKey;

    function setUp() public {
        // Deploy pull target first so we can set as defaultTarget
        pullTarget = new PullTargetForDefault();
        // Router with non-zero defaultTarget
        router = new Router(admin, feeRecipient, address(pullTarget), uint16(111));
        token = new MockERC20("TKN", "TKN", 18);

        // signer for signed tests
        signerKey = 0xB0B;
        signer = vm.addr(signerKey);

        // Mint and approve for both msg.sender (unsigned) and signer (signed)
        token.mint(address(this), 1_000 ether);
        token.approve(address(router), type(uint256).max);

        token.mint(signer, 1_000 ether);
        vm.prank(signer);
        token.approve(address(router), type(uint256).max);
    }

    // Helper to sign a RouteIntent for approve-then-call withSig
    function _signIntent(Router.RouteIntent memory intent) internal view returns (bytes memory) {
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
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("ZoopXRouter")),
                keccak256(bytes("1")),
                block.chainid,
                address(router)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_signed_approveThenCall_defaultTarget_call_branch() public {
        // a.target == 0 triggers defaultTarget fallback, non-empty payload causes call
        uint256 amount = 100 ether;
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("pull(address,uint256)", address(token), amount),
            target: address(0), // fallback to defaultTarget
            dstChainId: 222,
            nonce: 1001
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("dflt-call");
        intent.user = signer;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = address(pullTarget); // target must match when set
        intent.expiry = block.timestamp + 3600;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

        bytes memory sig = _signIntent(intent);

        uint256 beforeBal = token.balanceOf(address(pullTarget));
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
    uint256 afterBal = token.balanceOf(address(pullTarget));
    assertEq(afterBal - beforeBal, amount);
    }

    function test_signed_approveThenCall_defaultTarget_skip_call_residue_reverts() public {
        // a.target == 0 triggers defaultTarget fallback, empty payload skips call -> residue revert
        uint256 amount = 50 ether;
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: 0,
            relayerFee: 0,
            payload: bytes("") /* empty => skip call */, 
            target: address(0),
            dstChainId: 222,
            nonce: 1002
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("dflt-skip");
        intent.user = signer;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = address(0); // unset OK
        intent.expiry = block.timestamp + 3600;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

        bytes memory sig = _signIntent(intent);
        vm.expectRevert(Router.ResidueLeft.selector);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
    }

    function test_unsigned_approveThenCall_relayerFee_equal_cap_ok() public {
        // Set relayerFeeBps and use fee exactly equal to cap; should succeed
        vm.prank(admin);
        router.setRelayerFeeBps(500); // 5%

        uint256 amount = 200 ether;
        uint256 cap = (amount * 500) / 10_000; // 5%
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: 0,
            relayerFee: cap, // equal to cap
            payload: abi.encodeWithSignature("pull(address,uint256)", address(token), amount - cap),
            target: address(pullTarget),
            dstChainId: 222,
            nonce: 2001
        });

        // Ensure the target will pull the approved tokens to avoid residue
        router.universalBridgeApproveThenCall(a);
    }

    function test_signed_approveThenCall_relayerFee_equal_cap_ok() public {
        vm.prank(admin);
        router.setRelayerFeeBps(500); // 5%

        uint256 amount = 300 ether;
        uint256 cap = (amount * 500) / 10_000; // 5%
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: amount,
            protocolFee: 0,
            relayerFee: cap, // equal to cap
            payload: abi.encodeWithSignature("pull(address,uint256)", address(token), amount - cap),
            target: address(pullTarget),
            dstChainId: 222,
            nonce: 3001
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("equal-cap");
        intent.user = signer;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 3600;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

        bytes memory sig = _signIntent(intent);
        router.universalBridgeApproveThenCallWithSig(a, intent, sig);
    }
}
