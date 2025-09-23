// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IUserOperation.sol";

/**
 * @title IPaymaster
 * @dev Interface for paymasters that sponsor gas fees
 * @notice Defines functionality for sponsoring user operations and managing gas payments
 */
interface IPaymaster {
    // Paymaster modes
    enum PaymasterMode {
        FREE,           // Free transactions for whitelisted users
        SUBSCRIPTION,   // Subscription-based gas sponsorship
        TOKEN_PAYMENT,  // Pay with ERC20 tokens
        DEPOSIT_BASED   // Pre-deposited funds
    }

    // Subscription data structure
    struct Subscription {
        uint256 monthlyLimit;       // Monthly gas limit in wei
        uint256 usedThisMonth;     // Used gas this month
        uint256 lastResetTime;     // Last time monthly usage was reset
        bool isActive;             // Whether subscription is active
    }

    // Events
    event UserOpSponsored(
        address indexed user,
        bytes32 indexed userOpHash,
        uint256 actualGasCost,
        PaymasterMode mode
    );
    
    event SubscriptionCreated(
        address indexed user,
        uint256 monthlyLimit,
        uint256 duration
    );
    
    event SubscriptionUpdated(
        address indexed user,
        uint256 newMonthlyLimit
    );
    
    event DepositAdded(
        address indexed user,
        uint256 amount
    );
    
    event DepositWithdrawn(
        address indexed user,
        uint256 amount
    );

    // Errors
    error PaymasterValidationFailed(string reason);
    error InsufficientDeposit(address user, uint256 required, uint256 available);
    error SubscriptionLimitExceeded(address user, uint256 used, uint256 limit);
    error SubscriptionExpired(address user);
    error UnauthorizedUser(address user);
    error InvalidPaymasterMode(PaymasterMode mode);

    /**
     * @notice Validate a user operation and return context for gas payment
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @param maxCost The maximum cost this paymaster might pay
     * @return context Data to be passed to postOp
     * @return validAfter Timestamp after which this operation is valid (0 for unlimited)
     * @return validUntil Timestamp until which this operation is valid (0 for unlimited)
     */
    function validatePaymasterUserOp(
        IUserOperation.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validAfter, uint256 validUntil);

    /**
     * @notice Called after user operation execution to handle gas payment
     * @param mode The paymaster mode used
     * @param context The context returned from validatePaymasterUserOp
     * @param actualGasCost The actual gas cost of the operation
     */
    function postOp(
        PaymasterMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external;

    /**
     * @notice Create a gas subscription for a user
     * @param user The user address
     * @param monthlyLimit Monthly gas limit in wei
     * @param duration Subscription duration in seconds
     */
    function createSubscription(
        address user,
        uint256 monthlyLimit,
        uint256 duration
    ) external payable;

    /**
     * @notice Update a user's subscription limit
     * @param user The user address
     * @param newMonthlyLimit New monthly gas limit
     */
    function updateSubscription(address user, uint256 newMonthlyLimit) external;

    /**
     * @notice Add a user to the free transaction whitelist
     * @param user The user address
     * @param gasLimit Gas limit for free transactions
     */
    function addToWhitelist(address user, uint256 gasLimit) external;

    /**
     * @notice Remove a user from the free transaction whitelist
     * @param user The user address
     */
    function removeFromWhitelist(address user) external;

    /**
     * @notice Add deposit for a user to pay for gas
     * @param user The user address
     */
    function addDeposit(address user) external payable;

    /**
     * @notice Withdraw deposit for a user
     * @param user The user address
     * @param amount Amount to withdraw
     */
    function withdrawDeposit(address user, uint256 amount) external;

    /**
     * @notice Get user's subscription information
     * @param user The user address
     * @return subscription The subscription data
     */
    function getSubscription(address user) external view returns (Subscription memory subscription);

    /**
     * @notice Get user's deposit balance
     * @param user The user address
     * @return balance The deposit balance
     */
    function getDepositBalance(address user) external view returns (uint256 balance);

    /**
     * @notice Check if user is whitelisted for free transactions
     * @param user The user address
     * @return whitelisted True if user is whitelisted
     * @return gasLimit Gas limit for free transactions
     */
    function isWhitelisted(address user) external view returns (bool whitelisted, uint256 gasLimit);

    /**
     * @notice Calculate the gas cost for a user operation
     * @param userOp The user operation
     * @return gasCost The estimated gas cost
     */
    function calculateGasCost(IUserOperation.UserOperation calldata userOp) 
        external 
        view 
        returns (uint256 gasCost);

    /**
     * @notice Get the paymaster's deposit on the entry point
     * @return balance The paymaster's deposit balance
     */
    function getPaymasterDeposit() external view returns (uint256 balance);

    /**
     * @notice Add deposit to the paymaster's entry point balance
     */
    function addPaymasterDeposit() external payable;

    /**
     * @notice Withdraw from the paymaster's entry point deposit
     * @param amount Amount to withdraw
     */
    function withdrawPaymasterDeposit(uint256 amount) external;
}