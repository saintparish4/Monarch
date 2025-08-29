// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IBasePayments
 * @dev Interface for BasePayments library and manager contracts
 */
interface IBasePayments {
    // =============================================================================
    // STRUCTS
    // =============================================================================

    struct Subscription {
        address subscriber; // Who's paying
        address merchant; // Who's receiving
        address token; // Payment token (address(0) for ETH)
        uint256 amount; // Payment amount per period
        uint256 period; // Payment period in seconds
        uint256 nextPayment; // When next payment is due
        uint256 maxPayments; // Maximum number of payments (0 = unlimited)
        uint256 paymentCount; // Number of payments made
        bool active; // Whether subscription is active
    }

    struct PaymentPlan {
        address merchant; // Plan creator
        string name; // Plan name
        address token; // Payment token
        uint256 amount; // Amount per period
        uint256 period; // Period duration in seconds
        uint256 maxPayments; // Max payments (0 = unlimited)
        bool active; // Whether plan accepts new subscribers
        uint256 subscriberCount; // Number of active subscribers
    }

    // =============================================================================
    // EVENTS
    // =============================================================================

    event PaymentPlanCreated(
        bytes32 indexed planId,
        address indexed merchant,
        string name,
        uint256 amount,
        uint256 period
    );

    event SubscriptionCreated(
        bytes32 indexed subId,
        address indexed subscriber,
        address indexed merchant,
        bytes32 planId
    );

    event PaymentProcessed(bytes32 indexed subId, uint256 amount, uint256 paymentNumber);

    event SubscriptionCanceled(bytes32 indexed subId, address indexed canceler);

    event PaymentFailed(bytes32 indexed subId, string reason);

    // =============================================================================
    // ERRORS
    // =============================================================================

    error InvalidPeriod();
    error InvalidAmount();
    error InvalidPlan();
    error SubscriptionNotFound();
    error PaymentNotDue();
    error InsufficientAllowance();
    error InsufficientBalance();
    error Unauthorized();
    error SubscriptionInactive();
    error PlanNotFound();
    error MaxPaymentsReached();

    // =============================================================================
    // PLAN MANAGEMENT FUNCTIONS
    // =============================================================================

    /**
     * @dev Create a new payment plan
     */
    function createPaymentPlan(
        string calldata name,
        address token,
        uint256 amount,
        uint256 period,
        uint256 maxPayments
    ) external returns (bytes32 planId);

    /**
     * @dev Toggle payment plan active status
     */
    function togglePlan(bytes32 planId) external;

    /**
     * @dev Get payment plan details
     */
    function getPaymentPlan(bytes32 planId) external view returns (PaymentPlan memory);

    // =============================================================================
    // SUBSCRIPTION MANAGEMENT FUNCTIONS
    // =============================================================================

    /**
     * @dev Subscribe to a payment plan
     */
    function subscribe(bytes32 planId) external payable returns (bytes32 subId);

    /**
     * @dev Process payment for a subscription
     */
    function processPayment(bytes32 subId) external;

    /**
     * @dev Cancel a subscription
     */
    function cancelSubscription(bytes32 subId) external;

    /**
     * @dev Batch process multiple payments
     */
    function batchProcessPayments(bytes32[] calldata subIds) external;

    /**
     * @dev Get subscription details
     */
    function getSubscription(bytes32 subId) external view returns (Subscription memory);

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Check if payment is due
     */
    function isPaymentDue(bytes32 subId) external view returns (bool);

    /**
     * @dev Get user subscriptions
     */
    function getUserSubscriptions(address user) external view returns (bytes32[] memory);

    /**
     * @dev Get merchant plans
     */
    function getMerchantPlans(address merchant) external view returns (bytes32[] memory);

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /**
     * @dev Update platform fee
     */
    function updatePlatformFee(uint256 newFee) external;

    /**
     * @dev Update fee recipient
     */
    function updateFeeRecipient(address newRecipient) external;

    /**
     * @dev Emergency withdrawal
     */
    function emergencyWithdraw(address token, uint256 amount) external;

    // =============================================================================
    // GETTER FUNCTIONS
    // =============================================================================

    /**
     * @dev Get platform fee
     */
    function platformFee() external view returns (uint256);

    /**
     * @dev Get fee recipient
     */
    function feeRecipient() external view returns (address);
}
