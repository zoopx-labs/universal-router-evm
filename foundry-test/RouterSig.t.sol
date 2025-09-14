// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/Router.sol";
import "../contracts/MockERC20.sol";

contract RouterSigTest is Test {
    Router router;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20("Mock", "MCK");
        router = new Router(address(this), address(0), 1);
    }

    function testSignedAdapterFlow() public {
        // create user key
        uint256 userKey = 0xA11CE;
        address user = vm.addr(userKey);
        token.mint(user, 1e18);

        vm.startPrank(user);
        token.approve(address(router), 1e18);
        vm.stopPrank();

        // build intent struct hash
        bytes32 payloadHash = keccak256(abi.encodePacked("payload"));
        bytes32 routeId = keccak256(abi.encodePacked("routePlanExample"));

        // deploy helper to compute EIP-712 digest
        EIP712Helper helper = new EIP712Helper();

        bytes32 structHash = keccak256(
            abi.encode(
                router.ROUTE_INTENT_TYPEHASH_PUBLIC(),
                routeId,
                user,
                address(token),
                uint256(1e18),
                uint256(0),
                uint256(0),
                uint16(2),
                user,
                uint256(block.timestamp + 3600),
                payloadHash,
                uint64(1)
            )
        );

        bytes32 digest = helper.hashStruct(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        // call router as relayer
        vm.prank(address(this));
        router.universalBridgeTransferWithSig(
            Router.TransferArgs({
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                payload: abi.encodePacked("payload"),
                target: address(this),
                dstChainId: 2,
                nonce: 1
            }),
            Router.RouteIntent({
                routeId: routeId,
                user: user,
                token: address(token),
                amount: 1e18,
                protocolFee: 0,
                relayerFee: 0,
                dstChainId: 2,
                recipient: user,
                expiry: block.timestamp + 3600,
                payloadHash: payloadHash,
                nonce: 1
            }),
            abi.encodePacked(r, s, v),
            user
        );
    }
}
