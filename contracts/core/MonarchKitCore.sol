// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; // Will be updated to 0.8.27

import "./interfaces/IMonarchKit.sol";
import "./interfaces/IModule.sol";
import "./Registry.sol";

/**
 * @title MonarchKit
 * @dev Main factory and registry for the MonarchKit ecosystem
 * @notice Serves as the central hub for all MonarchKit modules and functionality 
 */
contract MonarchKitCore is IMonarchKit {
    // Constants
    string public constant VERSION = "1.0.0";

    // State variables
    Registry public immutable registry;
    address public override owner;
    bool private _initialized;

    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedAccess(msg.sender);
        _;
    }

    /**
     * @notice Initialize MonarchKit Core
     * @param initialOwner Address of the initial owner 
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert InvalidModule(initialOwner);

        owner = initialOwner;
        registry = new Registry(initialOwner);
        _initialized = true;

        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @notice Register a new module in the MonarchKit ecosystem
     * @param module Address of the module contract
     * @param moduleType Type identifier for the module 
     */
    function registerModule(
        address module,
        string calldata moduleType 
    ) external override onlyOwner onlyInitialized {
        if (module == address(0)) revert InvalidModule(module);
        if (bytes(moduleType).length == 0) revert InvalidModuleType(moduleType);

        // Verify module implements IModule interface and is not paused
        try IModule(module).moduleType() returns (string memory returnedType) {
            if (keccak256(bytes(returnedType)) != keccak256(bytes(moduleType))) revert InvalidModule(module); 
        }

        // Check if module is initalized
        if (!IModule(module).isInitialized()) {
            revert InvalidModule(module); 
        }

        // Register in the registry
        registry.registerModule(module, moduleType);

        emit ModuleRegistered(module, moduleType, msg.sender);
    } catch {
        revert InvalidModule(module); 
    }
}

/**
 * @notice Update an existing module 
 * @param moduleType Type identifier for the module to update
 * @param newModule Address of the new module contract 
 */
function updateModule(
    string calldata moduleType,
    address newModule 
) external override onlyOwner onlyInitialized {
    if (newModule == address(0)) revert InvalidModule(newModule);

    address oldModule = registry.getModule(moduleType);

    // Verify new module implements IModule interface
    try IModule(newModule).moduleType() returns (string memory returnedType) {
        if (keccak256(bytes(returnedType)) != keccak256(bytes(moduleType))) {
            revert InvalidModule(newModule);  
        }

        if (!IModule(newModule).isInitialized()) {
            revert InvalidModule(newModule);   
        }

        registry.updateModule(moduleType, newModule);

        emit ModuleUpdated(oldModule, newModule, moduleType);
    } catch {
        revert InvalidModule(newModule); 
    }
}

/**
 * @notice Remove a module from the registry
 * @param moduleType Type identifier for the module to remove 
 */
function removeModule(string calldata moduleType) external override onlyOwner onlyInitialized {
    address module = registry.getModule(moduleType);

    registry.removeModule(moduleType);

    emit ModuleRemoved(module, moduleType);
}

/**
     * @notice Get the address of a specific module
     * @param moduleType Type identifier for the module
     * @return module Address of the module contract
     */
    function getModule(string calldata moduleType) external view override onlyInitialized returns (address module) {
        return registry.getModule(moduleType);
    }

    /**
     * @notice Check if a module is registered
     * @param moduleType Type identifier for the module
     * @return exists True if module exists, false otherwise
     */
    function moduleExists(string calldata moduleType) external view override onlyInitialized returns (bool exists) {
        return registry.moduleExists(moduleType);
    }

    /**
     * @notice Get all registered module types
     * @return moduleTypes Array of all registered module type identifiers
     */
    function getModuleTypes() external view override onlyInitialized returns (string[] memory moduleTypes) {
        return registry.getModuleTypes();
    }

    /**
     * @notice Get version information
     * @return version Current version of BaseKit core
     */
    function version() external pure override returns (string memory version) {
        return VERSION;
    }

    /**
     * @notice Transfer ownership of the BaseKit registry
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external override onlyOwner {
        if (newOwner == address(0)) revert InvalidModule(newOwner);
        
        address previousOwner = owner;
        owner = newOwner;
        
        // Also transfer ownership of the registry
        registry.transferOwnership(newOwner);
        
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /**
     * @notice Get the registry contract address
     * @return registryAddress Address of the registry contract
     */
    function getRegistry() external view returns (address registryAddress) {
        return address(registry);
    }

    /**
     * @notice Check if the core is initialized
     * @return initialized True if core has been initialized
     */
    function isInitialized() external view returns (bool initialized) {
        return _initialized;
    }

    /**
     * @notice Get module information including version and status
     * @param moduleType Type identifier for the module
     * @return moduleAddress Address of the module
     * @return moduleVersion Version of the module
     * @return isModuleInitialized Whether the module is initialized
     * @return isModulePaused Whether the module is paused
     */
    function getModuleInfo(string calldata moduleType) external view onlyInitialized returns (
        address moduleAddress,
        string memory moduleVersion,
        bool isModuleInitialized,
        bool isModulePaused
    ) {
        moduleAddress = registry.getModule(moduleType);
        
        try IModule(moduleAddress).moduleVersion() returns (string memory version) {
            moduleVersion = version;
        } catch {
            moduleVersion = "unknown";
        }

        try IModule(moduleAddress).isInitialized() returns (bool initialized) {
            isModuleInitialized = initialized;
        } catch {
            isModuleInitialized = false;
        }

        try IModule(moduleAddress).isPaused() returns (bool paused) {
            isModulePaused = paused;
        } catch {
            isModulePaused = true; // Assume paused if we can't check
        }
    }

    /**
     * @notice Emergency pause all modules (if they support it)
     * @dev Attempts to pause all registered modules
     */
    function emergencyPauseAll() external onlyOwner onlyInitialized {
        string[] memory moduleTypes = registry.getModuleTypes();
        
        for (uint256 i = 0; i < moduleTypes.length; i++) {
            address module = registry.getModule(moduleTypes[i]);
            
            try IModule(module).pause() {
                // Module paused successfully
            } catch {
                // Module doesn't support pause or failed to pause
                // Continue with other modules
            }
        }
    }
}