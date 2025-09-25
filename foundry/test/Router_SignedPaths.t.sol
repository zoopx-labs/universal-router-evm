// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RouterSignedPaths is Test {
    Router router;
    MockERC20 token;
    uint256 userKey = 0xB10C;
    address user;
    address admin = address(0xBEEF);
    address adapter = address(0xDAD1);

    function setUp() public {
        user = vm.addr(userKey);
        token = new MockERC20("T", "T", 18);
        router = new Router(admin, address(this), address(0), uint16(1));

        // fund user and approve router
        token.mint(user, 1e20);
        vm.prank(user);
        token.approve(address(router), type(uint256).max);

        // grant adapter role
        vm.prank(admin);
        router.addAdapter(adapter);
    }

    function domainSeparator() internal view returns (bytes32) {
        bytes32 domainType = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(abi.encode(domainType, keccak256(bytes("ZoopXRouter")), keccak256(bytes("1")), block.chainid, address(router)));
    }

    function signIntent(Router.RouteIntent memory intent, uint256 key) internal returns (bytes memory) {
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_signed_transfer_happy_path_and_invalid() public {
        // build transfer args and intent
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: new bytes(0),
            target: address(this),
            dstChainId: 2,
            nonce: 10
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("r1");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1000;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

    bytes memory sig = signIntent(intent, userKey);

        // call signed transfer (should succeed)
        vm.prank(user);
        token.approve(address(router), a.amount);
        router.universalBridgeTransferWithSig(a, intent, sig);

        // tamper signature -> expect InvalidSignature
    // sign with a different key to produce a well-formed signature that recovers to a different address
    bytes memory badSig = signIntent(intent, userKey + 1);
    vm.prank(user);
    token.approve(address(router), a.amount);
    vm.expectRevert(Router.InvalidSignature.selector);
    router.universalBridgeTransferWithSig(a, intent, badSig);
    }

    function test_signed_approve_then_call_with_sig() public {
        // deploy a simple target contract that will pull tokens from router when called
        PullTarget t = new PullTarget();
        address target = address(t);
        bytes memory payload = abi.encodeWithSignature("pull(address,uint256)", address(token), uint256(1e18));

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: payload,
            target: target,
            dstChainId: 3,
            nonce: 11
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("r2");
        intent.user = user;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1000;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

    bytes memory sig = signIntent(intent, userKey);

            vm.prank(user);
            token.approve(address(router), a.amount);
            router.universalBridgeApproveThenCallWithSig(a, intent, sig);
        }

    }

    import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

    contract PullTarget {
        function pull(address token, uint256 amount) external {
            // msg.sender will be the router; pull the approved tokens
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        // noop target for approve-then-call
        function noop() external {}
    }
