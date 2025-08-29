// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BasePaymentsManager.sol";

/**
 * @title BasePaymentsFactory
 * @dev Factory for deploying isolated payment manager contracts
 * @notice Allows each application to have its own payment infrastructure
 */
contract BasePaymentsFactory {
    // =============================================================================
    // EVENTS
    // =============================================================================

    event PaymentManagerDeployed(
        address indexed manager,
        address indexed owner,
        address indexed feeRecipient,
        uint256 timestamp
    );

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    mapping(address => address[]) public userManagers;
    address[] public allManagers;

    uint256 public deploymentCount;

    // =============================================================================
    // DEPLOYMENT FUNCTIONS
    // =============================================================================

    /**
     * @dev Deploy a new payment manager contract
     * @param feeRecipient Address to receive platform fees
     * @return manager Address of deployed payment manager
     */
    function deployPaymentManager(address feeRecipient) external returns (address manager) {
        require(feeRecipient != address(0), "Invalid fee recipient");

        // Deploy new payment manager
        manager = address(new BasePaymentsManager(feeRecipient));

        // Transfer ownership to deployer
        BasePaymentsManager(manager).transferOwnership(msg.sender);

        // Track deployment
        userManagers[msg.sender].push(manager);
        allManagers.push(manager);
        deploymentCount++;

        emit PaymentManagerDeployed(manager, msg.sender, feeRecipient, block.timestamp);
    }

    /**
     * @dev Deploy payment manager with custom parameters
     * @param feeRecipient Address to receive platform fees
     * @param initialOwner Initial owner of the contract
     * @return manager Address of deployed payment manager
     */
    function deployPaymentManagerWithOwner(
        address feeRecipient,
        address initialOwner
    ) external returns (address manager) {
        require(feeRecipient != address(0), "Invalid fee recipient");
        require(initialOwner != address(0), "Invalid initial owner");

        // Deploy new payment manager
        manager = address(new BasePaymentsManager(feeRecipient));

        // Transfer ownership to specified owner
        BasePaymentsManager(manager).transferOwnership(initialOwner);

        // Track deployment under deployer
        userManagers[msg.sender].push(manager);
        allManagers.push(manager);
        deploymentCount++;

        emit PaymentManagerDeployed(manager, initialOwner, feeRecipient, block.timestamp);
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get all payment managers deployed by a user
     * @param user Address of the user
     * @return Array of payment manager addresses
     */
    function getUserManagers(address user) external view returns (address[] memory) {
        return userManagers[user];
    }

    /**
     * @dev Get all deployed payment managers
     * @return Array of all payment manager addresses
     */
    function getAllManagers() external view returns (address[] memory) {
        return allManagers;
    }

    /**
     * @dev Get total number of deployed managers
     * @return Total deployment count
     */
    function getTotalDeployments() external view returns (uint256) {
        return deploymentCount;
    }

    /**
     * @dev Get number of managers deployed by a user
     * @param user Address of the user
     * @return Number of managers deployed by user
     */
    function getUserManagerCount(address user) external view returns (uint256) {
        return userManagers[user].length;
    }

    /**
     * @dev Check if address is a payment manager deployed by this factory
     * @param manager Address to check
     * @return True if manager was deployed by this factory
     */
    function isValidManager(address manager) external view returns (bool) {
        for (uint256 i = 0; i < allManagers.length; i++) {
            if (allManagers[i] == manager) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get paginated list of all managers
     * @param offset Starting index
     * @param limit Number of items to return
     * @return managers Array of manager addresses
     * @return total Total number of managers
     */
    function getPaginatedManagers(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory managers, uint256 total) {
        total = allManagers.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        managers = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            managers[i - offset] = allManagers[i];
        }
    }

    /**
     * @dev Get manager details
     * @param manager Payment manager address
     * @return owner Owner of the manager
     * @return feeRecipient Fee recipient of the manager
     * @return platformFee Current platform fee
     */
    function getManagerDetails(
        address manager
    ) external view returns (address owner, address feeRecipient, uint256 platformFee) {
        BasePaymentsManager paymentManager = BasePaymentsManager(manager);

        try paymentManager.owner() returns (address _owner) {
            owner = _owner;
        } catch {
            owner = address(0);
        }

        try paymentManager.feeRecipient() returns (address _feeRecipient) {
            feeRecipient = _feeRecipient;
        } catch {
            feeRecipient = address(0);
        }

        try paymentManager.platformFee() returns (uint256 _platformFee) {
            platformFee = _platformFee;
        } catch {
            platformFee = 0;
        }
    }
}
