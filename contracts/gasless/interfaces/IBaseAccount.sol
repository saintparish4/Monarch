// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; // Will be updated to 0.8.27

import "./IUserOperation.sol";

/**
 * @title IBaseAccount
 * @dev Interface for smart accounts in the BaseKit ecosystem
 * @notice Defines core account functionality including validation and execution
 */
interface IBaseAccount {
    // Events
    event AccountInitialized(address indexed account, address indexed owner, uint256 salt);
    event OwnerChanged(address indexed account, address indexed oldOwner, address indexed newOwner);
    event ExecutionSuccess(address indexed target, uint256 value, bytes data);
    event ExecutionFailure(address indexed target, uint256 value, bytes data, string reason);

    // Errors
    error AccountNotInitialized();
    error AccountAlreadyInitialized();
    error InvalidOwner(address owner);
    error InvalidSignature(bytes32 hash, bytes signature);
    error ExecutionFailed(address target, bytes data);
    error InsufficientBalance(uint256 required, uint256 available);

    /**
     * @notice Initialize the account with an owner
     * @param owner The initial owner of the account
     * @param salt A unique salt for account creation
     */
    function initialize(address owner, uint256 salt) external;

    /**
     * @notice Validate a user operation signature
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @return validationData Validation result (0 = success, 1 = signature failure, other = time range)
     */
    function validateUserOp(
        IUserOperation.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);

    /**
     * @notice Execute a transaction from the account
     * @param target The target contract address
     * @param value The amount of ETH to send
     * @param data The transaction data
     * @return success Whether the execution was successful
     * @return result The return data from the execution
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external returns (bool success, bytes memory result);

    /**
     * @notice Execute multiple transactions in batch
     * @param targets Array of target contract addresses
     * @param values Array of ETH amounts to send
     * @param data Array of transaction data
     * @return successes Array of execution results
     * @return results Array of return data
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external returns (bool[] memory successes, bytes[] memory results);

    /**
     * @notice Get the current owner of the account
     * @return owner The address of the current owner
     */
    function getOwner() external view returns (address owner);

    /**
     * @notice Get the current nonce of the account
     * @return nonce The current nonce value
     */
    function getNonce() external view returns (uint256 nonce);

    /**
     * @notice Check if the account is initialized
     * @return initialized True if the account has been initialized
     */
    function isInitialized() external view returns (bool initialized);

    /**
     * @notice Change the owner of the account
     * @param newOwner The address of the new owner
     */
    function changeOwner(address newOwner) external;

    /**
     * @notice Validate a signature for a given hash
     * @param hash The hash to validate
     * @param signature The signature to check
     * @return valid True if the signature is valid
     */
    function isValidSignature(bytes32 hash, bytes memory signature) 
        external 
        view 
        returns (bool valid);

    /**
     * @notice Get the entry point this account is compatible with
     * @return entryPoint The entry point address
     */
    function entryPoint() external view returns (address entryPoint);

    /**
     * @notice Withdraw ETH from the account
     * @param recipient The address to receive the ETH
     * @param amount The amount to withdraw
     */
    function withdraw(address payable recipient, uint256 amount) external;

    /**
     * @notice Deposit ETH to pay for gas
     */
    function addDeposit() external payable;

    /**
     * @notice Get the deposit balance for gas payments
     * @return balance The current deposit balance
     */
    function getDeposit() external view returns (uint256 balance);
}