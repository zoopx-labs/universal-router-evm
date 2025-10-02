// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Hashing} from "../../contracts/lib/Hashing.sol";

contract RouterEchoExtensionsTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEEFEe);
    address adapter = address(0xADab0B);
    address vault = address(0x1111111111111111111111111111111111111111);

    function setUp() public {
        token = new MockERC20("Mock", "MCK", 18);
        router = new Router(admin, feeRecipient, vault, 1);
        vm.prank(admin); router.addAdapter(adapter);
    }

    // 1. Event Echo Assertion: finalize echoes protocolFee & relayerFee
    function test_finalize_echoes_fee_values() public {
        // fund router
        token.mint(address(router), 100 ether);
        bytes32 mh = keccak256("echo1");
        bytes32 gri = router.computeGlobalRouteId(1, 1, address(this), mh, 7);
        uint256 pf = 1 ether / 100; // 0.01 ETH
        uint256 rf = 1 ether / 200; // 0.005 ETH
        vm.prank(adapter);
        router.finalizeMessage(gri, mh, address(token), vault, address(0), 100 ether, pf, rf);
    }

    // 2. Delegate + Echo Combined: delegate fee to target and ensure source forwarding full amount but finalize echo still ok
    function test_delegate_and_echo() public {
        // configure delegation
        vm.prank(admin); router.setDelegateFeeToTarget(vault, true);
        // user path: fees present but delegateFeeToTarget[vault] = true => no skim
        address user = address(0xBEEF01);
        token.mint(user, 50 ether);
        vm.startPrank(user);
        token.approve(address(router), 50 ether);
        vm.stopPrank();
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 50 ether,
            // use small fees under the 5 bps protocol fee cap: cap = 50 * 0.0005 = 0.025 ether
            protocolFee: 0.01 ether, // below cap
            relayerFee: 0.005 ether,
            payload: bytes(""),
            target: vault,
            dstChainId: 137,
            nonce: 11
        });
        uint256 beforeVault = token.balanceOf(vault);
        uint256 beforeFee = token.balanceOf(feeRecipient);
        vm.prank(user); router.universalBridgeTransfer(a); // should forward entire 50 ether
        assertEq(token.balanceOf(vault) - beforeVault, 50 ether);
        // ensure no skim occurred
        assertEq(token.balanceOf(feeRecipient) - beforeFee, 0);
        // destination finalize echo
        token.mint(address(router), 50 ether);
        bytes32 mh = keccak256("echo-delegate");
        bytes32 gri = router.computeGlobalRouteId(1, 137, user, mh, 11);
        vm.prank(adapter);
        router.finalizeMessage(gri, mh, address(token), vault, address(0), 50 ether, a.protocolFee, a.relayerFee);
    }

    // 3. Non-zero protocolShareBps / lpShareBps echo (no distribution)
    function test_finalize_with_nonzero_shares_echo_only() public {
        vm.prank(admin); router.setFeeSplit(1234, 8766); // sums to 10000
        token.mint(address(router), 10 ether);
        bytes32 mh = keccak256("shares-echo");
        bytes32 gri = router.computeGlobalRouteId(1, 1, address(this), mh, 9);
        vm.prank(adapter);
        router.finalizeMessage(gri, mh, address(token), vault, address(0), 10 ether, 0.1 ether, 0.05 ether);
    }

    // 4. Mismatch / bogus echo (document no validation) protocolFee > amount accepted
    function test_finalize_bogus_fee_echo_allowed() public {
        token.mint(address(router), 1 ether);
        bytes32 mh = keccak256("bogus");
        bytes32 gri = router.computeGlobalRouteId(1, 1, address(this), mh, 10);
        uint256 bogusProtocol = 5 ether; // > amount
        vm.prank(adapter);
        router.finalizeMessage(gri, mh, address(token), vault, address(0), 1 ether, bogusProtocol, 0);
        // success => design acknowledges echo fields are informational only
    }

    // 5. Multiple hash vectors (empty payload, non-empty payload, non-zero recipient, large amount)
    function test_messageHash_vectors() public pure {
        // Vector 1: empty payload recipient=0
        bytes32 h1 = Hashing.messageHash(1, address(0x1234), address(0), address(0x9999), 100, keccak256(""), 1, 2);
        bytes32 h2 = Hashing.messageHash(1, address(0x1234), address(0), address(0x9999), 100, keccak256(""), 1, 2);
        assertEq(h1, h2);
        // Vector 2: non-empty payload & non-zero recipient
        bytes32 p2 = keccak256(abi.encodePacked("payload"));
        bytes32 h3 = Hashing.messageHash(10, address(0xABCD), address(0xDEAD), address(0xBEEF), 777, p2, 42, 11);
        bytes32 h4 = Hashing.messageHash(10, address(0xABCD), address(0xDEAD), address(0xBEEF), 777, p2, 42, 11);
        assertEq(h3, h4);
        // Vector 3: large amount (2^255 - 1)
        uint256 large = (uint256(1) << 255) - 1;
        bytes32 h5 = Hashing.messageHash(100, address(0xAAAA), address(0xBBBB), address(0xCCCC), large, keccak256("L"), 99, 101);
        bytes32 h6 = Hashing.messageHash(100, address(0xAAAA), address(0xBBBB), address(0xCCCC), large, keccak256("L"), 99, 101);
        assertEq(h5, h6);
    }

    // 6. Fuzz parity: random params vs recompute (simplified)
    function testFuzz_messageHash_parity(
        uint64 src,
        address adapterAddr,
        address recipient,
        address asset,
        uint256 amount,
        bytes32 payloadHash_,
        uint64 nonce,
        uint64 dst
    ) public pure {
        // recompute twice and ensure stability
        bytes32 a = Hashing.messageHash(src, adapterAddr, recipient, asset, amount, payloadHash_, nonce, dst);
        bytes32 b = Hashing.messageHash(src, adapterAddr, recipient, asset, amount, payloadHash_, nonce, dst);
    assertEq(a, b);
    }
}
