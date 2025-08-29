// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPaymentPlan
 * @dev Interface specifically for payment plan management
 * @notice Focused interface for applications that only need plan functionality
 */
interface IPaymentPlan {
    // =============================================================================
    // STRUCTS
    // =============================================================================

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

    struct PlanInfo {
        bytes32 planId; // Plan identifier
        string name; // Plan name
        address merchant; // Plan creator
        address token; // Payment token
        uint256 amount; // Payment amount
        uint256 period; // Payment period
        uint256 maxPayments; // Maximum payments
        bool active; // Plan status
        uint256 subscriberCount; // Current subscribers
        uint256 createdAt; // Creation timestamp
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

    event PaymentPlanUpdated(bytes32 indexed planId, address indexed merchant, bool active);

    event PaymentPlanDeleted(bytes32 indexed planId, address indexed merchant);

    // =============================================================================
    // PLAN MANAGEMENT FUNCTIONS
    // =============================================================================

    /**
     * @dev Create a new payment plan
     * @param name Plan name
     * @param token Payment token address
     * @param amount Payment amount per period
     * @param period Payment period in seconds
     * @param maxPayments Maximum number of payments (0 for unlimited)
     * @return planId Generated plan identifier
     */
    function createPaymentPlan(
        string calldata name,
        address token,
        uint256 amount,
        uint256 period,
        uint256 maxPayments
    ) external returns (bytes32 planId);

    /**
     * @dev Update payment plan status
     * @param planId Plan identifier
     * @param active New status
     */
    function updatePlanStatus(bytes32 planId, bool active) external;

    /**
     * @dev Delete a payment plan (only if no active subscriptions)
     * @param planId Plan identifier
     */
    function deletePlan(bytes32 planId) external;

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get payment plan details
     * @param planId Plan identifier
     * @return plan Payment plan struct
     */
    function getPaymentPlan(bytes32 planId) external view returns (PaymentPlan memory plan);

    /**
     * @dev Get detailed plan information
     * @param planId Plan identifier
     * @return info Detailed plan information
     */
    function getPlanInfo(bytes32 planId) external view returns (PlanInfo memory info);

    /**
     * @dev Get all plans created by a merchant
     * @param merchant Merchant address
     * @return planIds Array of plan identifiers
     */
    function getMerchantPlans(address merchant) external view returns (bytes32[] memory planIds);

    /**
     * @dev Get active plans created by a merchant
     * @param merchant Merchant address
     * @return planIds Array of active plan identifiers
     */
    function getMerchantActivePlans(address merchant) external view returns (bytes32[] memory planIds);

    /**
     * @dev Check if a plan exists and is active
     * @param planId Plan identifier
     * @return exists Whether plan exists
     * @return active Whether plan is active
     */
    function isPlanActive(bytes32 planId) external view returns (bool exists, bool active);

    /**
     * @dev Get plan subscriber count
     * @param planId Plan identifier
     * @return count Number of active subscribers
     */
    function getPlanSubscriberCount(bytes32 planId) external view returns (uint256 count);

    /**
     * @dev Get plan creation timestamp
     * @param planId Plan identifier
     * @return timestamp Creation timestamp
     */
    function getPlanCreationTime(bytes32 planId) external view returns (uint256 timestamp);

    /**
     * @dev Calculate plan revenue potential
     * @param planId Plan identifier
     * @return totalRevenue Total potential revenue (amount * maxPayments * subscribers)
     * @return monthlyRevenue Estimated monthly revenue
     */
    function calculatePlanRevenue(bytes32 planId) external view returns (uint256 totalRevenue, uint256 monthlyRevenue);

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    /**
     * @dev Validate plan parameters
     * @param amount Payment amount
     * @param period Payment period
     * @param maxPayments Maximum payments
     * @return valid Whether parameters are valid
     * @return errorMessage Error message if invalid
     */
    function validatePlanParameters(
        uint256 amount,
        uint256 period,
        uint256 maxPayments
    ) external pure returns (bool valid, string memory errorMessage);

    /**
     * @dev Generate plan ID from parameters
     * @param merchant Merchant address
     * @param name Plan name
     * @return planId Generated plan identifier
     */
    function generatePlanId(address merchant, string calldata name) external view returns (bytes32 planId);

    /**
     * @dev Check if merchant owns plan
     * @param planId Plan identifier
     * @param merchant Merchant address
     * @return owns Whether merchant owns the plan
     */
    function doesMerchantOwnPlan(bytes32 planId, address merchant) external view returns (bool owns);
}
