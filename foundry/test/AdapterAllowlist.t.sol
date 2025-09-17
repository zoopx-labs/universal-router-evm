// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "../../contracts/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract DummyTarget {
    event Ping(uint256 v);
    function ping(uint256 v) external { emit Ping(v); }
}

contract AdapterAllowlistTest is Test {
    Router router;
    MockERC20 token;
    address admin = address(0xA11CE);
    address adapterA = address(0xADAB0A);
    address adapterB = address(0xB0B);
    address vault = address(0x1111111111111111111111111111111111111111);
    address lp = address(0x2222222222222222222222222222222222222222);

    function setUp() public {
        vm.prank(admin);
        // deploy router with arbitrary defaultTarget = vault, srcChainId=1
        router = new Router(admin, admin, vault, 1);
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(address(this), 1_000_000 ether);
        token.approve(address(router), type(uint256).max);
    }

    function _grantAdapter(address a) internal {
    vm.prank(admin);
    router.addAdapter(a);
    }

    function _finalize(bytes32 gr, bytes32 mh, uint256 amount, uint256 protocolFee, uint256 relayerFee, address caller) internal {
        vm.prank(caller);
        router.finalizeMessage(gr, mh, address(token), vault, lp, amount, protocolFee, relayerFee);
    }

    function testAddRemoveAdapter() public {
        // grant A
        _grantAdapter(adapterA);
        bytes32 mh = keccak256("msg1");
        bytes32 gr = keccak256("gr1");
        token.mint(address(router), 100 ether);
        // finalize by A succeeds
        _finalize(gr, mh, 100 ether, 0, 0, adapterA);
        // remove A
    vm.prank(admin);
    router.removeAdapter(adapterA);
    vm.prank(adapterA);
    vm.expectRevert(Router.NotAdapter.selector);
    router.finalizeMessage(gr, keccak256("new"), address(token), vault, lp, 100 ether, 0, 0);
    }

    function testFreezeAdapter() public {
        _grantAdapter(adapterA);
        bytes32 mh = keccak256("msg2");
        bytes32 gr = keccak256("gr2");
        token.mint(address(router), 150 ether);
        _finalize(gr, mh, 50 ether, 0, 0, adapterA);
        // freeze
    vm.prank(admin);
    router.freezeAdapter(adapterA, true);
    vm.prank(adapterA);
    vm.expectRevert(Router.AdapterFrozenErr.selector);
    router.finalizeMessage(gr, keccak256("x"), address(token), vault, lp, 50 ether, 0, 0);
        // unfreeze
        vm.prank(admin);
        router.freezeAdapter(adapterA, false);
        _finalize(gr, keccak256("y"), 50 ether, 0, 0, adapterA);
    }

    function testReplayUnaffected() public {
        _grantAdapter(adapterA);
        bytes32 mh = keccak256("msg3");
        bytes32 gr = keccak256("gr3");
        token.mint(address(router), 10 ether);
        _finalize(gr, mh, 10 ether, 0, 0, adapterA);
        vm.prank(adapterA);
        vm.expectRevert(Router.MessageAlreadyUsed.selector);
        router.finalizeMessage(gr, mh, address(token), vault, lp, 10 ether, 0, 0);
    }

    function testTargetAllowlist() public {
        // Deploy dummy contract target
        DummyTarget dt = new DummyTarget();
        // Enforce allowlist
        vm.prank(admin);
        router.setEnforceTargetAllowlist(true);

        // Not yet allowed -> should revert TargetNotContract (because enforceTargetAllowlist && !isAllowedTarget[target])
        Router.TransferArgs memory args1 = Router.TransferArgs({
            token: address(token),
            amount: 1 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("ping(uint256)", 1),
            target: address(dt),
            dstChainId: 2,
            nonce: 42
        });
        token.mint(address(this), 1 ether);
        vm.expectRevert(Router.TargetNotContract.selector);
        router.universalBridgeTransfer(args1);

        // Allow the target
        vm.prank(admin);
        router.setAllowedTarget(address(dt), true);
        // Now succeeds
        router.universalBridgeTransfer(args1);

        // Disable enforcement and try with another fresh dummy contract not allowlisted
        DummyTarget dt2 = new DummyTarget();
        vm.prank(admin);
        router.setEnforceTargetAllowlist(false);
        Router.TransferArgs memory args2 = Router.TransferArgs({
            token: address(token),
            amount: 1 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("ping(uint256)", 2),
            target: address(dt2),
            dstChainId: 2,
            nonce: 43
        });
        token.mint(address(this), 1 ether);
        router.universalBridgeTransfer(args2); // succeeds without allowlisting
    }
}
