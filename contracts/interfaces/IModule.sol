// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; // Will be updated to 0.8.27

/**
 * @title IModule
 * @dev Standard interface that all MonarchKit modules must implement
 * @notice Ensures consistent behavior across all MonarchKit ecosystem modules
 */
interface IModule {
    // Events
    event ModuleInitialized(address indexed module, string indexed moduleType, string version);
    event ModuleConfigured(address indexed configurer, bytes configData);
    event ModulePaused(address indexed pauser);
    event ModuleUnpaused(address indexed unpauser);

    // Errors
    error ModuleNotInitialized();
    error ModuleAlreadyInitialized();
    error ModulePaused();
    error InvalidConfiguration(string reason);
    error UnauthorizedModuleAccess(address caller);

    /**
     * @notice Initialize the module
     * @dev Should only be called once during deployment
     * @param initData Initialization data specific to the module
     */
    function initialize(bytes calldata initData) external;

    /**
     * @notice Get the module type identifier
     * @return moduleType Unique identifier for this module type
     */
    function moduleType() external pure returns (string memory moduleType);

    /**
     * @notice Get the module version
     * @return version Current version of the module
     */
    function moduleVersion() external pure returns (string memory version);

    /**
     * @notice Check if the module is initialized
     * @return initialized True if module has been initialized
     */
    function isInitialized() external view returns (bool initialized);

    /**
     * @notice Check if the module is paused
     * @return paused True if module is currently paused
     */
    function isPaused() external view returns (bool paused);

    /**
     * @notice Pause the module (admin only)
     * @dev Should prevent all non-admin operations when paused
     */
    function pause() external;

    /**
     * @notice Unpause the module (admin only)
     * @dev Restores normal operation
     */
    function unpause() external;

    /**
     * @notice Configure module-specific settings
     * @param configData Configuration data specific to the module
     */
    function configure(bytes calldata configData) external;

    /**
     * @notice Get the BaseKit core registry address
     * @return registry Address of the BaseKit core registry
     */
    function baseKitRegistry() external view returns (address registry);

    /**
     * @notice Check if an address has admin privileges for this module
     * @param account Address to check
     * @return isAdmin True if address has admin privileges
     */
    function isAdmin(address account) external view returns (bool isAdmin);
}