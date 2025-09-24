// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../gasless/interfaces/IPaymaster.sol";
import "../gasless/interfaces/IUserOperation.sol";
import "../libraries/Constants.sol";
import "../libraries/Validation.sol";
import "../libraries/Security.sol";
import "../libraries/Math.sol";
import "../interfaces/IModule.sol";

/**
 * @title BasePaymaster
 * @dev Comprehensive paymaster implementation for sponsoring gas fees in the MonarchKit ecosystem
 * @notice Handles various gas sponsorship modes including free transactions, subscriptions, 
 *         deposit-based payments, and token payments. Integrates with ERC-4337 account abstraction.
 * 
 * Features:
 * - Multiple sponsorship modes (FREE, SUBSCRIPTION, TOKEN_PAYMENT, DEPOSIT_BASED)
 * - Monthly usage limits and tracking
 * - Whitelist management for free transactions
 * - Subscription-based gas sponsorship
 * - Deposit-based pre-paid gas
 * - Admin controls and emergency pause functionality
 * - Comprehensive usage analytics and reporting
 * 
 * @author MonarchKit Team
 * @custom:version 1.0.0
 * @custom:module-type gasless
 */
contract BasePaymaster is IPaymaster, IModule {
    using Security for Security.SecurityState;
    using Math for uint256;

    // State
    Security.SecurityState private _security;
    address public immutable baseKitRegistry;
    address public immutable entryPoint;

    // Paymaster deposits and balances
    mapping(address => uint256) public deposits;
    mapping(address => Subscription) public subscriptions;
    mapping(address => uint256) public whitelistGasLimits;
    mapping(address => bool) public whitelistedUsers;

    // Monthly usage tracking
    mapping(address => mapping(uint256 => uint256)) public monthlyUsage;

    // Statistics
    uint256 public totalGasSponsored;
    uint256 public totalUsersSponsored;

    // Configuration
    uint256 public maxGasSponsorshipPerMonth = Constants.MAX_MONTHLY_LIMIT;
    uint256 public minimumStake = 1 ether;
    
    // Constants
    uint256 private constant MAX_BATCH_SIZE = 100;
    uint256 private constant MIN_GAS_LIMIT = 21000;

    // Module info
    string public constant MODULE_TYPE = Constants.MODULE_TYPE_GASLESS;
    string public constant MODULE_VERSION = "1.0.0";

    // Modifiers
    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "Only EntryPoint");
        _;
    }

    modifier onlyAdmin() {
        _security.requireAdmin(msg.sender);
        _;
    }

    modifier whenNotPaused() {
        _security.requireNotPaused();
        _;
    }

    /**
     * @notice Initialize the paymaster
     * @param registry The BaseKit registry address
     * @param entryPointAddr The EntryPoint contract address
     * @param initialOwner The initial owner/admin
     */
    constructor(
        address registry,
        address entryPointAddr,
        address initialOwner
    ) {
        Validation.validateContract(registry);
        Validation.validateContract(entryPointAddr);
        Validation.validateAddress(initialOwner);

        baseKitRegistry = registry;
        entryPoint = entryPointAddr;
        _security.initialize(initialOwner);

        emit ModuleInitialized(address(this), MODULE_TYPE, MODULE_VERSION);
    }

    /**
     * @notice Validate a user operation for gas sponsorship
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @param maxCost Maximum cost this paymaster might pay
     * @return context Data to be passed to postOp
     * @return validAfter Timestamp after which operation is valid
     * @return validUntil Timestamp until which operation is valid
     */
    function validatePaymasterUserOp(
        IUserOperation.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) 
        external 
        override 
        onlyEntryPoint 
        whenNotPaused
        returns (bytes memory context, uint256 validAfter, uint256 validUntil) 
    {
        // Parse paymaster data to determine mode
        PaymasterMode mode = _parsePaymasterMode(userOp.paymasterAndData);
        address user = userOp.sender;

        // Validate sponsorship based on mode
        bool canSponsor = false;
        
        if (mode == PaymasterMode.FREE) {
            canSponsor = _validateFreeSponsorship(user, maxCost);
        } else if (mode == PaymasterMode.SUBSCRIPTION) {
            canSponsor = _validateSubscriptionSponsorship(user, maxCost);
        } else if (mode == PaymasterMode.DEPOSIT_BASED) {
            canSponsor = _validateDepositSponsorship(user, maxCost);
        } else if (mode == PaymasterMode.TOKEN_PAYMENT) {
            // Token payment validation would go here
            canSponsor = false; // Not implemented in MVP
        }

        if (!canSponsor) {
            revert PaymasterValidationFailed("Insufficient sponsorship");
        }

        // Pack context for postOp
        context = abi.encode(user, mode, maxCost, block.timestamp);
        
        // Set validity period (24 hours from now)
        validAfter = block.timestamp;
        validUntil = block.timestamp + Constants.SECONDS_PER_DAY;

        return (context, validAfter, validUntil);
    }

    /**
     * @notice Handle post-operation logic and gas accounting
     * @param mode The paymaster mode used
     * @param context Context data from validatePaymasterUserOp
     * @param actualGasCost Actual gas cost of the operation
     */
    function postOp(
        PaymasterMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override onlyEntryPoint {
        (address user, PaymasterMode contextMode, uint256 maxCost, uint256 timestamp) = 
            abi.decode(context, (address, PaymasterMode, uint256, uint256));

        require(mode == contextMode, "Mode mismatch");

        // Update usage tracking
        _updateUsageTracking(user, actualGasCost, timestamp);

        // Handle payment based on mode
        if (mode == PaymasterMode.SUBSCRIPTION) {
            _handleSubscriptionPayment(user, actualGasCost);
        } else if (mode == PaymasterMode.DEPOSIT_BASED) {
            _handleDepositPayment(user, actualGasCost);
        }

        // Update statistics
        totalGasSponsored = totalGasSponsored.safeAdd(actualGasCost);

        emit UserOpSponsored(user, bytes32(0), actualGasCost, mode);
    }

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
    ) external payable override onlyAdmin {
        Validation.validateAddress(user);
        Validation.validateMonthlyLimit(monthlyLimit);
        Validation.validateSubscriptionDuration(duration);

        require(msg.value >= minimumStake, "Insufficient payment");

        Subscription storage sub = subscriptions[user];
        sub.monthlyLimit = monthlyLimit;
        sub.usedThisMonth = 0;
        sub.lastResetTime = Constants.getCurrentMonthStart();
        sub.isActive = true;

        emit SubscriptionCreated(user, monthlyLimit, duration);
    }

    /**
     * @notice Update a user's subscription limit
     * @param user The user address
     * @param newMonthlyLimit New monthly gas limit
     */
    function updateSubscription(
        address user,
        uint256 newMonthlyLimit
    ) external override onlyAdmin {
        Validation.validateAddress(user);
        Validation.validateMonthlyLimit(newMonthlyLimit);

        Subscription storage sub = subscriptions[user];
        require(sub.isActive, "Subscription not active");

        sub.monthlyLimit = newMonthlyLimit;

        emit SubscriptionUpdated(user, newMonthlyLimit);
    }

    /**
     * @notice Add a user to the free transaction whitelist
     * @param user The user address
     * @param gasLimit Gas limit for free transactions
     */
    function addToWhitelist(
        address user,
        uint256 gasLimit
    ) external override onlyAdmin {
        Validation.validateAddress(user);
        require(gasLimit >= MIN_GAS_LIMIT, "Gas limit too low");

        whitelistedUsers[user] = true;
        whitelistGasLimits[user] = gasLimit;

        emit UserWhitelisted(user, gasLimit);
    }

    /**
     * @notice Remove a user from the free transaction whitelist
     * @param user The user address
     */
    function removeFromWhitelist(address user) external override onlyAdmin {
        whitelistedUsers[user] = false;
        whitelistGasLimits[user] = 0;

        emit UserRemovedFromWhitelist(user);
    }

    /**
     * @notice Add deposit for a user to pay for gas
     * @param user The user address
     */
    function addDeposit(address user) external payable override {
        Validation.validateAddress(user);
        Validation.validateDepositAmount(msg.value);

        deposits[user] = deposits[user].safeAdd(msg.value);

        emit DepositAdded(user, msg.value);
    }

    /**
     * @notice Withdraw deposit for a user
     * @param user The user address
     * @param amount Amount to withdraw
     */
    function withdrawDeposit(address user, uint256 amount) external override {
        require(msg.sender == user || _security.isAdmin(msg.sender), "Unauthorized");
        require(deposits[user] >= amount, "Insufficient deposit");

        deposits[user] = deposits[user].safeSub(amount);

        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit DepositWithdrawn(user, amount);
    }

    /**
     * @notice Get user's subscription information
     * @param user The user address
     * @return subscription The subscription data
     */
    function getSubscription(address user) 
        external 
        view 
        override 
        returns (Subscription memory subscription) 
    {
        return subscriptions[user];
    }

    /**
     * @notice Get user's deposit balance
     * @param user The user address
     * @return balance The deposit balance
     */
    function getDepositBalance(address user) external view override returns (uint256 balance) {
        return deposits[user];
    }

    /**
     * @notice Check if user is whitelisted for free transactions
     * @param user The user address
     * @return whitelisted True if user is whitelisted
     * @return gasLimit Gas limit for free transactions
     */
    function isWhitelisted(address user) 
        external 
        view 
        override 
        returns (bool whitelisted, uint256 gasLimit) 
    {
        return (whitelistedUsers[user], whitelistGasLimits[user]);
    }

    /**
     * @notice Calculate gas cost for a user operation
     * @param userOp The user operation
     * @return gasCost The estimated gas cost
     */
    function calculateGasCost(IUserOperation.UserOperation calldata userOp) 
        external 
        view 
        override 
        returns (uint256 gasCost) 
    {
        return Math.calculateUserOpGasCost(
            userOp.callGasLimit,
            userOp.verificationGasLimit,
            userOp.preVerificationGas,
            userOp.maxFeePerGas
        );
    }

    /**
     * @notice Get paymaster's deposit on entry point
     * @return balance The deposit balance
     */
    function getPaymasterDeposit() external view override returns (uint256 balance) {
        // In production, this would call entryPoint.balanceOf(address(this))
        return address(this).balance;
    }

    /**
     * @notice Add deposit to paymaster's entry point balance
     */
    function addPaymasterDeposit() external payable override onlyAdmin {
        // In production, this would call entryPoint.depositTo{value: msg.value}(address(this))
        emit PaymasterDepositAdded(msg.value);
    }

    /**
     * @notice Withdraw from paymaster's entry point deposit
     * @param amount Amount to withdraw
     */
    function withdrawPaymasterDeposit(uint256 amount) external override onlyAdmin {
        // In production, this would call entryPoint.withdrawTo(payable(msg.sender), amount)
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        emit PaymasterDepositWithdrawn(amount);
    }

    // IModule implementation

    function initialize(bytes calldata) external pure override {
        revert("Paymaster initialized in constructor");
    }

    function moduleType() external pure override returns (string memory) {
        return MODULE_TYPE;
    }

    function moduleVersion() external pure override returns (string memory) {
        return MODULE_VERSION;
    }

    function isInitialized() external pure override returns (bool) {
        return true;
    }

    function isPaused() external view override returns (bool) {
        return _security.paused;
    }

    function pause() external override onlyAdmin {
        _security.pause(msg.sender);
    }

    function unpause() external override onlyAdmin {
        _security.unpause(msg.sender);
    }

    function configure(bytes calldata configData) external override onlyAdmin {
        // Decode configuration data
        if (configData.length >= 64) {
            (uint256 newMaxGasSponsorship, uint256 newMinimumStake) = 
                abi.decode(configData, (uint256, uint256));
            
            if (newMaxGasSponsorship > 0) {
                maxGasSponsorshipPerMonth = newMaxGasSponsorship;
            }
            if (newMinimumStake > 0) {
                minimumStake = newMinimumStake;
            }
            
            emit PaymasterConfigUpdated(maxGasSponsorshipPerMonth, minimumStake);
        }
        emit ModuleConfigured(msg.sender, configData);
    }

    function baseKitRegistry() external view override returns (address) {
        return baseKitRegistry;
    }

    function isAdmin(address account) external view override returns (bool) {
        return _security.isAdmin(account);
    }

    // Additional utility functions

    /**
     * @notice Get monthly usage for a specific user and month
     * @param user The user address
     * @param monthStart The month start timestamp
     * @return usage The gas usage for that month
     */
    function getMonthlyUsage(address user, uint256 monthStart) external view returns (uint256 usage) {
        return monthlyUsage[user][monthStart];
    }

    /**
     * @notice Get current month usage for a user
     * @param user The user address
     * @return usage Current month's gas usage
     */
    function getCurrentMonthUsage(address user) external view returns (uint256 usage) {
        uint256 currentMonthStart = Constants.getCurrentMonthStart();
        return monthlyUsage[user][currentMonthStart];
    }

    /**
     * @notice Check if user can afford a transaction
     * @param user The user address
     * @param estimatedCost The estimated gas cost
     * @param mode The paymaster mode to check
     * @return canAfford True if user can afford the transaction
     */
    function canAffordTransaction(
        address user, 
        uint256 estimatedCost, 
        PaymasterMode mode
    ) external view returns (bool canAfford) {
        if (mode == PaymasterMode.FREE) {
            return _validateFreeSponsorship(user, estimatedCost);
        } else if (mode == PaymasterMode.SUBSCRIPTION) {
            return _validateSubscriptionSponsorship(user, estimatedCost);
        } else if (mode == PaymasterMode.DEPOSIT_BASED) {
            return _validateDepositSponsorship(user, estimatedCost);
        }
        return false;
    }

    /**
     * @notice Emergency function to pause all operations
     */
    function emergencyPause() external onlyAdmin {
        _security.pause(msg.sender);
        emit ModulePaused(msg.sender);
    }

    /**
     * @notice Batch update multiple user whitelists
     * @param users Array of user addresses
     * @param gasLimits Array of gas limits for each user
     */
    function batchUpdateWhitelist(
        address[] calldata users,
        uint256[] calldata gasLimits
    ) external onlyAdmin {
        require(users.length == gasLimits.length, "Array length mismatch");
        require(users.length <= MAX_BATCH_SIZE, "Batch size too large");
        require(users.length > 0, "Empty batch not allowed");
        
        for (uint256 i = 0; i < users.length; i++) {
            Validation.validateAddress(users[i]);
            require(gasLimits[i] >= MIN_GAS_LIMIT, "Gas limit too low");
            
            whitelistedUsers[users[i]] = true;
            whitelistGasLimits[users[i]] = gasLimits[i];
            
            emit UserWhitelisted(users[i], gasLimits[i]);
        }
    }

    // Internal functions

    function _parsePaymasterMode(bytes calldata paymasterAndData) 
        internal 
        pure 
        returns (PaymasterMode mode) 
    {
        if (paymasterAndData.length < 20) {
            revert PaymasterValidationFailed("Invalid paymaster data");
        }

        // Extract mode from paymaster data
        if (paymasterAndData.length >= 21) {
            uint8 modeValue = uint8(paymasterAndData[20]);
            if (modeValue <= uint8(PaymasterMode.DEPOSIT_BASED)) {
                mode = PaymasterMode(modeValue);
            } else {
                revert InvalidPaymasterMode(PaymasterMode(modeValue));
            }
        } else {
            mode = PaymasterMode.FREE; // Default mode
        }
    }

    function _validateFreeSponsorship(address user, uint256 maxCost) 
        internal 
        view 
        returns (bool) 
    {
        return whitelistedUsers[user] && maxCost <= whitelistGasLimits[user];
    }

    function _validateSubscriptionSponsorship(address user, uint256 maxCost) 
        internal 
        view 
        returns (bool) 
    {
        Subscription storage sub = subscriptions[user];
        if (!sub.isActive) return false;

        // Check if we need to reset monthly usage
        if (!Constants.isInCurrentMonth(sub.lastResetTime)) {
            return maxCost <= sub.monthlyLimit;
        }

        return sub.usedThisMonth.safeAdd(maxCost) <= sub.monthlyLimit;
    }

    function _validateDepositSponsorship(address user, uint256 maxCost) 
        internal 
        view 
        returns (bool) 
    {
        return deposits[user] >= maxCost;
    }

    function _updateUsageTracking(address user, uint256 actualCost, uint256 timestamp) internal {
        uint256 monthStart = Constants.getCurrentMonthStart();
        uint256 oldUsage = monthlyUsage[user][monthStart];
        monthlyUsage[user][monthStart] = oldUsage.safeAdd(actualCost);
        
        // Emit event if this is the first usage of the month
        if (oldUsage == 0 && actualCost > 0) {
            emit MonthlyUsageReset(user, monthStart);
        }
    }

    function _handleSubscriptionPayment(address user, uint256 actualCost) internal {
        Subscription storage sub = subscriptions[user];
        
        // Reset monthly usage if needed
        if (!Constants.isInCurrentMonth(sub.lastResetTime)) {
            sub.usedThisMonth = 0;
            sub.lastResetTime = Constants.getCurrentMonthStart();
        }

        sub.usedThisMonth = sub.usedThisMonth.safeAdd(actualCost);
    }

    function _handleDepositPayment(address user, uint256 actualCost) internal {
        deposits[user] = deposits[user].safeSub(actualCost);
    }

    // Receive function to accept ETH
    receive() external payable {}

    // Additional Events (beyond IPaymaster interface)
    event UserWhitelisted(address indexed user, uint256 gasLimit);
    event UserRemovedFromWhitelist(address indexed user);
    event PaymasterConfigUpdated(uint256 maxGasSponsorship, uint256 minimumStake);
    event MonthlyUsageReset(address indexed user, uint256 monthStart);
    event PaymasterDepositAdded(uint256 amount);
    event PaymasterDepositWithdrawn(uint256 amount);
}