// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Security.sol";
import "./SignatureSecurity.sol";
import "./Validation.sol";
import "./Constants.sol";
import "../gasless/interfaces/IUserOperation.sol";

/**
 * @title BaseAccount
 * @dev Core account functionality library for smart accounts
 * @notice Provides common patterns for account management and execution
 */
library BaseAccount {
    using Security for Security.SecurityState;
    using SignatureSecurity for SignatureSecurity.SignatureData;

    // Account state structure
    struct AccountState {
        Security.SecurityState security;
        address entryPoint;
        uint256 nonce;
        mapping(bytes32 => bool) executedHashes;
        bool isInitialized;
    }

    // Execution result structure
    struct ExecutionResult {
        bool success;
        bytes returnData;
        uint256 gasUsed;
    }

    // Events
    event AccountInitialized(address indexed account, address indexed owner, address entryPoint);
    event ExecutionSuccess(address indexed target, uint256 value, bytes4 indexed selector);
    event ExecutionFailure(address indexed target, uint256 value, bytes4 indexed selector, string reason);
    event NonceIncremented(uint256 indexed oldNonce, uint256 indexed newNonce);

    // Errors
    error AccountAlreadyInitialized();
    error AccountNotInitialized();
    error InvalidEntryPoint(address entryPoint);
    error ExecutionFailed(address target, string reason);
    error InsufficientBalance(uint256 required, uint256 available);
    error HashAlreadyExecuted(bytes32 hash);
    error InvalidUserOperation(string reason);

    /**
     * @notice Initialize the account state
     * @param state The account state storage
     * @param owner The initial owner address
     * @param entryPoint The entry point address
     */
    function initialize(
        AccountState storage state,
        address owner,
        address entryPoint
    ) internal {
        if (state.isInitialized) revert AccountAlreadyInitialized();
        
        Validation.validateAddress(owner);
        Validation.validateContract(entryPoint);

        state.security.initialize(owner);
        state.entryPoint = entryPoint;
        state.nonce = 1;
        state.isInitialized = true;

        emit AccountInitialized(address(this), owner, entryPoint);
    }

    /**
     * @notice Validate a user operation
     * @param state The account state storage
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @return validationData Validation result
     */
    function validateUserOperation(
        AccountState storage state,
        IUserOperation.UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal returns (uint256 validationData) {
        requireInitialized(state);
        
        // Validate nonce
        if (userOp.nonce != state.nonce) {
            return Constants.SIG_VALIDATION_FAILED;
        }

        // Create signature hash
        bytes32 hash = SignatureSecurity.createUserOperationHash(
            userOpHash,
            state.entryPoint,
            block.chainid
        );

        // Validate signature
        try this._validateSignature(hash, userOp.signature, state.security.owner) returns (bool valid) {
            if (!valid) {
                return Constants.SIG_VALIDATION_FAILED;
            }
        } catch {
            return Constants.SIG_VALIDATION_FAILED;
        }

        // Increment nonce
        uint256 oldNonce = state.nonce;
        state.nonce++;
        emit NonceIncremented(oldNonce, state.nonce);

        return Constants.SIG_VALIDATION_SUCCESS;
    }

    /**
     * @notice Execute a single transaction
     * @param target The target contract address
     * @param value The amount of ETH to send
     * @param data The transaction data
     * @return result The execution result
     */
    function executeTransaction(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (ExecutionResult memory result) {
        Validation.validateAddress(target);

        // Check balance if sending ETH
        if (value > 0) {
            if (address(this).balance < value) {
                revert InsufficientBalance(value, address(this).balance);
            }
        }

        // Extract function selector for events
        bytes4 selector = bytes4(0);
        if (data.length >= 4) {
            selector = bytes4(data[0]) | (bytes4(data[1]) >> 8) | (bytes4(data[2]) >> 16) | (bytes4(data[3]) >> 24);
        }

        uint256 gasStart = gasleft();

        // Execute the call
        (result.success, result.returnData) = target.call{value: value}(data);
        
        result.gasUsed = gasStart - gasleft();

        if (result.success) {
            emit ExecutionSuccess(target, value, selector);
        } else {
            string memory reason = _getRevertReason(result.returnData);
            emit ExecutionFailure(target, value, selector, reason);
        }
    }

    /**
     * @notice Execute multiple transactions in batch
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param data Array of transaction data
     * @return results Array of execution results
     */
    function executeBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory data
    ) internal returns (ExecutionResult[] memory results) {
        Validation.validateArrayLengths(targets, values);
        Validation.validateArrayLengths(data, values);
        Validation.validateExecutionTargets(targets);

        results = new ExecutionResult[](targets.length);

        for (uint256 i = 0; i < targets.length; i++) {
            results[i] = executeTransaction(targets[i], values[i], data[i]);
        }
    }

    /**
     * @notice Get the current nonce
     * @param state The account state storage
     * @return nonce The current nonce value
     */
    function getNonce(AccountState storage state) internal view returns (uint256 nonce) {
        return state.nonce;
    }

    /**
     * @notice Get the entry point address
     * @param state The account state storage
     * @return entryPoint The entry point address
     */
    function getEntryPoint(AccountState storage state) internal view returns (address entryPoint) {
        return state.entryPoint;
    }

    /**
     * @notice Check if account is initialized
     * @param state The account state storage
     * @return initialized True if account is initialized
     */
    function isInitialized(AccountState storage state) internal view returns (bool initialized) {
        return state.isInitialized;
    }

    /**
     * @notice Require account to be initialized
     * @param state The account state storage
     */
    function requireInitialized(AccountState storage state) internal view {
        if (!state.isInitialized) revert AccountNotInitialized();
    }

    /**
     * @notice Change the account owner
     * @param state The account state storage
     * @param caller The caller address
     * @param newOwner The new owner address
     */
    function changeOwner(
        AccountState storage state,
        address caller,
        address newOwner
    ) internal {
        requireInitialized(state);
        state.security.transferOwnership(caller, newOwner);
    }

    /**
     * @notice Add an admin to the account
     * @param state The account state storage
     * @param caller The caller address
     * @param admin The admin address to add
     */
    function addAdmin(
        AccountState storage state,
        address caller,
        address admin
    ) internal {
        requireInitialized(state);
        state.security.addAdmin(caller, admin);
    }

    /**
     * @notice Remove an admin from the account
     * @param state The account state storage
     * @param caller The caller address
     * @param admin The admin address to remove
     */
    function removeAdmin(
        AccountState storage state,
        address caller,
        address admin
    ) internal {
        requireInitialized(state);
        state.security.removeAdmin(caller, admin);
    }

    /**
     * @notice Withdraw ETH from the account
     * @param recipient The address to receive ETH
     * @param amount The amount to withdraw
     */
    function withdraw(address payable recipient, uint256 amount) internal {
        Validation.validateAddress(recipient);
        
        if (address(this).balance < amount) {
            revert InsufficientBalance(amount, address(this).balance);
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert ExecutionFailed(recipient, "ETH transfer failed");
        }
    }

    /**
     * @notice Validate signature (external function for try/catch)
     * @param hash The hash to validate
     * @param signature The signature to check
     * @param expectedSigner The expected signer
     * @return valid True if signature is valid
     */
    function _validateSignature(
        bytes32 hash,
        bytes memory signature,
        address expectedSigner
    ) external pure returns (bool valid) {
        return SignatureSecurity.validateECDSASignature(hash, signature, expectedSigner);
    }

    /**
     * @notice Extract revert reason from return data
     * @param returnData The return data from a failed call
     * @return reason The revert reason string
     */
    function _getRevertReason(bytes memory returnData) private pure returns (string memory reason) {
        if (returnData.length < 68) {
            return "Transaction reverted silently";
        }

        assembly {
            returnData := add(returnData, 0x04)
        }

        return abi.decode(returnData, (string));
    }

    /**
     * @notice Check if caller is authorized (owner or admin)
     * @param state The account state storage
     * @param caller The caller address
     * @return authorized True if caller is authorized
     */
    function isAuthorized(
        AccountState storage state,
        address caller
    ) internal view returns (bool authorized) {
        return state.security.isAdmin(caller);
    }

    /**
     * @notice Require caller to be authorized
     * @param state The account state storage
     * @param caller The caller address
     */
    function requireAuthorized(AccountState storage state, address caller) internal view {
        state.security.requireAdmin(caller);
    }

    /**
     * @notice Mark a hash as executed to prevent replay
     * @param state The account state storage
     * @param hash The hash to mark as executed
     */
    function markHashExecuted(AccountState storage state, bytes32 hash) internal {
        if (state.executedHashes[hash]) {
            revert HashAlreadyExecuted(hash);
        }
        state.executedHashes[hash] = true;
    }

    /**
     * @notice Check if a hash has been executed
     * @param state The account state storage
     * @param hash The hash to check
     * @return executed True if hash has been executed
     */
    function isHashExecuted(
        AccountState storage state,
        bytes32 hash
    ) internal view returns (bool executed) {
        return state.executedHashes[hash];
    }
}