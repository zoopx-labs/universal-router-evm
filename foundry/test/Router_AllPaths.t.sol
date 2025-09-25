// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PullTarget {
    function pull(address token, uint256 amount) external {
        // msg.sender will be the router; pull the approved tokens
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    // noop target for approve-then-call
    function noop() external {}
}

import {MockERC20} from "./mocks/MockERC20.sol";

contract CallTarget {
    event Called(bytes payload);
    function callMe(bytes calldata payload) external {
        emit Called(payload);
    }
}

contract RouterAllPaths is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA1);
    address user = address(0xB2);
    address adapter = address(0xC3);
    CallTarget target;

    function setUp() public {
        token = new MockERC20("T","T",18);
        token.mint(user, 1e21);
        vm.prank(user);
        token.approve(address(this), type(uint256).max);

        router = new Router(admin, address(this), address(0), uint16(1));
        vm.prank(admin);
        router.addAdapter(adapter);

        target = new CallTarget();
    }

    function test_universal_transfer_with_payload_and_fees() public {
        // user approves router
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            // keep protocol fee within FEE_CAP_BPS (0.05% of 1e18 == 5e14)
            protocolFee: 5e14,
            relayerFee: 1e14,
            payload: abi.encodeWithSignature("callMe(bytes)", abi.encodePacked(uint256(1))),
            target: address(target),
            dstChainId: 2,
            nonce: 20
        });

        // ensure target allowlist off path
        vm.prank(user);
        router.universalBridgeTransfer(a);
    }

    function test_universal_approve_then_call_non_delegate() public {
        // approve-then-call where router skims fees and approves target
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        // use a PullTarget so the approved tokens are pulled during the call and no residue remains
        PullTarget p = new PullTarget();
        address paddr = address(p);

        uint256 totalFees = 5e14 + 1e14;
        uint256 forward = 1e18 - totalFees;
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            // keep protocol fee within FEE_CAP_BPS
            protocolFee: 5e14,
            relayerFee: 1e14,
            payload: abi.encodeWithSignature("pull(address,uint256)", address(token), forward),
            target: paddr,
            dstChainId: 2,
            nonce: 21
        });

        vm.prank(user);
        router.universalBridgeApproveThenCall(a);
    }

    function test_universal_approve_then_call_delegate() public {
        // set delegate fee to target and test approveThenCall path where forwardAmount == amount
        // deploy a PullTarget that will pull the approved tokens
        // PullTarget is defined in other test files and available at compile time
        PullTarget p = new PullTarget();
        address paddr = address(p);

        vm.prank(admin);
        router.setDelegateFeeToTarget(paddr, true);

        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(router), 1e18);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("pull(address,uint256)", address(token), uint256(1e18)),
            target: paddr,
            dstChainId: 2,
            nonce: 22
        });

        vm.prank(user);
        router.universalBridgeApproveThenCall(a);
    }

    // Signed variants: reuse Router SignedPaths style signing
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xC0FFEE, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_signed_transfer_with_payload() public {
        // create a signed transfer intent where user key is vm.addr(0xC0FFEE)
        address userAddr = vm.addr(0xC0FFEE);
        token.mint(userAddr, 1e18);
        vm.prank(userAddr);
        token.approve(address(router), 1e18);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 1e18,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("callMe(bytes)", abi.encodePacked(uint256(3))),
            target: address(target),
            dstChainId: 2,
            nonce: 30
        });

        Router.RouteIntent memory intent;
        intent.routeId = keccak256("st1");
        intent.user = userAddr;
        intent.token = a.token;
        intent.amount = a.amount;
        intent.protocolFee = a.protocolFee;
        intent.relayerFee = a.relayerFee;
        intent.dstChainId = a.dstChainId;
        intent.recipient = a.target;
        intent.expiry = block.timestamp + 1000;
        intent.payloadHash = keccak256(a.payload);
        intent.nonce = a.nonce;

        bytes memory sig = signIntent(intent, 0xC0FFEE);
        router.universalBridgeTransferWithSig(a, intent, sig);
    }
}
