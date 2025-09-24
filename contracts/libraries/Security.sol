// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Security
 * @dev Security utilities and access control functions for MonarchKit
 * @notice Provides common security patterns and access control mechanisms 
 */
library Security {
    // Security state structure
    struct SecurityState {
        address owner;
        mapping(address => bool) admins;
        mapping(address => bool) operators;
        bool paused;
        bool initialized;
        uint256 nonce; 
    }

    // Role constants
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AdminAdded(address indexed admin, address indexed addedBy);
    event AdminRemoved(address indexed admin, address indexed removedBy);
    event OperatorAdded(address indexed operator, address indexed addedBy);
    event OperatorRemoved(address indexed operator, address indexed removedBy);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    // Errors
    error UnauthorizedAccess(address caller, bytes32 requiredRole);
    error ContractPaused();
    error ContractNotPaused();
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidAddress(address addr);
    error SelfRoleModification();

    /**
     * @notice Initialize security state
     * @param state The security state storage
     * @param initialOwner The initial owner address 
     */
    function initialize(SecurityState storage state, address initialOwner) internal {
        if (state.initialized) revert AlreadyInitialized();
        if (initialOwner == address(0)) revert InvalidAddress(initialOwner);

        state.owner = initialOwner;
        state.initialized = true;
        state.nonce = 1;

        emit OwnershipTransferred(address(0), initialOwner); 
    }

    /**
     * @notice Check if caller is the owner
     * @param state The security state storage
     * @return isOwner True if caller is owner 
     */
    function isOwner(SecurityState storage state, address caller)
        internal 
        view
        returns (bool isOwner)
    {
        return state.owner == caller;
    }

    /**
     * @notice Check if caller is an admin
     * @param state The security state storage
     * @param caller The address to check
     * @return isAdmin True if caller is admin 
     */
    function isAdmin(SecurityState storage state, address caller)
        internal
        view
        returns (bool isAdmin)
    {
        return state.admins[caller] || isOwner(state, caller); 
    }

    /**
     * @notice Check if caller is an operator
     * @param state The security state storage
     * @param caller The address to check
     * @return isOperator True is caller is operator  
     */
    function isOperator(SecurityState storage state, address caller)
        internal
        view
        returns (bool isOperator)
    {
        return state.operators[caller] || isAdmin(state, caller);  
    }

    /**
     * @notice Require owner access
     * @param state The security state storage
     * @param caller The address to check 
     */
    function requireOwner(SecurityState storage state, address caller)
        if (!isOwner(state, caller)) {
            revert UnauthorizedAccess(caller, OWNER_ROLE); 
        }
    }

    /**
     * @notice Require admin access
     * @param state The security state storage
     * @param caller The address to check
     */
    function requireAdmin(SecurityState storage state, address caller) internal view {
        if (!isOperator(state, caller)) {
            revert UnauthorizedAccess(caller, OPERATOR_ROLE); 
        }
    }

    /**
     * @notice Require contract not to be paused
     * @param state The security state storage 
     */
    function requireNotPaused(SecurityState storage state) internal view {
        if (state.paused) revert ContractPaused(); 
    }

    /**
     * @notice Require contract to be paused
     * @param state The security state storage 
     */
    function requirePaused(SecurityState storage state) internal view {
        if (!state.paused) revert ContractNotPaused(); 
    }

    /**
     * @notice Require contract to be initialized
     * @param state The security state storage 
     */
    function requireInitialized(SecurityState storage state) internal view {
        if (!state.initialized) revert NotInitialized();  
    }

    /**
     * @notice Transfer ownership
     * @param state The security state storage
     * @param caller The caller address
     * @param newOwner The new owner address 
     */
    function transferOwnership(
        SecurityState storage state,
        address caller,
        address newOwner 
    ) internal {
        requireOwner(state, caller);
        if (newOwner == address(0)) revert InvalidAddress(newOwner);

        address previousOwner = state.owner;
        state.owner = newOwner;

        emit OwnershipTransferred(previousOwner, newOwner); 
    }

    /**
     * @notice Add an admin
     * @param state The security state storage
     * @param caller The caller address
     * @param admin The admin address to add 
     */
    function addAdmin(
        SecurityState storage state,
        address caller,
        address admin 
    ) internal {
        requireOwner(state, caller);
        if (admin == address(0)) revert InvalidAddress(admin);
        if (admin == caller) revert SelfRoleModification();

        state.admins[admin] = true;
        emit AdminAdded(admin, caller); 
    }

    /**
     * @notice Remove an admin
     * @param state The security state storage
     * @param caller The caller address
     * @param admin The admin address to remove 
     */
    function removeAdmin(
        SecurityState storage state,
        address caller,
        address admin 
    ) internal {
        requireOwner(state, caller);
        if (admin == caller) revert SelfRoleModification();

        state.admins[admin] = false;
        emit AdminRemoved(admin, caller); 
    }

    /**
     * @notice Add an operator
     * @param state The security state storage
     * @param caller The caller address
     * @param operator The operator address to add 
     */
    function addOperator(
        SecurityState storage state,
        address caller,
        address operator 
    ) internal {
        requireAdmin(state, caller);
        if (operator == address(0)) revert InvalidAddress(operator);

        state.operators[operator] = true;
        emit OperatorAdded(operator, caller); 
    }

    /**
     * @notice Remove an operator
     * @param state The security state storage
     * @param caller The caller address
     * @param operator The operator address to remove 
     */
    function removeOperator(
        SecurityState storage state,
        address caller,
        address operator 
    ) internal {
        requireAdmin(state, caller);

        state.operators[operator] = false;
        emit OperatorRemoved(operator, caller); 
    }

    /**
     * @notice Pause the contract
     * @param state The security state storage
     * @param caller The caller address 
     */
    function pause(SecurityState storage state, address caller) internal {
        requireAdmin(state, caller);
        requireNotPaused(state);

        state.paused = true;
        emit Paused(caller); 
    }

    /**
     * @notice Unpause the contract
     * @param state The security state storage
     * @param caller The caller address 
     */
    function unpause(SecurityState storage state, address caller) internal {
        requireAdmin(state, caller);
        requirePaused(state);

        state.paused = false;
        emit Unpaused(caller); 
    }

    /**
     * @notice Get and increment nonce for replay protection
     * @param state The security state storage
     * @return nonce The current nonce
     */
    function useNonce(SecurityState storage state) internal returns (uint256 nonce) {
        nonce = state.nonce;
        state.nonce++;
    }

    /**
     * @notice Validate address is not zero
     * @param addr The address to validate 
     */
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert InvalidAddress(addr); 
    }

    /**
     * @notice Check if contract has code at address
     * @param addr The address to check
     * @return hasCode True if address has contract code 
     */
    function hasCode(address addr) internal view returns (bool hasCode) {
        uint256 size;
        assembly {
            size := extcodesize(addr) 
        }
        hasCode = size > 0;
    }

    /**
     * @notice Generate a unique hash for replay protection
     * @param state The security state storage
     * @param data The data to hash
     * @return hash The unique hash 
     */
    function generateUniqueHash(
        SecurityState storage state,
        bytes memory data 
    ) internal returns (bytes32 hash) {
        uint256 nonce = useNonce(state);
        hash = keccak256(abi.encodePacked(data, nonce, block.timestamp, block.chainid));
    }
}