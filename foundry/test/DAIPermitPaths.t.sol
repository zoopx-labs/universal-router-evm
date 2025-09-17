// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {DAIPermitMock} from "foundry/test/mocks/DAIPermitMock.sol";

contract DAIPermitPathsTest is Test {
    Router router;
    DAIPermitMock token;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEE5);
    address target = address(0xBEEF);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, feeRecipient, target, uint16(111));
        token = new DAIPermitMock("DAIPermit", "DPRM");
        token.mint(address(this), 1000 ether);
    }

    function _signDAIPermit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(token.PERMIT_TYPEHASH(), holder, spender, nonce, expiry, allowed)
                )
            )
        );
        (v, r, s) = vm.sign(1, digest);
    }

    function test_universal_with_dai_permit_path() public {
        address holder = vm.addr(1);
        token.mint(holder, 100 ether);
        vm.startPrank(holder);
        (uint8 v, bytes32 r, bytes32 s) = _signDAIPermit(holder, address(router), token.nonces(holder), block.timestamp + 1 days, true);
        Router.TransferArgs memory a = Router.TransferArgs({
            token: address(token),
            amount: 10 ether,
            protocolFee: 0,
            relayerFee: 0,
            payload: "",
            target: target,
            dstChainId: 222,
            nonce: 9
        });
        router.universalBridgeTransferWithDAIPermit(a, token.nonces(holder), block.timestamp + 1 days, true, v, r, s);
        vm.stopPrank();
    }
}
