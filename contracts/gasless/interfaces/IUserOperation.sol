// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; // Will be updated to 0.8.27

/**
 * @title IUserOperation
 * @dev Interface for EIP-4337 User Operations
 * @notice Defines the structure and validation for gasless transactions
 */

interface IUserOperation {
    /**
     * @dev User Operation structure based on EIP-4337
     */

    struct UserOperation {
        address sender; // The account making the operation
        uint256 nonce; // Anti-replay parameter
        bytes initCode; // Account factory data (if account not yet deployed)
        bytes callData; // The data to pass to the sender during the main execution call
        uint256 callGasLimit; // Gas limit for the main execution call
        uint256 verificationGasLimit; // Gas limit for the verification step
        uint256 preVerificationGas; // Gas to pay the bundler
        uint256 maxFeePerGas; // Maximum fee per gas
        uint256 maxPriorityFeePerGas; // Maximum priority fee per gas
        bytes paymasterAndData; // Paymaster address and data (if using paymaster)
        bytes signature; // Data passed to the account for signature verification
    }

    /**
     * @dev Packed User Operation for efficient processing
     */
    struct PackedUserOperation {
        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        bytes32 accountGasLimits; // Packed gas limits
        uint256 preVerificationGas;
        bytes32 gasFees; // Packed gas fees
        bytes paymasterAndData;
        bytes signature;
    }

    // Events
    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed 
    );

    event AccountDeployed(
        bytes32 indexed userOpHash,
        address indexed sender,
        address factory,
        address paymaster 
    );

    // Errors
    error InvalidUserOperation(string reason);
    error InvalidSignature(address account, bytes32 userOpHash);
    error InsufficientGas(uint256 required, uint256 available);
    error PaymasterValidationFailed(address paymaster);

    /**
     * @notice Pack a UserOperation into PackedUserOperation format
     * @param userOp The user operation to pack
     * @return packed The packed user operation 
     */
    function packUserOperation(UserOperation calldata userOp)
        external
        pure
        returns (PackedUserOperation memory packed); 

    /**
     * @notice Unpack a PackedUserOperation into UserOperation format
     * @param packed The packed user operation to unpack
     * @return userOp The unpacked user operation 
     */
    function unpackUserOperation(PackedUserOperation calldata packed)
        external
        pure
        returns (UserOperation memory userOp);

    /**
     * @notice Calculate the hash of a user operation
     * @param userOp The user operation
     * @param entryPoint The entry point address
     * @param chainId The chain ID
     * @return userOpHash The hash of the user operation 
     */
    function getUserOperationHash(
        UserOperation calldata userOp,
        address entryPoint,
        uint256 chainId
    ) external pure returns (bytes32 userOpHash);

    /**
     * @notice Validate user operation gas limits
     * @param userOp The user operation to validate
     * @return valid True if gas limits are valid 
     */
    function validateGasLimits(UserOperation calldata userOp)
        external
        pure
        returns (bool valid); 
}
