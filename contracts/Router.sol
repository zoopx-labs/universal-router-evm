// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Router {
    using SafeERC20 for IERC20;

    error ZeroAmount();
    error FeeTooHigh();
    error FeesExceedAmount();
    error TargetNotSet();

    event BridgeInitiated(
        address indexed user,
        address indexed token,
        address indexed target,
        uint256 amount,
        uint256 protocolFee,
        uint256 relayerFee,
        bytes32 payloadHash,
        uint16 srcChainId,
        uint16 dstChainId,
        uint64 nonce
    );

    uint16 public constant FEE_CAP_BPS = 5; // 0.05%
    address public immutable feeRecipient;
    address public immutable defaultTarget; // optional: 0x0 means caller must pass target
    uint16  public immutable SRC_CHAIN_ID;

    constructor(address _feeRecipient, address _defaultTarget, uint16 _srcChainId) {
        require(_feeRecipient != address(0), "bad feeRecipient");
        feeRecipient = _feeRecipient;
        defaultTarget = _defaultTarget;
        SRC_CHAIN_ID = _srcChainId;
    }

    function universalBridgeTransfer(
        address token,
        uint256 amount,
        uint256 protocolFee,
        uint256 relayerFee,
        bytes calldata payload,
        address target,         // override defaultTarget if nonzero
        uint16 dstChainId,
        uint64 nonce
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (protocolFee * 10000 > amount * FEE_CAP_BPS) revert FeeTooHigh();
        if (protocolFee + relayerFee > amount) revert FeesExceedAmount();

        address _target = target != address(0) ? target : defaultTarget;
        if (_target == address(0)) revert TargetNotSet();

        IERC20 t = IERC20(token);

        // Pull full amount from user
        t.safeTransferFrom(msg.sender, address(this), amount);

        // Fees → feeRecipient in a single transfer
        uint256 totalFees = protocolFee + relayerFee;
        if (totalFees > 0) {
            t.safeTransfer(feeRecipient, totalFees);
        }

        // Remainder → target custody (adapter) or its escrow
        uint256 forwardAmount = amount - totalFees;
        t.safeTransfer(_target, forwardAmount);

        emit BridgeInitiated(
            msg.sender,
            token,
            _target,
            forwardAmount,
            protocolFee,
            relayerFee,
            keccak256(payload),
            SRC_CHAIN_ID,
            dstChainId,
            nonce
        );

        // Forward opaque payload to target (stateless router, no reentrancy-sensitive state)
        // Target should implement its own checks / replay protection / auth.
        (bool ok, ) = _target.call(payload);
        require(ok, "target call failed");
    }
}
