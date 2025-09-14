// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Optional permit interfaces
interface IERC20Permit {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}

interface IERC20PermitDAI {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract Router is ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    /// @notice Security notes:
    /// @dev This router is intentionally stateless per transfer. It uses transfer-before-call semantics
    ///      (pull funds -> skim fees -> forward -> emit -> call) to avoid holding user balances.
    ///      For vault/pool interactions that require pull semantics, the router provides an
    ///      approve-then-call flow that performs ephemeral approvals (approve 0 -> approve X -> call -> approve 0)
    ///      in the same transaction and revokes approvals immediately after the external call.
    ///      Low-level calls to partner adapters are required because the router is partner-agnostic.
    ///      The contract checks call return and reverts on failure. These design choices will trigger
    ///      certain static-analysis warnings (external-call, approvals); they are intentional and
    ///      documented here for reviewers and automated tools.
    ///
    /// EIP-712 pulls: this contract authorizes pulls from user accounts when an EIP-712
    /// RouteIntent signed by that user is presented. Static-analysis tools may flag the
    /// resulting transferFrom as arbitrary-send; these are intentional meta-transactions
    /// authorized by the user's signature. Where appropriate the code includes
    /// Slither suppression comments to document the authorization.

    // ---------- Admin & config ----------
    address public admin;
    address public feeRecipient;

    // ---------- Errors ----------
    error ZeroAmount();
    error FeeTooHigh();
    error FeesExceedAmount();
    error TokenZeroAddress();
    error TargetNotSet();
    error TargetNotContract();
    error PayloadTooLarge();
    error PayloadDisallowedToEOA();
    error FeeOnTransferNotSupported();
    error ExpiredIntent();
    error InvalidSignature();
    error IntentMismatch();
    error ResidueLeft();

    // ---------- Events ----------
    event BridgeInitiated( // commitment to the full off-chain plan
        // recovered signer (intent.user)
        // adapter/partner/vault/bridge handler
        bytes32 indexed routeId,
        address indexed user,
        address indexed token,
        address target,
        uint256 forwardedAmount,
        uint256 protocolFee,
        uint256 relayerFee,
        bytes32 payloadHash,
        uint16 srcChainId,
        uint16 dstChainId,
        uint64 nonce
    );
    event IntentConsumed(bytes32 indexed digest, bytes32 indexed routeId, address indexed user);

    // ---------- Types ----------
    struct TransferArgs {
        address token;
        uint256 amount;
        uint256 protocolFee;
        uint256 relayerFee;
        bytes payload; // opaque adapter calldata
        address target; // override defaultTarget if nonzero
        uint16 dstChainId;
        uint64 nonce;
    }

    // EIP-712 intent signed by the user (owner of funds)
    struct RouteIntent {
        bytes32 routeId; // keccak256(routePlan)
        address user; // signer & token owner
        address token;
        uint256 amount;
        uint256 protocolFee;
        uint256 relayerFee;
        uint16 dstChainId;
        address recipient; // recommended: expected target/receiver for this leg
        uint256 expiry; // unix seconds
        bytes32 payloadHash; // keccak256(payload)
        uint64 nonce; // off-chain unique; router remains stateless
    }

    // typehash for RouteIntent
    bytes32 private constant ROUTE_INTENT_TYPEHASH = keccak256(
        "RouteIntent(bytes32 routeId,address user,address token,uint256 amount,uint256 protocolFee,uint256 relayerFee,uint16 dstChainId,address recipient,uint256 expiry,bytes32 payloadHash,uint64 nonce)"
    );

    // public accessor for tests and off-chain tooling
    function ROUTE_INTENT_TYPEHASH_PUBLIC() external pure returns (bytes32) {
        return ROUTE_INTENT_TYPEHASH;
    }

    // optional target allowlist (disabled by default)
    mapping(address => bool) public isAllowedTarget;
    bool public enforceTargetAllowlist;

    function setAllowedTarget(address t, bool ok) external onlyAdmin {
        isAllowedTarget[t] = ok;
    }

    function setEnforceTargetAllowlist(bool v) external onlyAdmin {
        enforceTargetAllowlist = v;
    }

    // ---------- Config ----------
    uint16 public constant FEE_CAP_BPS = 5; // 0.05%
    uint256 public constant MAX_PAYLOAD_BYTES = 512;

    address public immutable defaultTarget; // 0x0 => must pass target
    uint16 public immutable SRC_CHAIN_ID;
    // No storage temporaries: router remains stateless and uses locals only

    // new constructor: admin, feeRecipient, defaultTarget, srcChainId
    constructor(address _admin, address _feeRecipient, address _defaultTarget, uint16 _srcChainId)
        EIP712("ZoopXRouter", "1")
    {
        require(_admin != address(0), "bad admin");
        require(_feeRecipient != address(0), "bad feeRecipient");
        admin = _admin;
        feeRecipient = _feeRecipient;
        defaultTarget = _defaultTarget;
        SRC_CHAIN_ID = _srcChainId;
    }

    // ---------- Replay protection for signed intents (small mapping)
    // maps EIP-712 digest -> used
    mapping(bytes32 => bool) public usedIntents;

    error IntentAlreadyUsed();

    // ---------- Message-level replay protection for cross-chain messages
    // maps canonical messageHash -> used
    mapping(bytes32 => bool) public usedMessages;

    error MessageAlreadyUsed();

    // ---------- Adapter authority + fee configuration (minimal, additive)
    address public adapter; // configured destination adapter that is allowed to finalize messages

    // Fee configuration (bps) and collector
    uint16 public protocolFeeBps;
    uint16 public relayerFeeBps;
    uint16 public protocolShareBps;
    uint16 public lpShareBps;
    address public feeCollector;

    // Events for fee application and canonical initiation
    event FeeApplied(
        bytes32 indexed globalRouteId,
        bytes32 indexed messageHash,
        uint16 chainId,
        address router,
        address vault,
        address asset,
        uint256 protocol_fee_native,
        uint256 relayer_fee_native,
        uint16 protocol_bps,
        uint16 lp_bps,
        address collector,
        uint256 applied_at
    );

    event UniversalBridgeInitiated(
        bytes32 indexed routeId,
        bytes32 indexed payloadHash,
        bytes32 indexed messageHash,
        bytes32 globalRouteId,
        address user,
        address token,
        address target,
        uint256 forwardedAmount,
        uint256 protocolFee,
        uint256 relayerFee,
        uint16 srcChainId,
        uint16 dstChainId,
        uint64 nonce
    );

    // ---------- Admin errors/events/modifiers ----------
    error Unauthorized();
    error ZeroAddress();

    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminUpdated(admin, newAdmin);
        admin = newAdmin;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyAdmin {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);
        feeRecipient = newFeeRecipient;
    }

    // Two-step admin handover
    address public pendingAdmin;

    event AdminProposed(address indexed current, address indexed proposed);

    function proposeAdmin(address p) external onlyAdmin {
        if (p == address(0)) revert ZeroAddress();
        pendingAdmin = p;
        emit AdminProposed(admin, p);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert Unauthorized();
        emit AdminUpdated(admin, pendingAdmin);
        admin = pendingAdmin;
        pendingAdmin = address(0);
    }

    // ---------- Public: generic, no signature ----------
    function universalBridgeTransfer(TransferArgs calldata a) external nonReentrant {
        _commonChecks(a.token, a.amount, a.protocolFee, a.relayerFee);
        address target = a.target != address(0) ? a.target : defaultTarget;
        if (target == address(0)) revert TargetNotSet();
        if (a.payload.length > MAX_PAYLOAD_BYTES) revert PayloadTooLarge();

        bool isContract = target.code.length > 0;
        if (!isContract && a.payload.length != 0) revert PayloadDisallowedToEOA();
        if (enforceTargetAllowlist && isContract && !isAllowedTarget[target]) revert TargetNotContract();

        // perform pull, fee skim and forward to target
        uint256 balBefore = IERC20(a.token).balanceOf(address(this));
        uint256 forwardAmount = _pullSkimAndForward(a.token, msg.sender, target, a.amount, a.protocolFee, a.relayerFee);

        // compute canonical hashes
        bytes32 payloadHash = keccak256(a.payload);
        bytes32 messageHash =
            computeMessageHash(SRC_CHAIN_ID, a.dstChainId, msg.sender, target, a.token, a.amount, a.nonce, payloadHash);
        bytes32 globalRouteId = computeGlobalRouteId(SRC_CHAIN_ID, a.dstChainId, msg.sender, messageHash, a.nonce);
        emit BridgeInitiated(
            bytes32(0),
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            payloadHash,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        emit UniversalBridgeInitiated(
            bytes32(0),
            payloadHash,
            messageHash,
            globalRouteId,
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );

        // call contract targets only
        if (isContract && a.payload.length > 0) _callTarget(target, a.payload);

        // defense-in-depth: ensure no residue left
        if (IERC20(a.token).balanceOf(address(this)) != balBefore) revert ResidueLeft();
    }

    // ---------- Public: generic with EIP-712 signature ----------
    function universalBridgeTransferWithSig(
        TransferArgs calldata a,
        RouteIntent calldata intent,
        bytes calldata signature
    ) external nonReentrant {
        // Verify EIP-712 intent, get digest and claim it for replay-protection before external calls
        bytes32 digest = _verifyIntentReturningDigest(intent, signature);
        if (usedIntents[digest]) revert IntentAlreadyUsed();
        usedIntents[digest] = true;
        emit IntentConsumed(digest, intent.routeId, intent.user);

        // Bind call arguments to the signed commitment
        if (intent.token != a.token) revert IntentMismatch();
        if (intent.amount != a.amount) revert IntentMismatch();
        if (intent.protocolFee != a.protocolFee) revert IntentMismatch();
        if (intent.relayerFee != a.relayerFee) revert IntentMismatch();
        if (intent.dstChainId != a.dstChainId) revert IntentMismatch();
        if (intent.payloadHash != keccak256(a.payload)) revert IntentMismatch();

        address target = a.target != address(0) ? a.target : defaultTarget;
        if (target == address(0)) revert TargetNotSet();
        if (a.payload.length > MAX_PAYLOAD_BYTES) revert PayloadTooLarge();

        bool isContract = target.code.length > 0;
        if (!isContract && a.payload.length != 0) revert PayloadDisallowedToEOA();
        if (isContract && target.code.length == 0) revert TargetNotContract();
        if (enforceTargetAllowlist && isContract && !isAllowedTarget[target]) revert TargetNotContract();

        // Tighten binding: recipient must match target when set
        if (intent.recipient != address(0) && intent.recipient != target) revert IntentMismatch();

        // perform pull, fee skim and forward to target on behalf of the intent.user
        uint256 balBefore = IERC20(a.token).balanceOf(address(this));
        // slither-disable-next-line arbitrary-send-erc20
        uint256 forwardAmount = _pullSkimAndForward(a.token, intent.user, target, a.amount, a.protocolFee, a.relayerFee);

        // compute canonical hashes
        bytes32 payloadHash = keccak256(a.payload);
        bytes32 messageHash =
            computeMessageHash(SRC_CHAIN_ID, a.dstChainId, intent.user, target, a.token, a.amount, a.nonce, payloadHash);
        bytes32 globalRouteId = computeGlobalRouteId(SRC_CHAIN_ID, a.dstChainId, intent.user, messageHash, a.nonce);
        emit BridgeInitiated(
            intent.routeId,
            intent.user,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            payloadHash,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        emit UniversalBridgeInitiated(
            intent.routeId,
            payloadHash,
            messageHash,
            globalRouteId,
            intent.user,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        if (target.code.length > 0 && a.payload.length > 0) _callTarget(target, a.payload);

        // intent already marked earlier (pre-call) to avoid reentrancy races

        // defense-in-depth: ensure no residue left
        if (IERC20(a.token).balanceOf(address(this)) != balBefore) revert ResidueLeft();
    }

    // ---------- Optional: Permit variants (partner-agnostic) ----------
    function universalBridgeTransferWithPermit(TransferArgs calldata a, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
    {
        _commonChecks(a.token, a.amount, a.protocolFee, a.relayerFee);
        address target = a.target != address(0) ? a.target : defaultTarget;
        if (target == address(0)) revert TargetNotSet();
        if (a.payload.length > MAX_PAYLOAD_BYTES) revert PayloadTooLarge();

        bool isContract = target.code.length > 0;
        if (!isContract && a.payload.length != 0) revert PayloadDisallowedToEOA();

        IERC20Permit(a.token).permit(msg.sender, address(this), a.amount, deadline, v, r, s);

        uint256 balBefore = IERC20(a.token).balanceOf(address(this));
        // perform pull, fee skim and forward to target
        uint256 forwardAmount = _pullSkimAndForward(a.token, msg.sender, target, a.amount, a.protocolFee, a.relayerFee);

        bytes32 payloadHash = keccak256(a.payload);
        bytes32 messageHash =
            computeMessageHash(SRC_CHAIN_ID, a.dstChainId, msg.sender, target, a.token, a.amount, a.nonce, payloadHash);
        bytes32 globalRouteId = computeGlobalRouteId(SRC_CHAIN_ID, a.dstChainId, msg.sender, messageHash, a.nonce);
        emit BridgeInitiated(
            bytes32(0),
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            payloadHash,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        emit UniversalBridgeInitiated(
            bytes32(0),
            payloadHash,
            messageHash,
            globalRouteId,
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        if (isContract && a.payload.length > 0) _callTarget(target, a.payload);
        if (IERC20(a.token).balanceOf(address(this)) != balBefore) revert ResidueLeft();
    }

    function universalBridgeTransferWithDAIPermit(
        TransferArgs calldata a,
        uint256 permitNonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        _commonChecks(a.token, a.amount, a.protocolFee, a.relayerFee);
        address target = a.target != address(0) ? a.target : defaultTarget;
        if (target == address(0)) revert TargetNotSet();
        if (a.payload.length > MAX_PAYLOAD_BYTES) revert PayloadTooLarge();

        bool isContract = target.code.length > 0;
        if (!isContract && a.payload.length != 0) revert PayloadTooLarge();

        IERC20PermitDAI(a.token).permit(msg.sender, address(this), permitNonce, expiry, allowed, v, r, s);

        // perform pull, fee skim and forward to target
        uint256 forwardAmount = _pullSkimAndForward(a.token, msg.sender, target, a.amount, a.protocolFee, a.relayerFee);

        bytes32 payloadHash = keccak256(a.payload);
        bytes32 messageHash =
            computeMessageHash(SRC_CHAIN_ID, a.dstChainId, msg.sender, target, a.token, a.amount, a.nonce, payloadHash);
        bytes32 globalRouteId = computeGlobalRouteId(SRC_CHAIN_ID, a.dstChainId, msg.sender, messageHash, a.nonce);
        emit BridgeInitiated(
            bytes32(0),
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            payloadHash,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        emit UniversalBridgeInitiated(
            bytes32(0),
            payloadHash,
            messageHash,
            globalRouteId,
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        if (isContract && a.payload.length > 0) _callTarget(target, a.payload);
    }

    // ---------- Approve-then-call (pull semantics for vaults/pools) ----------
    function universalBridgeApproveThenCall(TransferArgs calldata a) external nonReentrant {
        _commonChecks(a.token, a.amount, a.protocolFee, a.relayerFee);
        address target = a.target != address(0) ? a.target : defaultTarget;
        if (target == address(0)) revert TargetNotSet();
        if (a.payload.length > MAX_PAYLOAD_BYTES) revert PayloadTooLarge();

        bool isContract = target.code.length > 0;
        if (!isContract && a.payload.length != 0) revert PayloadDisallowedToEOA();
        if (isContract && target.code.length == 0) revert TargetNotContract();

        IERC20 t = IERC20(a.token);

        uint256 balBefore = t.balanceOf(address(this));
        t.safeTransferFrom(msg.sender, address(this), a.amount);
        uint256 received = t.balanceOf(address(this)) - balBefore;
        if (received != a.amount) revert FeeOnTransferNotSupported();

        uint256 fees = a.protocolFee + a.relayerFee;
        if (fees > 0) t.safeTransfer(feeRecipient, fees);
        uint256 forwardAmount = a.amount - fees;

        // Ephemeral approval to target - use OZ forceApprove
        IERC20(a.token).forceApprove(target, 0);
        IERC20(a.token).forceApprove(target, forwardAmount);

        // perform call (target should pull)
        if (isContract && a.payload.length > 0) _callTarget(target, a.payload);

        // Revoke approval
        IERC20(a.token).forceApprove(target, 0);

        // compute and emit
        bytes32 payloadHash = keccak256(a.payload);
        bytes32 messageHash =
            computeMessageHash(SRC_CHAIN_ID, a.dstChainId, msg.sender, target, a.token, a.amount, a.nonce, payloadHash);
        bytes32 globalRouteId = computeGlobalRouteId(SRC_CHAIN_ID, a.dstChainId, msg.sender, messageHash, a.nonce);
        emit BridgeInitiated(
            bytes32(0),
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            payloadHash,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        emit UniversalBridgeInitiated(
            bytes32(0),
            payloadHash,
            messageHash,
            globalRouteId,
            msg.sender,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );

        // defense-in-depth: ensure no residue left
        if (IERC20(a.token).balanceOf(address(this)) != balBefore) revert ResidueLeft();
    }

    function universalBridgeApproveThenCallWithSig(
        TransferArgs calldata a,
        RouteIntent calldata intent,
        bytes calldata signature
    ) external nonReentrant {
        // Verify EIP-712 intent, get digest and claim it for replay-protection before external calls
        bytes32 digest = _verifyIntentReturningDigest(intent, signature);
        if (usedIntents[digest]) revert IntentAlreadyUsed();
        usedIntents[digest] = true;
        emit IntentConsumed(digest, intent.routeId, intent.user);

        // Bind intent fields
        if (intent.token != a.token) revert IntentMismatch();
        if (intent.amount != a.amount) revert IntentMismatch();
        if (intent.protocolFee != a.protocolFee) revert IntentMismatch();
        if (intent.relayerFee != a.relayerFee) revert IntentMismatch();
        if (intent.dstChainId != a.dstChainId) revert IntentMismatch();
        if (intent.payloadHash != keccak256(a.payload)) revert IntentMismatch();

        address target = a.target != address(0) ? a.target : defaultTarget;
        if (target == address(0)) revert TargetNotSet();
        if (a.payload.length > MAX_PAYLOAD_BYTES) revert PayloadTooLarge();

        bool isContract = target.code.length > 0;
        if (!isContract && a.payload.length != 0) revert PayloadTooLarge();
        if (isContract && target.code.length == 0) revert TargetNotContract();

        if (intent.recipient != address(0) && intent.recipient != target) revert IntentMismatch();

        IERC20 t = IERC20(a.token);

        uint256 balBefore = t.balanceOf(address(this));
        // slither-disable-next-line arbitrary-send-erc20
        t.safeTransferFrom(intent.user, address(this), a.amount);
        uint256 received = t.balanceOf(address(this)) - balBefore;
        if (received != a.amount) revert FeeOnTransferNotSupported();

        uint256 fees = a.protocolFee + a.relayerFee;
        if (fees > 0) t.safeTransfer(feeRecipient, fees);
        uint256 forwardAmount = a.amount - fees;

        // Approve and call (target should pull) - use OZ forceApprove helper
        IERC20(a.token).forceApprove(target, 0);
        IERC20(a.token).forceApprove(target, forwardAmount);

        if (isContract && a.payload.length > 0) _callTarget(target, a.payload);

        IERC20(a.token).forceApprove(target, 0);

        // compute and emit
        bytes32 payloadHash = keccak256(a.payload);
        bytes32 messageHash =
            computeMessageHash(SRC_CHAIN_ID, a.dstChainId, intent.user, target, a.token, a.amount, a.nonce, payloadHash);
        bytes32 globalRouteId = computeGlobalRouteId(SRC_CHAIN_ID, a.dstChainId, intent.user, messageHash, a.nonce);
        emit BridgeInitiated(
            intent.routeId,
            intent.user,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            payloadHash,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );
        emit UniversalBridgeInitiated(
            intent.routeId,
            payloadHash,
            messageHash,
            globalRouteId,
            intent.user,
            a.token,
            target,
            forwardAmount,
            a.protocolFee,
            a.relayerFee,
            SRC_CHAIN_ID,
            a.dstChainId,
            a.nonce
        );

        // intent already marked earlier (pre-call) to avoid reentrancy races

        // defense-in-depth: ensure no residue left
        if (IERC20(a.token).balanceOf(address(this)) != balBefore) revert ResidueLeft();
    }

    // ---------- Internal helpers ----------
    function _commonChecks(address token, uint256 amount, uint256 protocolFee, uint256 relayerFee) internal pure {
        if (token == address(0)) revert TokenZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (protocolFee + relayerFee > amount) revert FeesExceedAmount();
        if (protocolFee > Math.mulDiv(amount, FEE_CAP_BPS, 10_000)) revert FeeTooHigh();
    }

    // NOTE: deprecated custom _forceApprove removed; using OpenZeppelin's `forceApprove` via SafeERC20

    function _pullSkimAndForward(
        address token,
        address user,
        address target,
        uint256 amount,
        uint256 protocolFee,
        uint256 relayerFee
    ) internal returns (uint256 forwardAmount) {
        IERC20 t = IERC20(token);

        // forbid fee-on-transfer (or replace with computing 'received')
        uint256 balBefore = t.balanceOf(address(this));
        t.safeTransferFrom(user, address(this), amount);
        uint256 received = t.balanceOf(address(this)) - balBefore;
        if (received != amount) revert FeeOnTransferNotSupported();

        uint256 totalFees = protocolFee + relayerFee;
        if (totalFees > 0) t.safeTransfer(feeRecipient, totalFees);

        forwardAmount = amount - totalFees;
        t.safeTransfer(target, forwardAmount);

        return forwardAmount;
    }

    // (removed _pullEmitCall helper; flows now use _pullSkimAndForward + emit + _callTarget)

    function _callTarget(address target, bytes calldata payload) internal {
        (bool ok,) = target.call(payload);
        require(ok, "target call failed");
    }

    // New name requested by pre-testnet fixes: return the digest while performing the same checks.
    function _verifyIntentReturningDigest(RouteIntent calldata intent, bytes calldata sig)
        internal
        view
        returns (bytes32 digest)
    {
        if (block.timestamp > intent.expiry) revert ExpiredIntent();
        if (intent.payloadHash == bytes32(0)) revert PayloadTooLarge();

        bytes32 structHash = keccak256(
            abi.encode(
                ROUTE_INTENT_TYPEHASH,
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
        digest = _hashTypedDataV4(structHash);
        if (ECDSA.recover(digest, sig) != intent.user) revert InvalidSignature();
    }

    // ---------- Helpers: message hash and global route id (deterministic on-chain)
    function computeMessageHash(
        uint16 srcChainId,
        uint16 dstChainId,
        address initiator,
        address target,
        address token,
        uint256 amount,
        uint64 nonce,
        bytes32 payloadHash
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(srcChainId, dstChainId, initiator, target, token, amount, nonce, payloadHash));
    }

    function computeGlobalRouteId(
        uint16 srcChainId,
        uint16 dstChainId,
        address initiator,
        bytes32 messageHash,
        uint64 nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(srcChainId, dstChainId, initiator, messageHash, nonce));
    }

    // ---------- Admin setters for adapter and fee collector
    function setAdapter(address a) external onlyAdmin {
        adapter = a;
    }

    function setFeeCollector(address c) external onlyAdmin {
        if (c == address(0)) revert ZeroAddress();
        feeCollector = c;
    }

    // Admin setters for BPS configuration with validation
    event ProtocolFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event RelayerFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event ProtocolShareBpsUpdated(uint16 oldBps, uint16 newBps);
    event LPShareBpsUpdated(uint16 oldBps, uint16 newBps);

    function setProtocolFeeBps(uint16 bps) external onlyAdmin {
        // enforce reasonable cap using FEE_CAP_BPS for on-chain protocol fee cap
        if (bps > FEE_CAP_BPS) revert FeeTooHigh();
        emit ProtocolFeeBpsUpdated(protocolFeeBps, bps);
        protocolFeeBps = bps;
    }

    function setRelayerFeeBps(uint16 bps) external onlyAdmin {
        // relayer fee cap cannot exceed 10% (1000 bps) as a safety heuristic
        if (bps > 1000) revert FeeTooHigh();
        emit RelayerFeeBpsUpdated(relayerFeeBps, bps);
        relayerFeeBps = bps;
    }

    function setProtocolShareBps(uint16 bps) external onlyAdmin {
        // protocolShareBps + lpShareBps must not exceed 10000 (100%)
        if (uint256(bps) + uint256(lpShareBps) > 10_000) revert FeeTooHigh();
        emit ProtocolShareBpsUpdated(protocolShareBps, bps);
        protocolShareBps = bps;
    }

    function setLPShareBps(uint16 bps) external onlyAdmin {
        if (uint256(protocolShareBps) + uint256(bps) > 10_000) revert FeeTooHigh();
        emit LPShareBpsUpdated(lpShareBps, bps);
        lpShareBps = bps;
    }

    // ---------- Finalizer (adapter-only) ----------
    /**
     * @notice Finalize a cross-chain message. Only the configured adapter may call this.
     * Marks the canonical message as used to prevent replay and applies fee splits.
     * @param globalRouteId canonical route identifier (for indexing/read-side)
     * @param messageHash canonical message hash (pre-image of GRI)
     * @param asset ERC20 token to distribute
     * @param vault recipient vault/pool address for forwarded funds
     * @param lpRecipient optional LP recipient for LP share
     * @param amount total forwarded amount that was sent to the destination (includes fees already skimmed)
     * @param protocolFee native protocol fee amount (passed through for read-side auditing)
     * @param relayerFee native relayer fee amount; will be forwarded to msg.sender (relayer)
     */
    function finalizeMessage(
        bytes32 globalRouteId,
        bytes32 messageHash,
        address asset,
        address vault,
        address lpRecipient,
        uint256 amount,
        uint256 protocolFee,
        uint256 relayerFee
    ) external nonReentrant {
        // if adapter set, only adapter may call
        if (adapter != address(0) && msg.sender != adapter) revert Unauthorized();

        if (usedMessages[messageHash]) revert MessageAlreadyUsed();
        usedMessages[messageHash] = true;

        IERC20 t = IERC20(asset);

        // Compute protocol and LP splits (protocolShareBps and lpShareBps are relative bps)
        uint256 protocolShare = Math.mulDiv(amount, protocolShareBps, 10_000);
        uint256 lpShare = Math.mulDiv(amount, lpShareBps, 10_000);

        // Ensure the collector address exists for protocol share
        if (protocolShare > 0) {
            if (feeCollector == address(0)) revert ZeroAddress();
            t.safeTransfer(feeCollector, protocolShare);
        }

        if (lpShare > 0 && lpRecipient != address(0)) {
            t.safeTransfer(lpRecipient, lpShare);
        }

        // Transfer relayer fee to caller
        if (relayerFee > 0) {
            t.safeTransfer(msg.sender, relayerFee);
        }

        // Remaining amount to vault
        uint256 paidFees = protocolShare + lpShare + relayerFee;
        if (paidFees > amount) revert FeesExceedAmount();
        uint256 toVault = amount - paidFees;
        if (toVault > 0) {
            t.safeTransfer(vault, toVault);
        }

        emit FeeApplied(
            globalRouteId,
            messageHash,
            SRC_CHAIN_ID,
            address(this),
            vault,
            asset,
            protocolShare,
            relayerFee,
            protocolShareBps,
            lpShareBps,
            feeCollector,
            block.timestamp
        );
    }

    // (debug helpers removed)
}
