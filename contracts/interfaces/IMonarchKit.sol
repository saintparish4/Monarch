// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IMonarchKit
 * @dev Main interface for the MonarchKit ecosystem
 * @notice Defines the core functionality that all MonarchKit implementations must provide
 */
interface IMonarchKit {
    // Events
    event ModuleRegistered(address indexed module, string indexed moduleType, address indexed owner);
    event ModuleUpdated(address indexed oldModule, address indexed newModule, string indexed moduleType);
    event ModuleRemoved(address indexed module, string indexed moduleType);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Errors
    error ModuleNotFound(string moduleType);
    error ModuleAlreadyExists(string moduleType);
    error UnauthorizedAccess(address caller);
    error InvalidModule(address module);
    error InvalidModuleType(string moduleType);

    /**
     * @notice Register a new module in the BaseKit ecosystem
     * @param module Address of the module contract
     * @param moduleType Type identifier for the module (e.g., "gasless", "payments", "social")
     */
    function registerModule(address module, string calldata moduleType) external;

    /**
     * @notice Update an existing module
     * @param moduleType Type identifier for the module to update
     * @param newModule Address of the new module contract
     */
    function updateModule(string calldata moduleType, address newModule) external;

    /**
     * @notice Remove a module from the registry
     * @param moduleType Type identifier for the module to remove
     */
    function removeModule(string calldata moduleType) external;

    /**
     * @notice Get the address of a specific module
     * @param moduleType Type identifier for the module
     * @return module Address of the module contract
     */
    function getModule(string calldata moduleType) external view returns (address module);

    /**
     * @notice Check if a module is registered
     * @param moduleType Type identifier for the module
     * @return exists True if module exists, false otherwise
     */
    function moduleExists(string calldata moduleType) external view returns (bool exists);

    /**
     * @notice Get all registered module types
     * @return moduleTypes Array of all registered module type identifiers
     */
    function getModuleTypes() external view returns (string[] memory moduleTypes);

    /**
     * @notice Get version information
     * @return version Current version of BaseKit core
     */
    function version() external pure returns (string memory version);

    /**
     * @notice Get the owner of the BaseKit registry
     * @return owner Address of the current owner
     */
    function owner() external view returns (address owner);

    /**
     * @notice Transfer ownership of the BaseKit registry
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external;
}