// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {ERC20PermitMock} from "foundry/test/mocks/ERC20PermitMock.sol";
import {DAIPermitMock} from "foundry/test/mocks/DAIPermitMock.sol";

contract PermitTarget {
    function noop() external {}
}

contract Router_BranchCoverage10_PermitAllowlist is Test {
    address admin = address(this);
    address fee = address(0xFEEA);

    function test_permit_allowlist_blocks_unapproved_target() public {
        Router r = new Router(admin, fee, address(0), 1);
        ERC20PermitMock p = new ERC20PermitMock("Permit", "PRM");
        PermitTarget t = new PermitTarget();
        // Enforce allowlist but do NOT add target
        r.setEnforceTargetAllowlist(true);

        address holder = vm.addr(0x1111);
        p.mint(holder, 10 ether);
        vm.startPrank(holder);
        // Sign a permit: holder -> router for 10 ether
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                p.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        p.PERMIT_TYPEHASH(),
                        holder,
                        address(r),
                        10 ether,
                        p.nonces(holder),
                        block.timestamp + 1 days
                    )
                )
            )
        );
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(0x1111, digest);
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(p),
            amount: 10 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("noop()"),
            target: address(t),
            dstChainId: 2,
            nonce: 1
        });
        // Enforced allowlist + unapproved contract target => TargetNotContract revert
        vm.expectRevert(Router.TargetNotContract.selector);
        r.universalBridgeTransferWithPermit(a, block.timestamp + 1 days, v, rr, ss);
        vm.stopPrank();
    }

    function test_dai_permit_allowlist_blocks_unapproved_target() public {
        Router r = new Router(admin, fee, address(0), 1);
        DAIPermitMock d = new DAIPermitMock("DAI", "DAI");
        PermitTarget t = new PermitTarget();
        // Enforce allowlist but do NOT add target
        r.setEnforceTargetAllowlist(true);

        address holder = vm.addr(0x2222);
        d.mint(holder, 10 ether);
        vm.startPrank(holder);
        uint256 nonce = d.nonces(holder);
        uint256 expiry = block.timestamp + 1 days;
        bool allowed = true;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                d.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(d.PERMIT_TYPEHASH(), holder, address(r), nonce, expiry, allowed))
            )
        );
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(0x2222, digest);

        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(d),
            amount: 10 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: abi.encodeWithSignature("noop()"),
            target: address(t),
            dstChainId: 2,
            nonce: 2
        });
        vm.expectRevert(Router.TargetNotContract.selector);
        r.universalBridgeTransferWithDAIPermit(a, nonce, expiry, allowed, v, rr, ss);
        vm.stopPrank();
    }
}
