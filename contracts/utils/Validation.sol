// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Validation
 * @dev Input validation utilities for Base applications
 * @author BlueSky Labs Contracts Team
 */
library Validation {
    // Custom errors
    error InvalidInput();
    error ValueTooLarge();
    error ValueTooSmall();
    error InvalidStringLength();
    error InvalidCharacter();
    error InvalidFormat();
    error InvalidRange();

    // Constants for validation
    uint256 public constant MAX_STRING_LENGTH = 1000;
    uint256 public constant MAX_ARRAY_LENGTH = 1000;
    uint256 public constant MAX_BASIS_POINTS = 10000; // 100%

    /**
     * @dev Validates that a value is within a specified range
     */
    function validateRange(uint256 value, uint256 minValue, uint256 maxValue) internal pure {
        if (value < minValue) revert ValueTooSmall();
        if (value > maxValue) revert ValueTooLarge();
    }

    /**
     * @dev Validates that a percentage is valid (0-10000 basis points)
     */
    function validatePercentage(uint256 percentage) internal pure {
        if (percentage > MAX_BASIS_POINTS) {
            revert ValueTooLarge();
        }
    }

    /**
     * @dev Validates string length
     */
    function validateStringLength(string memory str, uint256 minLength, uint256 maxLength) internal pure {
        bytes memory strBytes = bytes(str);
        if (strBytes.length < minLength || strBytes.length > maxLength) {
            revert InvalidStringLength();
        }
    }

    /**
     * @dev Validates that a string is not empty
     */
    function validateNonEmptyString(string memory str) internal pure {
        if (bytes(str).length == 0) {
            revert InvalidStringLength();
        }
    }

    /**
     * @dev Validates array length
     */
    function validateArrayLength(uint256 length, uint256 maxLength) internal pure {
        if (length == 0) revert InvalidInput();
        if (length > maxLength) revert ValueTooLarge();
    }

    /**
     * @dev Validates that arrays have matching lengths
     */
    function validateArrayLengthsMatch(uint256 length1, uint256 length2) internal pure {
        if (length1 != length2) {
            revert InvalidInput();
        }
    }

    /**
     * @dev Validates address is not zero
     */
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert InvalidInput();
        }
    }

    /**
     * @dev Validates multiple addresses are not zero
     */
    function validateAddresses(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            validateAddress(addresses[i]);
        }
    }

    /**
     * @dev Validates amount is greater than zero
     */
    function validateAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert ValueTooSmall();
        }
    }

    /**
     * @dev Validates timestamp is in the future
     */
    function validateFutureTimestamp(uint256 timestamp) internal view {
        if (timestamp <= block.timestamp) {
            revert InvalidInput();
        }
    }

    /**
     * @dev Validates timestamp is reasonable (not too far in future)
     */
    function validateReasonableTimestamp(uint256 timestamp) internal view {
        // Allow up to 10 years in the future
        uint256 maxFuture = block.timestamp + (10 * 365 days);
        if (timestamp > maxFuture) {
            revert ValueTooLarge();
        }
    }

    /**
     * @dev Validates duration is within acceptable range
     */
    function validateDuration(uint256 duration, uint256 minDuration, uint256 maxDuration) internal pure {
        validateRange(duration, minDuration, maxDuration);
    }

    /**
     * @dev Validates handle format for social applications
     * Rules: 3-32 characters, alphanumeric + underscore, no leading/trailing underscore
     */
    function validateHandle(string memory handle) internal pure {
        bytes memory handleBytes = bytes(handle);
        uint256 length = handleBytes.length;

        // Check length
        if (length < 3 || length > 32) {
            revert InvalidStringLength();
        }

        // Check first and last character are not underscore
        if (handleBytes[0] == "_" || handleBytes[length - 1] == "_") {
            revert InvalidCharacter();
        }

        // Check all characters are valid
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = handleBytes[i];
            if (
                !((char >= "a" && char <= "z") ||
                    (char >= "A" && char <= "Z") ||
                    (char >= "0" && char <= "9") ||
                    char == "_")
            ) {
                revert InvalidCharacter();
            }
        }
    }

    /**
     * @dev Validates email format (basic validation)
     */
    function validateEmail(string memory email) internal pure {
        bytes memory emailBytes = bytes(email);
        uint256 length = emailBytes.length;

        if (length < 5 || length > 254) {
            revert InvalidStringLength();
        }

        bool hasAt = false;
        bool hasDot = false;
        uint256 atPosition = 0;

        for (uint256 i = 0; i < length; i++) {
            bytes1 char = emailBytes[i];

            if (char == "@") {
                if (hasAt || i == 0 || i == length - 1) {
                    revert InvalidFormat();
                }
                hasAt = true;
                atPosition = i;
            } else if (char == "." && hasAt && i > atPosition + 1) {
                hasDot = true;
            }
        }

        if (!hasAt || !hasDot) {
            revert InvalidFormat();
        }
    }

    /**
     * @dev Validates URL format (basic validation)
     */
    function validateURL(string memory url) internal pure {
        bytes memory urlBytes = bytes(url);
        uint256 length = urlBytes.length;

        if (length < 7 || length > 2083) {
            // Min: "http://" or "https://"
            revert InvalidStringLength();
        }

        // Check for protocol
        bool validProtocol = false;

        // Check for "http://"
        if (length >= 7) {
            if (
                urlBytes[0] == "h" &&
                urlBytes[1] == "t" &&
                urlBytes[2] == "t" &&
                urlBytes[3] == "p" &&
                urlBytes[4] == ":" &&
                urlBytes[5] == "/" &&
                urlBytes[6] == "/"
            ) {
                validProtocol = true;
            }
        }

        // Check for "https://"
        if (!validProtocol && length >= 8) {
            if (
                urlBytes[0] == "h" &&
                urlBytes[1] == "t" &&
                urlBytes[2] == "t" &&
                urlBytes[3] == "p" &&
                urlBytes[4] == "s" &&
                urlBytes[5] == ":" &&
                urlBytes[6] == "/" &&
                urlBytes[7] == "/"
            ) {
                validProtocol = true;
            }
        }

        if (!validProtocol) {
            revert InvalidFormat();
        }
    }

    /**
     * @dev Validates IPFS hash format
     */
    function validateIPFSHash(string memory hash) internal pure {
        bytes memory hashBytes = bytes(hash);
        uint256 length = hashBytes.length;

        // CIDv0: 46 characters starting with "Qm"
        // CIDv1: typically 59 characters starting with "bafy" (base32)
        if (length == 46) {
            // Validate CIDv0
            if (hashBytes[0] != "Q" || hashBytes[1] != "m") {
                revert InvalidFormat();
            }

            // Check all characters are base58
            for (uint256 i = 2; i < length; i++) {
                bytes1 char = hashBytes[i];
                if (
                    !((char >= "1" && char <= "9") ||
                        (char >= "A" && char <= "H") ||
                        (char >= "J" && char <= "N") ||
                        (char >= "P" && char <= "Z") ||
                        (char >= "a" && char <= "k") ||
                        (char >= "m" && char <= "z"))
                ) {
                    revert InvalidCharacter();
                }
            }
        } else if (length == 59) {
            // Validate CIDv1
            if (!(hashBytes[0] == "b" && hashBytes[1] == "a" && hashBytes[2] == "f" && hashBytes[3] == "y")) {
                revert InvalidFormat();
            }
        } else {
            revert InvalidStringLength();
        }
    }

    /**
     * @dev Validates metadata format for NFTs/posts
     */
    function validateMetadata(bytes32 metadata) internal pure {
        if (metadata == bytes32(0)) {
            revert InvalidInput();
        }
    }

    /**
     * @dev Validates token symbol format
     */
    function validateTokenSymbol(string memory symbol) internal pure {
        bytes memory symbolBytes = bytes(symbol);
        uint256 length = symbolBytes.length;

        if (length < 2 || length > 11) {
            revert InvalidStringLength();
        }

        // Only uppercase letters and numbers
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = symbolBytes[i];
            if (!((char >= "A" && char <= "Z") || (char >= "0" && char <= "9"))) {
                revert InvalidCharacter();
            }
        }
    }

    /**
     * @dev Validates token name format
     */
    function validateTokenName(string memory name) internal pure {
        validateStringLength(name, 1, 50);

        bytes memory nameBytes = bytes(name);

        // Check for valid characters (letters, numbers, spaces, hyphens)
        for (uint256 i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            if (
                !((char >= "a" && char <= "z") ||
                    (char >= "A" && char <= "Z") ||
                    (char >= "0" && char <= "9") ||
                    char == " " ||
                    char == "-")
            ) {
                revert InvalidCharacter();
            }
        }
    }

    /**
     * @dev Validates signature format
     */
    function validateSignature(bytes memory signature) internal pure {
        if (signature.length != 65) {
            revert InvalidInput();
        }
    }

    /**
     * @dev Validates price is reasonable (not too high)
     */
    function validatePrice(uint256 price, uint256 maxPrice) internal pure {
        if (price > maxPrice) {
            revert ValueTooLarge();
        }
    }

    /**
     * @dev Validates slippage tolerance
     */
    function validateSlippage(uint256 slippage) internal pure {
        // Max 50% slippage (5000 basis points)
        if (slippage > 5000) {
            revert ValueTooLarge();
        }
    }

    /**
     * @dev Validates gas limit is reasonable
     */
    function validateGasLimit(uint256 gasLimit) internal pure {
        // Min 21000, max 15M (Base block gas limit)
        validateRange(gasLimit, 21000, 15000000);
    }

    /**
     * @dev Validates fee rate is reasonable
     */
    function validateFeeRate(uint256 feeRate) internal pure {
        // Max 10% fee (1000 basis points)
        if (feeRate > 1000) {
            revert ValueTooLarge();
        }
    }

    /**
     * @dev Comprehensive input validation for user operations
     */
    function validateUserOperation(address sender, uint256 callGasLimit, uint256 maxFeePerGas) internal pure {
        validateAddress(sender);
        validateGasLimit(callGasLimit);
        validateAmount(maxFeePerGas);
        // Nonce can be 0, so no validation needed
    }

    /**
     * @dev Validates payment plan parameters
     */
    function validatePaymentPlan(string memory name, uint256 amount, uint256 period) internal pure {
        validateNonEmptyString(name);
        validateStringLength(name, 1, 100);
        validateAmount(amount);

        // Period must be at least 1 hour
        if (period < 1 hours) {
            revert ValueTooSmall();
        }

        // Period must be less than 10 years
        if (period > 10 * 365 days) {
            revert ValueTooLarge();
        }
    }
}
