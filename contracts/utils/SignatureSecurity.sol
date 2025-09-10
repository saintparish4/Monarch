// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title SignatureSecurity
 * @dev Enhanced signature validation utilities implementing 2025 security best practices
 * @author BlueSky Labs Security Team
 */
library SignatureSecurity {
    using ECDSA for bytes32;

    // Custom errors for gas efficiency
    error InvalidSignature();
    error SignatureMalleable();
    error SignatureReplay();
    error InvalidSignatureFormat();
    error RateLimitExceeded();
    error KeyRevoked();
    error TimestampExpired();
    error InvalidNonce();

    // Constants for security validation
    uint256 public constant MAX_SIGNATURE_AGE = 1 hours; // Maximum age for signatures
    uint256 public constant MAX_NONCE_GAP = 1000; // Maximum nonce gap allowed
    uint256 public constant SIGNATURE_RATE_LIMIT = 100; // Max signatures per hour
    uint256 public constant SIGNATURE_RATE_WINDOW = 1 hours;

    // Signature validation result structure
    struct ValidationResult {
        address signer;
        bool isValid;
        string reason;
        uint256 timestamp;
    }

    // Rate limiting structure
    struct RateLimitData {
        uint256 count;
        uint256 windowStart;
        uint256 lastUpdate;
    }

    // Events for security monitoring
    event SignatureValidated(address indexed signer, bool success, string reason);
    event ReplayAttackDetected(address indexed attacker, bytes32 indexed signatureHash);
    event RateLimitExceeded(address indexed signer, uint256 count);

    /**
     * @dev Comprehensive signature validation with 2025 security standards
     */
    function validateSignatureComprehensive(
        bytes32 messageHash,
        bytes calldata signature,
        address expectedSigner,
        uint256 nonce,
        uint256 currentNonce,
        mapping(bytes32 => bool) storage usedSignatures,
        mapping(address => RateLimitData) storage rateLimits
    ) internal returns (ValidationResult memory result) {
        result.timestamp = block.timestamp;

        // 1. Format validation
        if (!_validateSignatureFormat(signature)) {
            result.reason = "Invalid signature format";
            emit SignatureValidated(expectedSigner, false, result.reason);
            return result;
        }

        // 2. Malleability check
        if (_isSignatureMalleable(signature)) {
            result.reason = "Signature malleable";
            emit SignatureValidated(expectedSigner, false, result.reason);
            return result;
        }

        // 3. Replay protection
        bytes32 signatureHash = keccak256(signature);
        if (usedSignatures[signatureHash]) {
            result.reason = "Signature replay detected";
            emit ReplayAttackDetected(expectedSigner, signatureHash);
            emit SignatureValidated(expectedSigner, false, result.reason);
            return result;
        }

        // 4. Nonce validation
        if (!_validateNonce(nonce, currentNonce)) {
            result.reason = "Invalid nonce";
            emit SignatureValidated(expectedSigner, false, result.reason);
            return result;
        }

        // 5. Rate limiting
        if (!_checkRateLimit(expectedSigner, rateLimits)) {
            result.reason = "Rate limit exceeded";
            emit RateLimitExceeded(expectedSigner, rateLimits[expectedSigner].count);
            emit SignatureValidated(expectedSigner, false, result.reason);
            return result;
        }

        // 6. Signature recovery and validation
        try ECDSA.recover(messageHash, signature) returns (address recovered) {
            result.signer = recovered;
            
            if (recovered == address(0)) {
                result.reason = "Invalid signature recovery";
                emit SignatureValidated(expectedSigner, false, result.reason);
                return result;
            }

            if (recovered != expectedSigner) {
                result.reason = "Signer mismatch";
                emit SignatureValidated(expectedSigner, false, result.reason);
                return result;
            }

            result.isValid = true;
            result.reason = "Valid signature";
            emit SignatureValidated(expectedSigner, true, result.reason);

        } catch {
            result.reason = "Signature recovery failed";
            emit SignatureValidated(expectedSigner, false, result.reason);
        }
    }

    /**
     * @dev Validate signature format according to ECDSA standards
     */
    function _validateSignatureFormat(bytes calldata signature) internal pure returns (bool) {
        // ECDSA signature must be exactly 65 bytes
        if (signature.length != 65) {
            return false;
        }

        // Check that signature is not all zeros
        bool allZero = true;
        for (uint256 i = 0; i < 65; i++) {
            if (signature[i] != 0) {
                allZero = false;
                break;
            }
        }
        
        return !allZero;
    }

    /**
     * @dev Check for signature malleability vulnerability
     */
    function _isSignatureMalleable(bytes calldata signature) internal pure returns (bool) {
        if (signature.length != 65) return true;

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        // Check for signature malleability
        // s value must be <= secp256k1n/2 to prevent malleability
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return true;
        }

        // v must be 27 or 28
        if (v != 27 && v != 28) {
            return true;
        }

        return false;
    }

    /**
     * @dev Enhanced nonce validation with gap checking
     */
    function _validateNonce(uint256 nonce, uint256 currentNonce) internal pure returns (bool) {
        // Nonce must be >= current nonce
        if (nonce < currentNonce) {
            return false;
        }

        // Nonce gap must be reasonable (prevent nonce manipulation)
        if (nonce > currentNonce + MAX_NONCE_GAP) {
            return false;
        }

        return true;
    }

    /**
     * @dev Rate limiting for signature validation
     */
    function _checkRateLimit(
        address signer,
        mapping(address => RateLimitData) storage rateLimits
    ) internal returns (bool) {
        RateLimitData storage limit = rateLimits[signer];
        
        // Reset window if expired
        if (block.timestamp >= limit.windowStart + SIGNATURE_RATE_WINDOW) {
            limit.count = 0;
            limit.windowStart = block.timestamp;
        }

        // Check if limit exceeded
        if (limit.count >= SIGNATURE_RATE_LIMIT) {
            return false;
        }

        // Increment counter
        limit.count++;
        limit.lastUpdate = block.timestamp;

        return true;
    }

    /**
     * @dev Generate secure message hash with timestamp
     */
    function generateSecureHash(
        bytes32 messageHash,
        uint256 timestamp,
        uint256 nonce,
        address sender
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            messageHash,
            timestamp,
            nonce,
            sender
        ));
    }

    /**
     * @dev Validate timestamp is within acceptable range
     */
    function validateTimestamp(uint256 timestamp) internal view returns (bool) {
        // Timestamp must not be too old
        if (block.timestamp - timestamp > MAX_SIGNATURE_AGE) {
            return false;
        }

        // Timestamp must not be too far in the future
        if (timestamp > block.timestamp + 300) { // 5 minutes tolerance
            return false;
        }

        return true;
    }

    /**
     * @dev Create deterministic signature hash for replay protection
     */
    function createSignatureHash(
        bytes32 messageHash,
        uint256 nonce,
        uint256 timestamp,
        address sender
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "BaseSmartAccount",
            messageHash,
            nonce,
            timestamp,
            sender
        ));
    }

    /**
     * @dev Verify signature with additional security checks
     */
    function verifySignatureWithSecurity(
        bytes32 messageHash,
        bytes calldata signature,
        address expectedSigner,
        uint256 nonce,
        uint256 timestamp
    ) internal view returns (bool) {
        // Validate timestamp
        if (!validateTimestamp(timestamp)) {
            return false;
        }

        // Validate signature format
        if (!_validateSignatureFormat(signature)) {
            return false;
        }

        // Check malleability
        if (_isSignatureMalleable(signature)) {
            return false;
        }

        // Recover and verify signer
        try ECDSA.recover(messageHash, signature) returns (address signer) {
            return signer == expectedSigner && signer != address(0);
        } catch {
            return false;
        }
    }

    /**
     * @dev Batch signature validation for multiple signatures
     */
    function validateBatchSignatures(
        bytes32[] calldata messageHashes,
        bytes[] calldata signatures,
        address[] calldata expectedSigners
    ) internal pure returns (bool[] memory results) {
        require(
            messageHashes.length == signatures.length && 
            signatures.length == expectedSigners.length,
            "Array length mismatch"
        );

        results = new bool[](signatures.length);

        for (uint256 i = 0; i < signatures.length; i++) {
            try ECDSA.recover(messageHashes[i], signatures[i]) returns (address signer) {
                results[i] = (signer == expectedSigners[i] && signer != address(0));
            } catch {
                results[i] = false;
            }
        }
    }

    /**
     * @dev Get signature security score (0-100)
     */
    function getSignatureSecurityScore(
        bytes calldata signature,
        uint256 timestamp,
        uint256 nonce,
        uint256 currentNonce
    ) internal view returns (uint256 score) {
        score = 100; // Start with perfect score

        // Deduct points for format issues
        if (!_validateSignatureFormat(signature)) {
            score -= 50;
        }

        // Deduct points for malleability
        if (_isSignatureMalleable(signature)) {
            score -= 30;
        }

        // Deduct points for timestamp issues
        if (!validateTimestamp(timestamp)) {
            score -= 20;
        }

        // Deduct points for nonce issues
        if (!_validateNonce(nonce, currentNonce)) {
            score -= 25;
        }

        // Ensure score doesn't go below 0
        if (score > 100) {
            score = 0;
        }
    }
}
