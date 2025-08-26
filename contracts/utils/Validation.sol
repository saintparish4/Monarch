// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title BaseValidation
 * @dev Input validation utilities for Base applications
 * @author Monarch Contracts Team  
 */
library BaseValidation {
    /// @dev Custom errors for gas efficiency
    error InvalidLength();
    error InvalidRange();
    error InvalidFormat();
    error InvalidPercentage();
    error InvalidTimestamp();
    error InvalidDuration();
    error ArrayLengthMismatch();
    error EmptyArray();
    error DuplicateEntry();

    /// @dev Constants for validation
    uint256 public constant MAX_BPS = 10000; // 100%
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant MAX_DURATION = 365 days;
    uint256 public constant MAX_STRING_LENGTH = 256;

    /**
     * @dev Validate string length
     * @param str String to Validate
     * @param minLength Minimum length
     * @param maxLength Maximum length 
     */
    function validateStringLength(
        string memory str,
        uint256 minLength,
        uint256 maxLength
    ) internal pure {
        uint256 length = bytes(str).length;
        if (length < minLength || length > maxLength) {
            revert InvalidLength();
        }
    }

    /**
     * @dev Validate that string is not empty
     * @param str String to validate
     */
    function validateNonEmptyString(string memory str) internal pure {
        if (bytes(str).length == 0) revert InvalidLength();
    }

    /**
     * @dev Validate percentage in basis points
     * @param bps Basis points to validate
     */
    function validateBasisPoints(uint256 bps) internal pure {
        if (bps > MAX_BPS) revert InvalidPercentage();
    }

    /**
     * @dev Validate value is within range (inclusive)
     * @param value Value to validate
     * @param min Minimum value
     * @param max Maximum value
     */
    function validateRange(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure {
        if (value < min || value > max) revert InvalidRange();
    }

    /**
     * @dev Validate timestamp is in the future
     * @param timestamp Timestamp to validate
     */
    function validateFutureTimestamp(uint256 timestamp) internal view {
        if (timestamp <= block.timestamp) revert InvalidTimestamp();
    }

    /**
     * @dev Validate timestamp is in the past
     * @param timestamp Timestamp to validate
     */
    function validatePastTimestamp(uint256 timestamp) internal view {
        if (timestamp >= block.timestamp) revert InvalidTimestamp();
    }

    /**
     * @dev Validate duration is within acceptable range
     * @param duration Duration to validate in seconds
     */
    function validateDuration(uint256 duration) internal pure {
        if (duration < MIN_DURATION || duration > MAX_DURATION) {
            revert InvalidDuration();
        }
    }

    /**
     * @dev Validate array is not empty
     * @param array Array to validate
     */
    function validateNonEmptyArray(uint256[] memory array) internal pure {
        if (array.length == 0) revert EmptyArray();
    }

    /**
     * @dev Validate address array is not empty
     * @param array Array to validate
     */
    function validateNonEmptyAddressArray(address[] memory array) internal pure {
        if (array.length == 0) revert EmptyArray();
    }

    /**
     * @dev Validate two arrays have the same length
     * @param array1 First array
     * @param array2 Second array
     */
    function validateArrayLengths(
        uint256[] memory array1,
        uint256[] memory array2
    ) internal pure {
        if (array1.length != array2.length) revert ArrayLengthMismatch();
    }

    /**
     * @dev Validate address and uint256 arrays have same length
     * @param addresses Address array
     * @param values Values array
     */
    function validateArrayLengths(
        address[] memory addresses,
        uint256[] memory values
    ) internal pure {
        if (addresses.length != values.length) revert ArrayLengthMismatch();
    }

    /**
     * @dev Validate array has no duplicate addresses
     * @param addresses Array to validate
     */
    function validateNoDuplicateAddresses(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; ) {
            for (uint256 j = i + 1; j < addresses.length; ) {
                if (addresses[i] == addresses[j]) revert DuplicateEntry();
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /**
     * @dev Validate handle format (alphanumeric + underscore, 3-32 chars)
     * @param handle Handle string to validate
     */
    function validateHandle(string memory handle) internal pure {
        bytes memory handleBytes = bytes(handle);
        uint256 length = handleBytes.length;
        
        // Check length
        if (length < 3 || length > 32) revert InvalidLength();
        
        // Check first character is not underscore
        if (handleBytes[0] == 0x5f) revert InvalidFormat(); // underscore
        
        // Validate each character
        for (uint256 i = 0; i < length; ) {
            bytes1 char = handleBytes[i];
            
            // Allow: a-z, A-Z, 0-9, underscore
            if (!(
                (char >= 0x61 && char <= 0x7a) || // a-z
                (char >= 0x41 && char <= 0x5a) || // A-Z  
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char == 0x5f)                     // underscore
            )) {
                revert InvalidFormat();
            }
            
            unchecked { ++i; }
        }
    }

    /**
     * @dev Validate email format (basic validation)
     * @param email Email string to validate
     */
    function validateEmail(string memory email) internal pure {
        bytes memory emailBytes = bytes(email);
        uint256 length = emailBytes.length;
        
        if (length < 5 || length > 254) revert InvalidLength();
        
        bool hasAt = false;
        bool hasDot = false;
        uint256 atIndex = 0;
        
        // Find @ symbol
        for (uint256 i = 0; i < length; ) {
            if (emailBytes[i] == 0x40) { // @
                if (hasAt) revert InvalidFormat(); // Multiple @
                hasAt = true;
                atIndex = i;
            }
            unchecked { ++i; }
        }
        
        if (!hasAt || atIndex == 0 || atIndex == length - 1) {
            revert InvalidFormat();
        }
        
        // Check for dot after @
        for (uint256 i = atIndex + 1; i < length; ) {
            if (emailBytes[i] == 0x2e) { // .
                hasDot = true;
                break;
            }
            unchecked { ++i; }
        }
        
        if (!hasDot) revert InvalidFormat();
    }

    /**
     * @dev Validate URL format (basic validation)
     * @param url URL string to validate
     */
    function validateURL(string memory url) internal pure {
        bytes memory urlBytes = bytes(url);
        uint256 length = urlBytes.length;
        
        if (length < 10 || length > 2048) revert InvalidLength();
        
        // Check for http:// or https://
        if (length < 8) revert InvalidFormat();
        
        bool validProtocol = false;
        
        // Check for https://
        if (length >= 8 && 
            urlBytes[0] == 0x68 && // h
            urlBytes[1] == 0x74 && // t  
            urlBytes[2] == 0x74 && // t
            urlBytes[3] == 0x70 && // p
            urlBytes[4] == 0x73 && // s
            urlBytes[5] == 0x3a && // :
            urlBytes[6] == 0x2f && // /
            urlBytes[7] == 0x2f    // /
        ) {
            validProtocol = true;
        }
        
        // Check for http://
        if (!validProtocol && length >= 7 &&
            urlBytes[0] == 0x68 && // h
            urlBytes[1] == 0x74 && // t
            urlBytes[2] == 0x74 && // t  
            urlBytes[3] == 0x70 && // p
            urlBytes[4] == 0x3a && // :
            urlBytes[5] == 0x2f && // /
            urlBytes[6] == 0x2f    // /
        ) {
            validProtocol = true;
        }
        
        if (!validProtocol) revert InvalidFormat();
    }

    /**
     * @dev Validate IPFS hash format
     * @param hash IPFS hash string to validate
     */
    function validateIPFSHash(string memory hash) internal pure {
        bytes memory hashBytes = bytes(hash);
        uint256 length = hashBytes.length;
        
        // IPFS v0 hashes are 46 characters starting with "Qm"
        // IPFS v1 hashes are 59 characters starting with "ba" 
        if (length == 46) {
            if (hashBytes[0] != 0x51 || hashBytes[1] != 0x6d) { // "Qm"
                revert InvalidFormat();
            }
        } else if (length == 59) {
            if (hashBytes[0] != 0x62 || hashBytes[1] != 0x61) { // "ba"
                revert InvalidFormat();
            }
        } else {
            revert InvalidLength();
        }
    }

    /**
     * @dev Batch validate addresses are not zero
     * @param addresses Array of addresses to validate
     */
    function validateAddressesNotZero(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; ) {
            if (addresses[i] == address(0)) revert InvalidFormat();
            unchecked { ++i; }
        }
    }

    /**
     * @dev Validate fee structure
     * @param fees Array of fee percentages in basis points
     */
    function validateFees(uint256[] memory fees) internal pure {
        uint256 totalFees = 0;
        
        for (uint256 i = 0; i < fees.length; ) {
            validateBasisPoints(fees[i]);
            totalFees += fees[i];
            unchecked { ++i; }
        }
        
        // Total fees cannot exceed 100%
        if (totalFees > MAX_BPS) revert InvalidPercentage();
    }
}