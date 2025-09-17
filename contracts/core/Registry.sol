// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; // Will be updated to 0.8.27

import "./interfaces/IModule.sol";

/**
 * @title Registry
 * @dev Core registry for managing MonarchKit modules
 * @notice Handles registration, updates, and queries for all MonarchKit ecosystem modules
 */
contract Registry {
    // State variables
    address public owner;
    mapping(string => address) public _modules;
    mapping(address => bool) public _registeredModules;
    string[] private _moduleTypes;

    // Events
    event ModuleRegistered(address indexed module, string indexed moduleType, address indexed registeredBy);
    event ModuleUpdated(address indexed oldModule, address indexed newModule, string indexed moduleType);
    event ModuleRemoved(address indexed module, string indexed moduleType);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Errors
    error ModuleNotFound(string moduleType);
    error ModuleAlreadyExists(string moduleType);
    error UnauthorizedAccess(address caller);
    error InvalidModule(address module);
    error InvalidModuleType(string moduleType);
    error InvalidAddress(address addr);

    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedAccess(msg.sender);
        _;
    }

    modifier validModule(address module) {
        if (module == address(0)) revert InvalidAddress(module);
        if (module.code.length == 0) revert InvalidModule(module);
        _;
    }

    modifier validModuleType(string calldata moduleType) {
        if (bytes(moduleType).length == 0) revert InvalidModuleType(moduleType);
        _;
    }

    /**
     * @notice Initialize the registry
     * @param initialOwner Address of the initial owner
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert InvalidAddress(initialOwner);
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @notice Register a new module in the registry
     * @param module Address of the module contract
     * @param moduleType Type identifier for the module
     */
    function registerModule(
        address module,
        string calldata moduleType
    ) external onlyOwner validModule(module) validModuleType(moduleType) {
        if (_modules[moduleType] != address(0)) {
            revert ModuleAlreadyExists(moduleType);
        }

        // Verify the module implements IModule interface
        try IModule(module).moduleType() returns (string memory returnedType) {
            // Verify the returned type matches the registration type
            if (keccak256(bytes(returnedType)) != keccak256(bytes(moduleType))) {
                revert InvalidModule(module);
            }
        } catch {
            revert InvalidModule(module);
        }

        _modules[moduleType] = module;
        _registeredModules[module] = true;
        _moduleTypes.push(moduleType);

        emit ModuleRegistered(module, moduleType, msg.sender);
    }

    /**
     * @notice Update an existing module
     * @param moduleType Type identifier for the module to update
     * @param newModule Address of the new module contract
     */
    function updateModule(
        string calldata moduleType,
        address newModule
    ) external onlyOwner validModule(newModule) validModuleType(moduleType) {
        address oldModule = _modules[moduleType];
        if (oldModule == address(0)) {
            revert ModuleNotFound(moduleType);
        }

        // Verify the new module implements IModule interface
        try IModule(newModule).moduleType() returns (string memory returnedType) {
            if (keccak256(bytes(returnedType)) != keccak256(bytes(moduleType))) {
                revert InvalidModule(newModule);
            }
        } catch {
            revert InvalidModule(newModule);
        }

        _modules[moduleType] = newModule;
        _registeredModules[oldModule] = false;
        _registeredModules[newModule] = true;

        emit ModuleUpdated(oldModule, newModule, moduleType);
    }

    /**
     * @notice Remove a module from the registry
     * @param moduleType Type identifier for the module to remove
     */
    function removeModule(string calldata moduleType) external onlyOwner validModuleType(moduleType) {
        address module = _modules[moduleType];
        if (module == address(0)) {
            revert ModuleNotFound(moduleType);
        }

        delete _modules[moduleType];
        _registeredModules[module] = false;

        // Remove from moduleTypes array
        for (uint256 i = 0; i < _moduleTypes.length; i++) {
            if (keccak256(bytes(_moduleTypes[i])) == keccak256(bytes(moduleType))) {
                _moduleTypes[i] = _moduleTypes[_moduleTypes.length - 1];
                _moduleTypes.pop();
                break;
            }
        }

        emit ModuleRemoved(module, moduleType);
    }

    /**
     * @notice Get the address of a specific module
     * @param moduleType Type identifier for the module
     * @return module Address of the module contract
     */
    function getModule(string calldata moduleType) external view returns (address module) {
        module = _modules[moduleType];
        if (module == address(0)) {
            revert ModuleNotFound(moduleType);
        }
    }

    /**
     * @notice Check if a module is registered
     * @param moduleType Type identifier for the module
     * @return exists True if module exists, false otherwise
     */
    function moduleExists(string calldata moduleType) external view returns (bool exists) {
        return _modules[moduleType] != address(0);
    }

    /**
     * @notice Check if an address is a registered module
     * @param module Address to check
     * @return registered True if address is a registered module
     */
    function isRegisteredModule(address module) external view returns (bool registered) {
        return _registeredModules[module];
    }

    /**
     * @notice Get all registered module types
     * @return moduleTypes Array of all registered module type identifiers
     */
    function getModuleTypes() external view returns (string[] memory moduleTypes) {
        return _moduleTypes;
    }

    /**
     * @notice Get the total number of registered modules
     * @return count Total number of registered modules
     */
    function getModuleCount() external view returns (uint256 count) {
        return _moduleTypes.length;
    }

    /**
     * @notice Transfer ownership of the registry
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress(newOwner);

        address previousOwner = owner;
        owner = newOwner;

        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /**
     * @notice Get version information
     * @return version Current version of the registry
     */
    function version() external pure returns (string memory version) {
        return "1.0.0";
    }
}
