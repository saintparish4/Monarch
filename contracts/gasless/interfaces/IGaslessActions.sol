// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; // Will be updated to 0.8.27

import "./IUserOperation.sol";

/**
 * @title IGaslessActions
 * @dev High-level interface for gasless interactions in BaseKit
 * @notice Provides simple methods for executing gasless transactions and managing sponsorship
 */
interface IGaslessActions {
    // Execution types
    enum ExecutionType {
        SINGLE,         // Single transaction
        BATCH,          // Multiple transactions
        DELAYED         // Scheduled execution
    }

    // Execution data structure
    struct ExecutionData {
        address target;     // Target contract
        uint256 value;      // ETH value to send
        bytes data;         // Call data
        uint256 gasLimit;   // Gas limit for this call
    }

    // Sponsorship data structure
    struct SponsorshipData {
        address sponsor;           // Address sponsoring the gas
        uint256 maxGasCost;       // Maximum gas cost sponsor will pay
        uint256 validUntil;       // Timestamp until sponsorship is valid
        bytes sponsorSignature;   // Sponsor's signature approving the sponsorship
    }

    // Events
    event GaslessExecutionSuccess(
        address indexed user,
        address indexed target,
        bytes32 indexed userOpHash,
        uint256 actualGasCost
    );

    event GaslessExecutionFailure(
        address indexed user,
        address indexed target,
        bytes32 indexed userOpHash,
        string reason
    );

    event UserSponsoredForGas(
        address indexed user,
        address indexed sponsor,
        uint256 monthlyLimit
    );

    event MetaTransactionExecuted(
        address indexed user,
        bytes32 indexed txHash,
        bool success
    );

    // Errors
    error GaslessExecutionFailed(string reason);
    error InvalidExecutionData(uint256 index);
    error SponsorshipExpired(uint256 currentTime, uint256 validUntil);
    error InsufficientSponsorship(uint256 required, uint256 available);
    error InvalidSponsorSignature(address sponsor);
    error AccountNotDeployed(address account);

    /**
     * @notice Execute a gasless transaction for a user
     * @param user The user address
     * @param execution The execution data
     * @param signature The user's signature
     * @param sponsorship Optional sponsorship data
     * @return success Whether the execution was successful
     * @return userOpHash The hash of the user operation
     */
    function executeGasless(
        address user,
        ExecutionData calldata execution,
        bytes calldata signature,
        SponsorshipData calldata sponsorship
    ) external returns (bool success, bytes32 userOpHash);

    /**
     * @notice Execute multiple gasless transactions in batch
     * @param user The user address
     * @param executions Array of execution data
     * @param signature The user's signature
     * @param sponsorship Optional sponsorship data
     * @return success Whether all executions were successful
     * @return userOpHash The hash of the user operation
     */
    function executeGaslessBatch(
        address user,
        ExecutionData[] calldata executions,
        bytes calldata signature,
        SponsorshipData calldata sponsorship
    ) external returns (bool success, bytes32 userOpHash);

    /**
     * @notice Execute a meta-transaction with EIP-2771 support
     * @param functionSignature The encoded function call
     * @param sigR Signature R component
     * @param sigS Signature S component
     * @param sigV Signature V component
     * @return success Whether the execution was successful
     */
    function executeMetaTransaction(
        bytes calldata functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) external returns (bool success);

    /**
     * @notice Sponsor a user's gas for a specific period
     * @param user The user address
     * @param monthlyLimit Monthly gas limit in wei
     * @param duration Sponsorship duration in seconds
     */
    function sponsorUserForGas(
        address user,
        uint256 monthlyLimit,
        uint256 duration
    ) external payable;

    /**
     * @notice Create or get a smart account for a user
     * @param user The user address
     * @param salt Unique salt for account creation
     * @return account The smart account address
     * @return isNewAccount Whether this is a newly created account
     */
    function getOrCreateAccount(
        address user,
        uint256 salt
    ) external returns (address account, bool isNewAccount);

    /**
     * @notice Estimate gas cost for a gasless execution
     * @param user The user address
     * @param execution The execution data
     * @return estimatedCost The estimated gas cost in wei
     */
    function estimateGaslessExecution(
        address user,
        ExecutionData calldata execution
    ) external view returns (uint256 estimatedCost);

    /**
     * @notice Check if a user has sufficient gas sponsorship
     * @param user The user address
     * @param estimatedCost The estimated gas cost
     * @return hasSufficientSponsorship Whether user has enough sponsorship
     * @return availableGas Available sponsored gas amount
     */
    function checkSponsorship(
        address user,
        uint256 estimatedCost
    ) external view returns (bool hasSufficientSponsorship, uint256 availableGas);

    /**
     * @notice Get user's smart account address (even if not deployed)
     * @param user The user address
     * @param salt The salt used for account creation
     * @return account The deterministic account address
     */
    function getAccountAddress(
        address user,
        uint256 salt
    ) external view returns (address account);

    /**
     * @notice Check if an account is deployed
     * @param account The account address to check
     * @return deployed Whether the account is deployed
     */
    function isAccountDeployed(address account) external view returns (bool deployed);

    /**
     * @notice Get the nonce for a user's next operation
     * @param user The user address
     * @return nonce The next nonce value
     */
    function getUserNonce(address user) external view returns (uint256 nonce);

    /**
     * @notice Validate a sponsorship signature
     * @param sponsorship The sponsorship data
     * @param userOpHash The user operation hash
     * @return valid Whether the sponsorship signature is valid
     */
    function validateSponsorship(
        SponsorshipData calldata sponsorship,
        bytes32 userOpHash
    ) external view returns (bool valid);

    /**
     * @notice Get the entry point address used by this module
     * @return entryPoint The entry point contract address
     */
    function getEntryPoint() external view returns (address entryPoint);

    /**
     * @notice Get the account factory address
     * @return factory The account factory contract address
     */
    function getAccountFactory() external view returns (address factory);

    /**
     * @notice Get the paymaster address
     * @return paymaster The paymaster contract address
     */
    function getPaymaster() external view returns (address paymaster);
}