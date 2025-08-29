// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libs/BasePayments.sol";

/**
 * @title BasePaymentsManager
 * @dev Main contract for managing subscriptions and recurring payments
 * @notice Gas-optimized for Base L2 with efficient batch processing
 * @author BlueSky Labs Contracts Team
 */
contract BasePaymentsManager is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using BasePayments for *;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    mapping(bytes32 => BasePayments.PaymentPlan) public paymentPlans;
    mapping(bytes32 => BasePayments.Subscription) public subscriptions;
    mapping(address => bytes32[]) public userSubscriptions;
    mapping(address => bytes32[]) public merchantPlans;

    uint256 public platformFee = 250; // 2.5% in basis points
    address public feeRecipient;

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    constructor(address _feeRecipient) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    // =============================================================================
    // PLAN MANAGEMENT
    // =============================================================================

    /**
     * @dev Create a new payment plan
     * @param name Plan name
     * @param token Payment token address (address(0) for ETH)
     * @param amount Payment amount per period
     * @param period Payment period in seconds
     * @param maxPayments Max number of payments (0 = unlimited)
     * @param planId Generated plan ID
     */
    function createPaymentPlan(
        string calldata name,
        address token,
        uint256 amount,
        uint256 period,
        uint256 maxPayments
    ) external returns (bytes32 planId) {
        BasePayments.validatePlan(amount, period, maxPayments);

        planId = BasePayments.generatePlanId(msg.sender, name);
        require(paymentPlans[planId].merchant == address(0), "Plan already exists");

        paymentPlans[planId] = BasePayments.PaymentPlan({
            merchant: msg.sender,
            name: name,
            token: token,
            amount: amount,
            period: period,
            maxPayments: maxPayments,
            active: true,
            subscriberCount: 0
        });

        merchantPlans[msg.sender].push(planId);

        emit BasePayments.PaymentPlanCreated(planId, msg.sender, name, amount, period);
    }

    /**
     * @dev Toggle payment plan active status
     * @param planId Plan to toggle
     */
    function togglePlan(bytes32 planId) external {
        BasePayments.PaymentPlan storage plan = paymentPlans[planId];
        require(plan.merchant == msg.sender, "Not plan owner");

        plan.active = !plan.active;
    }

    // =============================================================================
    // SUBSCRIPTION MANAGEMENT
    // =============================================================================

    /**
     * @dev Subscribe to a payment plan
     * @param planId Plan to subscribe to
     * @return subId Generated subscription ID
     */
    function subscribe(bytes32 planId) external payable nonReentrant returns (bytes32 subId) {
        BasePayments.PaymentPlan storage plan = paymentPlans[planId];
        require(plan.active, "Plan is not active");
        require(plan.merchant != address(0), "Plan not found");

        subId = BasePayments.generateSubscriptionId(msg.sender, planId);
        require(subscriptions[subId].subscriber == address(0), "Already subscribed");

        // Process first payment
        _processInitialPayment(plan);

        // Create Subscription
        subscriptions[subId] = BasePayments.Subscription({
            subscriber: msg.sender,
            merchant: plan.merchant,
            token: plan.token,
            amount: plan.amount,
            period: plan.period,
            nextPayment: BasePayments.calculateNextPayment(block.timestamp, plan.period),
            maxPayments: plan.maxPayments,
            paymentCount: 1,
            active: true
        });

        userSubscriptions[msg.sender].push(subId);
        plan.subscriberCount++;

        emit BasePayments.SubscriptionCreated(subId, msg.sender, plan.merchant, planId);
        emit BasePayments.PaymentProcessed(subId, plan.amount, 1);

        /**
         * @dev Process payment for subscription
         * @param subId Subscription ID
         */
        function processPayment(bytes32 subId) external nonReentrant {
            BasePayments.Subscription storage sub = subscriptions[subId];
            require(sub.active, "Subscription inactive");
            require(BasePayments.isPaymentDue(sub), "Payment not due");

            // Check max payments
            if (BasePayments.hasReachedMaxPayments(sub)) {
                sub.active = false;
                return; 
            }

            // Calculate fees
            uint256 feeAmount = (sub.amount * platformFee) / 10000;
            uint256 merchantAmount = sub.amount - feeAmount;

            // Execute payment
            if (sub.token == address(0)) {
                _processETHPayment(sub.subscriber, sub.merchant, sub.amount, feeAmount, merchantAmount);
            } else {
                _processTokenPayment(sub.subscriber, sub.merchant, sub.token, sub.amount, feeAmount, merchantAmount);
            }

            // Update subscription
            sub.paymentCount++;
            sub.nextPayment = BasePayments.calculateNextPayment(block.timestamp, sub.period);

            emit BasePayments.PaymentProcessed(subId, sub.amount, sub.paymentCount); 
        }

        /**
         * @dev Cancel a subscription
         * @param subId Subscription ID 
         */
        function cancelSubscription(bytes32 subId) external {
            BasePayments.Subscription storage sub = subscriptions[subId];
            require(
                msg.sender == sub.subscriber || msg.sender == sub.merchant,
                "Not authorized" 
            );

            sub.active = false;
            emit BasePayments.SubscriptionCanceled(subId, msg.sender); 
        }

        /**
         * @dev Batch process multiple payments
         * @param subIds Array of subscription IDs 
         */
        function batchProcessPayments(bytes32[] calldata subIds) external nonReentrant {
            uint256 length = subIds.length;
            require(length > 0, "Empty array");

            for (uint256 i = 0; i < length;) {
                try this.processPayment(subIds[i]) {} catch {
                    // Payment processed successfully
                } catch Error(string memory reason) {
                    emit BasePayments.PaymentFailed(subIds[i], reason); 
                } catch {
                    emit BasePayments.PaymentFailed(subIds[i], "Unknown error"); 
                }
                unchecked { ++i; } 
            }
        }

        // =============================================================================
        // PAYMENT PROCESSING
        // =============================================================================

        /**
         * @dev Process initial payment when subscribing  
         */
        function _processInitialPayment(BasePayments.PaymentPlan storage plan) internal {
            uint256 feeAmount = (plan.amount * platformFee) / 10000;
            uint256 merchantAmount = plan.amount - feeAmount;

            if (plan.token == address(0)) {
                require(msg.value == plan.amount, "Incorrect payment amount");

                if (plan.token == address(0)) {
                    require(feeRecipient).transfer(feeAmount); 
                }
                payable(plan.merchant).transfer(merchantAmount); 
                } else {
                    IERC20 token = IERC20(plan.token); 

                    if (feeAmount > 0) {
                        token.safeTransferFrom(msg.sender, feeRecipient, feeAmount);  
                    }
                    token.safeTransferFrom(msg.sender, plan.merchant, merchantAmount);  
                }
            }

            /**
             * @dev Process ETH payment 
             */
            function _processETHPayment(
                address subscriber,
                address merchant,
                uint256 totalAmount,
                uint256 feeAmount,
                uint256 merchantAmount 
            ) internal {
                require(subscriber.balance >= totalAmount, "Insufficient balance");

                // In real implementation, you would need a different mechanism for ETH
                // This is a simplified version - typically would use permit or pre approval
                revert("ETH recurring payments need escrow mechanism"); 
            }

            /**
             * @dev Process token payment  
             */
            function _processTokenPayment(
                address subscriber,
                address merchant,
                address token,
                uint256 totalAmount,
                uint256 feeAmount,
                uint256 merchantAmount 
            ) internal {
                IERC20 paymentToken = IERC20(token);

                require(paymentToken.allowance(subscriber, address(this)) >= totalAmount, "Insufficient allowance");
                require(
                    paymentToken.balanceOf(subscriber) >= totalAmount,
                    "Insufficient balance"  
                );

                if (feeAmount > 0) {
                    paymentToken.safeTransferFrom(subscriber, feeRecipient, feeAmount);  
                }
                paymentToken.safeTransferFrom(subscriber, merchant, merchantAmount);   
            }

            // =============================================================================
            // VIEW FUNCTIONS
            // =============================================================================

            /**
             * @dev Get payment plan details 
             */
            function getPaymentPlan(bytes32 planId)
                external
                view
                returns (BasePayments.PaymentPlan memory) 
            {
                return paymentPlans[planId];  
            }

            /**
             * @dev Get subscription details 
             */
            function getSubscription(bytes32 subId)
                external
                view
                returns (BasePayments.Subscription memory) 
            {
                return subscriptions[subId];   
            }

            /**
             * @dev Check if payment is due 
             */
            function isPaymentDue(bytes32 subId) external view returns (bool) {
                return BasePayments.isPaymentDue(subscriptions[subId]);  
            }

            /**
             * @dev Get user subscriptions 
             */
            function getUserSubscriptions(address user)
                external
                view
                returns (bytes32[] memory) 
            {
                return userSubscriptions[user];   
            }

            /**
             * @dev Get merchant plans 
             */
            function getMerchantPlans(address merchant)
                external
                view
                returns (bytes32[] memory) 
            {
                return merchantPlans[merchant];    
            }

            // =============================================================================
            // ADMIN FUNCTIONS
            // =============================================================================

            /**
             * @dev Update platform fee (only owner) 
             */
            function updatePlatformFee(uint256 newFee) external onlyOwner {
                require(newFee <= 1000, "Fee too high"); // Max 10%
                platformFee = newFee; 
            }

            /**
             * @dev Update fee recipient (only owner)  
             */
            function updateFeeRecipient(address newRecipient) external onlyOwner {
                require(newRecipient != address(0), "Invalid recipient");
                feeRecipient = newRecipient;  
            }

            /**
             * @dev Emergency withdrawal (only owner)   
             */
            function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
                if (token == address(0)) {
                    payable(owner()).transfer(amount);   
                } else {
                    IERC20(token).safeTransfer(owner(), amount);   
                }
            }
        }
    }
}
