// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title BasePayments
 * @dev Core library for recurring payments and subscription management
 * @notice Optimized for Base L2 with gas-efficient operations
 */
library BasePayments {
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
    // CONSTANTS
    // =============================================================================

    uint256 public constant MIN_PERIOD = 1 hours;
    uint256 public constant MAX_PERIOD = 365 days;
    uint256 public constant GRACE_PERIOD = 3 days;

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    /**
     * @dev Generate plan ID from merchant and name
     */
    function generatePlanId(address merchant, string memory name) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(merchant, name, block.timestamp));
    }

    /**
     * @dev Generate subscription ID
     */
    function generateSubscriptionId(address subscriber, bytes32 planId) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(subscriber, planId, block.timestamp));
    }

    /**
     * @dev Validate payment plan parameters
     */
    function validatePlan(uint256 amount, uint256 period, uint256 maxPayments) internal pure {
        if (amount == 0) revert InvalidAmount();
        if (period < MIN_PERIOD || period > MAX_PERIOD) revert InvalidPeriod();
        // maxPayments can be 0 for unlimited
    }

    /**
     * @dev Check if payment is due for subscription
     */
    function isPaymentDue(Subscription memory sub) internal view returns (bool) {
        return sub.active && block.timestamp >= sub.nextPayment;
    }

    /**
     * @dev Check if subscription has reached max payments
     */
    function hasReachedMaxPayments(Subscription memory sub) internal pure returns (bool) {
        return sub.maxPayments > 0 && sub.paymentCount >= sub.maxPayments;
    }

    /**
     * @dev Calculate next payment timestamp
     */
    function calculateNextPayment(uint256 currentTime, uint256 period) internal pure returns (uint256) {
        return currentTime + period;
    }
}
