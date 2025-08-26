// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title BaseSecurity
 * @dev Security utilities and patterns for Base applications
 * @author Monarch Contracts Team 
 */
library BaseSecurity {
    /// @dev Custom errors for gas efficiency
    error Unauthorized();
    error Paused();
    error NotPaused();
    error InvalidAddress();
    error InvalidAmount();
    error TimeLockNotMet();
    error AlreadyExecuted();
    error InvalidSignature();

    /// @dev Role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Validate that address is not zero
     * @param addr Address to validate 
     */
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert InvalidAddress(); 
    }
    /**
     * @dev Validate that amount is greater than zero
     * @param amount Amount to validate 
     */
    function validateAmount(uint256 amount) internal pure {
        if (amount == 0) revert InvalidAmount(); 
    }

    /**
     * @dev Validate multiple addresses are not zero
     * @param addresses Array of addresses to validate 
     */
    function validateAddresses(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; ) {
            validateAddress(addresses[i]);
            unchecked { ++i }    
        }
    }

    /**
     * @dev Check if caller is authorized for the given role
     * @param hasRole Mapping to check role membership
     * @param role Role to check
     * @param account Account to check
     */
    function requireRole(
        mapping(bytes32 => mapping(address => bool)) storage hasRole,
        bytes32 role,
        address account 
    ) internal view {
        if (!hasRole[role][account]) revert Unauthorized(); 
    }

    /**
     * @dev Check if contract is not paused
     * @param paused Current pause state 
     */
    function requireNotPaused(bool paused) internal pure {
        if (paused) revert Paused();  
    }

    /**
     * @dev Check if contract is paused
     * @param paused Current pause state 
     */
    function requirePaused(bool paused) internal pure {
        if (!paused) revert NotPaused();   
    }

    /**
     * @dev Check if timelock period has passed
     * @param timestamp Target timestamp 
     */
    function requireTimeLock(uint256 timestamp) internal view {
        if (block.timestamp < timestamp) revert TimeLockNotMet();   
    }

    /**
     * @dev Generate a unique ID based on input parameters
     * @param creator Creator address
     * @param nonce Unique nonce
     * @param data Additional data
     * @return Unique Identifier 
     */
    function generateId(
        address creator,
        uint256 nonce,
        bytes memory data 
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(creator, nonce, data)); 
    }

    /**
     * @dev Verify ECDSA signature
     * @param hash Message hash
     * @param signature Signature bytes
     * @param signer Expected signer address
     * @return True if signature is valid 
     */
    function verifySignature(
        bytes32 hash,
        bytes memory signature,
        address signer 
    ) internal pure returns (bool) {
        if (signature.length != 65) return false;

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96))) 
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) return false;

        address recovered = ecrecover(hash, v, r, s);
        return recovered != address(0) && recovered == signer; 
    }

    /**
     * @dev Create EIP-712 compliant hash
     * @param domainSeparator Domain Separator
     * @param structHash Struct hash
     * @return EIP-712 hash 
     */
    function hashTypedData(
        bytes32 domainSeparator,
        bytes32 structHash 
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)); 
    }

    /**
     * @dev Safe transfer of ETH
     * @param to Recipient address
     * @param amount Amount to transfer 
     */
    function safeTransferETH(address to, uint256 amount) internal {
        validateAddress(to);
        validateAmount(amount);

        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert("ETH transfer failed");  
    }

    /**
     * @dev Check if transaction is not being replayed
     * @param used Mapping of used nonces
     * @param nonce Nonce to check 
     */
    function requireNonceNotUsed(
        mapping(uint256 => bool) storage used,
        uint256 nonce 
    ) internal view {
        if (used[nonce]) revert AlreadyExecuted();  
    }

    /**
     * @dev Mark nonce as used
     * @param used Mapping of used nonces
     * @param nonce Nonce to mark as used 
     */
    function markNonceUsed(
        mapping(uint256 => bool) storage used,
        uint256 nonce 
    ) internal {
        used[nonce] = true;  
    }

    /**
     * @dev Rate limiting check
     * @param lastAction Timestamp of last action
     * @param cooldown Required cooldown period 
     */
    function requireCooldown(uint256 lastAction, uint256 cooldown) internal view {
        if (block.timestamp < lastAction + cooldown) revert TimeLockNotMet();  
    }
}

/**
 * @title Pausable
 * @dev Base contract with pause functionality 
 */
abstract contract Pausable {
    using BaseSecurity for bool;

    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        _paused.requireNotPaused();
        _; 
    }

    modifier whenPaused() {
        _paused.requirePaused();
        _;  
    }

    function paused() public view returns (bool) {
        return _paused;  
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);   
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);   
    }
}

/**
 * @title ReentrancyGuard
 * @dev Gas-optimized reentrancy protection 
 */
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;   
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert BaseSecurity.AlreadyExecuted();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;   
    }
}