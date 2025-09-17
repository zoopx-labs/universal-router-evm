// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Router} from "contracts/Router.sol";
import {ERC20PermitMock} from "foundry/test/mocks/ERC20PermitMock.sol";

contract PermitPathsTest is Test {
    Router router;
    ERC20PermitMock token;
    address admin = address(0xA11CE);
    address feeRecipient = address(0xFEE5);
    address target = address(0xBEEF);

    function setUp() public {
        vm.prank(admin);
        router = new Router(admin, feeRecipient, target, uint16(111));
        token = new ERC20PermitMock("Permit", "PRM");
        token.mint(address(this), 1000 ether);
    }

    function _signPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        token.PERMIT_TYPEHASH(),
                        owner,
                        spender,
                        value,
                        token.nonces(owner),
                        deadline
                    )
                )
            )
        );
        (v, r, s) = vm.sign(1, digest); // note: owner must be derived from private key 1 for real signature; we will use prank
    }

    function test_universal_with_permit_allows_skim_or_delegate() public {
        // use prank to set msg.sender as holder corresponding to key 1
        address holder = vm.addr(1);
        token.mint(holder, 100 ether);
        vm.startPrank(holder);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(holder, address(router), 10 ether, block.timestamp + 1 days);
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
        router.universalBridgeTransferWithPermit(a, block.timestamp + 1 days, v, r, s);
        vm.stopPrank();
    }
}
