// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title BaseAccount
 * @dev Core library for account abstraction on Base
 * Provides utilities for smart accounts, user operations, and gasless transactions
 */
library BaseAccount {
    using ECDSA for bytes32;

    // ============== STRUCTS ==============

    struct UserOperation {
        address sender; // The account making the operation
        uint256 nonce; // Anti-replay parameter
        bytes initCode; // Account creation code (if new account)
        bytes callData; // The call data to execute
        uint256 callGasLimit; // Gas limit for the main execution call
        uint256 verificationGasLimit; // Gas limit for the verification step
        uint256 preVerificationGas; // Gas for pre-verification logic
        uint256 maxFeePerGas; // Maximum fee per gas unit
        uint256 maxPriorityFeePerGas; // Maximum priority fee per gas
        bytes paymasterAndData; // Paymaster address and data
        bytes signature; // Signature for verification
    }

    struct GasPolicy {
        address paymentToken; // Token for gas payments (address(0) for ETH)
        uint256 maxGasPrice; // Maximum gas price to pay
        uint256 dailyGasLimit; // Daily gas spending limit
        uint256 perTxGasLimit; // Per-transaction gas limit
        uint256 dailySpent; // Amount spent today
        uint256 lastResetTime; // Last time daily counter was reset
        bool enabled; // Whether gas policy is active
    }

    struct AppPermission {
        bool authorized; // Whether app is authorized
        uint256 gasAllowance; // Gas allowance for this app
        uint256 dailySpentByApp; // Gas spent by app today
        uint256 lastAppResetTime; // Last reset for app-specific limits
        bytes4[] allowedMethods; // Specific methods app can call
        bool requiresConfirmation; // Whether transactions need user confirmation
    }

    struct AccountState {
        address owner; // Account owner
        uint256 nonce; // Current nonce
        bool locked; // Emergency lock state
        uint256 lockUntil; // Lock expiration timestamp
        address recovery; // Recovery address
        uint256 recoverDelay; // Recovery action delay
    }

    // ============== EVENTS ==============

    event AccountCreated(address indexed account, address indexed owner);
    event TransactionExecuted(
        address indexed account,
        bytes32 indexed userOpHash,
        bool indexed success,
        uint256 gasUsed
    );
    event AppAuthorized(address indexed account, address indexed app, bool authorized);
    event GasPolicyUpdated(address indexed account, address token, uint256 dailyLimit);
    event PaymasterChanged(address indexed account, address indexed paymaster);
    event AccountLocked(address indexed account, uint256 lockUntil);
    event RecoveryInitiated(address indexed account, address indexed newOwner);

    // ============== ERRORS ==============

    error InvalidSignature();
    error NonceAlreadyUsed();
    error AppNotAuthorized();
    error GasLimitExceeded();
    error DailyLimitExceeded();
    error AccountLocked();
    error InvalidUserOperation();
    error InsufficientGasAllowance();
    error MethodNotAllowed();
    error InvalidRecovery();
    error RecoveryDelayNotMet();

    // ============== CONSTANTS ==============

    bytes32 public constant USER_OPERATION_TYPEHASH =
        keccak256(
            "UserOperation(address sender, uint256 nonce, bytes initCode, bytes callData, uint256 callGasLimit, uint256 verificationGasLimit, uint256 preVerificationGas, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas, bytes paymasterAndData)"
        );

    uint256 public constant MIN_RECOVERY_DELAY = 1 days;
    uint256 public constant MAX_RECOVERY_DELAY = 30 days;
    uint256 public constant MAX_LOCK_DURATION = 7 days;

    // ============== VALIDATION FUNCTIONS ==============

    /**
     * @dev Validate user operation parameters
     */
    function validateUserOperation(UserOperation calldata userOp) internal pure returns (bool) {
        if (userOp.sender == address(0)) return false;
        if (userOp.callGasLimit == 0) return false;
        if (userOp.verificationGasLimit == 0) return false;
        if (userOp.maxFeePerGas == 0) return false;
        return true;
    }

    /**
     * @dev Validate app permission for method call
     */
    function validateAppPermission(
        AppPermission storage permission,
        bytes4 methodSelector,
        uint256 gasNeeded
    ) internal view returns (bool) {
        if (!permission.authorized) return false;

        // Check gas allowance
        if (permission.gasAllowance < gasNeeded) return false;

        // Check method permissions (if specific methods are set)
        if (permission.allowedMethods.length > 0) {
            bool methodAllowed = false;
            for (uint256 i = 0; i < permission.allowedMethods.length; i++) {
                if (permission.allowedMethods[i] == methodSelector) {
                    methodAllowed = true;
                    break;
                }
            }
            if (!methodAllowed) return false;
        }

        return true;
    }

    /**
     * @dev Update gas policy spending
     */
    function updateGasSpending(GasPolicy storage policy, uint256 gasUsed, uint256 gasPrice) internal {
        if (!policy.enabled) return;

        // Reset daily counter if needed
        if (block.timestamp >= policy.lastResetTime + 1 days) {
            policy.dailySpent = 0;
            policy.lastResetTime = block.timestamp;
        }

        uint256 gasCost = gasUsed * gasPrice;
        policy.dailySpent += gasCost;
    }

    /**
     * @dev Update app gas spending
     */
    function updateAppGasSpending(AppPermission storage permission, uint256 gasUsed, uint256 gasPrice) internal {
        // Reset app daily counter if needed
        if (block.timestamp >= permission.lastAppResetTime + 1 days) {
            permission.dailySpentByApp = 0;
            permission.lastAppResetTime = block.timestamp;
        }

        uint256 gasCost = gasUsed * gasPrice;
        permission.dailySpentByApp += gasCost;

        // Deduct from app's gas allowance
        if (permission.gasAllowance >= gasCost) {
            permission.gasAllowance -= gasCost;
        }
    }

    /**
     * @dev Check if gas policy allows transaction
     */
    function checkGasPolicy(GasPolicy storage policy, uint256 gasLimit, uint256 gasPrice) internal view returns (bool) {
        if (!policy.enabled) return true;

        uint256 estimatedCost = gasLimit * gasPrice;

        // Check per-transaction limit
        if (estimatedCost > policy.perTxGasLimit) return false;

        // Check gas price limit
        if (gasPrice > policy.maxGasPrice) return false;

        // Check daily limit
        uint256 dailySpent = policy.dailySpent;
        if (block.timestamp >= policy.lastResetTime + 1 days) {
            dailySpent = 0; // Would be reset
        }

        if (dailySpent + estimatedCost > policy.dailyGasLimit) return false;

        return true;
    }

    /**
     * @dev Generate user operation hash
     */
    function getUserOpHash(UserOperation calldata userOp, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                USER_OPERATION_TYPEHASH,
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                keccak256(userOp.paymasterAndData)
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /**
     * @dev Pack user operation for gas estimation
     */
    function packUserOp(UserOperation calldata userOp) internal pure returns (bytes memory) {
        return
            abi.encode(
                userOp.sender,
                userOp.nonce,
                userOp.initCode,
                userOp.callData,
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                userOp.paymasterAndData,
                userOp.signature
            );
    }

    /**
     * @dev Calculate required prefund for user operation
     */
    function calculatePrefund(UserOperation calldata userOp) internal pure returns (uint256) {
        uint256 requiredGas = userOp.callGasLimit + userOp.verificationGasLimit + userOp.preVerificationGas;
        return requiredGas * userOp.maxFeePerGas;
    }

    /**
     * @dev Validate recovery parameters
     */
    function validateRecovery(
        uint256 recoveryDelay,
        address newOwner,
        address currentOwner
    ) internal pure returns (bool) {
        if (newOwner == address(0)) return false;
        if (newOwner == currentOwner) return false;
        if (recoveryDelay < MIN_RECOVERY_DELAY || recoveryDelay > MAX_RECOVERY_DELAY) return false;
        return true;
    }

    /**
     * @dev Check if account should be locked
     */
    function shouldBeLocked(AccountState storage state) internal view returns (bool) {
        return state.locked && block.timestamp < state.lockUntil;
    }

    /**
     * @dev Extract method selector from call data
     */
    function getMethodSelector(bytes calldata data) internal pure returns (bytes4) {
        if (data.length < 4) return bytes4(0);
        return bytes4(data[:4]);
    }
}
