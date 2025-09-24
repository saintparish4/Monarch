// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Constants.sol";

/**
 * @title SignatureSecurity
 * @dev Signature validation and security utilities for BaseKit
 * @notice Provides secure signature verification with replay protection
 */
library SignatureSecurity {
    // Signature types
    enum SignatureType {
        EOA,            // Externally Owned Account signature
        CONTRACT,       // EIP-1271 contract signature
        ETH_SIGN,       // Ethereum signed message
        EIP712          // EIP-712 typed data signature
    }

    // Signature data structure
    struct SignatureData {
        SignatureType sigType;
        bytes signature;
        uint256 validUntil;
        uint256 validAfter;
    }

    // EIP-712 domain data
    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    // Events
    event SignatureValidated(
        address indexed signer,
        bytes32 indexed hash,
        SignatureType sigType,
        bool valid
    );

    // Errors
    error InvalidSignatureLength(uint256 length);
    error InvalidSignatureType(SignatureType sigType);
    error SignatureExpired(uint256 validUntil, uint256 currentTime);
    error SignatureNotYetValid(uint256 validAfter, uint256 currentTime);
    error InvalidRecoveredSigner(address expected, address recovered);
    error ContractSignatureValidationFailed(address contract_);

    /**
     * @notice Validate an ECDSA signature
     * @param hash The hash that was signed
     * @param signature The signature bytes
     * @param expectedSigner The expected signer address
     * @return valid True if signature is valid
     */
    function validateECDSASignature(
        bytes32 hash,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool valid) {
        if (signature.length != Constants.SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // Adjust v if necessary
        if (v < 27) {
            v += 27;
        }

        // Validate signature parameters
        if (!isValidSignatureParameters(r, s, v)) {
            return false;
        }

        address recoveredSigner = ecrecover(hash, v, r, s);
        return recoveredSigner != address(0) && recoveredSigner == expectedSigner;
    }

    /**
     * @notice Validate an EIP-712 signature
     * @param domain The EIP-712 domain
     * @param structHash The hash of the typed data struct
     * @param signature The signature bytes
     * @param expectedSigner The expected signer address
     * @return valid True if signature is valid
     */
    function validateEIP712Signature(
        EIP712Domain memory domain,
        bytes32 structHash,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool valid) {
        bytes32 domainSeparator = hashDomain(domain);
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        return validateECDSASignature(digest, signature, expectedSigner);
    }

    /**
     * @notice Validate an Ethereum signed message signature
     * @param message The original message
     * @param signature The signature bytes
     * @param expectedSigner The expected signer address
     * @return valid True if signature is valid
     */
    function validateEthSignedMessage(
        bytes memory message,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool valid) {
        bytes32 messageHash = keccak256(message);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        return validateECDSASignature(ethSignedHash, signature, expectedSigner);
    }

    /**
     * @notice Validate an EIP-1271 contract signature
     * @param hash The hash that was signed
     * @param signature The signature bytes
     * @param contractSigner The contract that should validate the signature
     * @return valid True if signature is valid
     */
    function validateContractSignature(
        bytes32 hash,
        bytes memory signature,
        address contractSigner
    ) internal view returns (bool valid) {
        // EIP-1271 magic value
        bytes4 magicValue = 0x1626ba7e;

        try IERC1271(contractSigner).isValidSignature(hash, signature) returns (bytes4 returnValue) {
            return returnValue == magicValue;
        } catch {
            return false;
        }
    }

    /**
     * @notice Validate a signature with full context
     * @param hash The hash that was signed
     * @param sigData The signature data including type and timing
     * @param expectedSigner The expected signer address
     * @return valid True if signature is valid
     */
    function validateSignature(
        bytes32 hash,
        SignatureData memory sigData,
        address expectedSigner
    ) internal view returns (bool valid) {
        // Check timing validity
        if (sigData.validUntil != 0 && block.timestamp > sigData.validUntil) {
            revert SignatureExpired(sigData.validUntil, block.timestamp);
        }

        if (sigData.validAfter != 0 && block.timestamp < sigData.validAfter) {
            revert SignatureNotYetValid(sigData.validAfter, block.timestamp);
        }

        // Validate based on signature type
        if (sigData.sigType == SignatureType.EOA || sigData.sigType == SignatureType.EIP712) {
            valid = validateECDSASignature(hash, sigData.signature, expectedSigner);
        } else if (sigData.sigType == SignatureType.ETH_SIGN) {
            // Convert hash to message format for eth_sign
            bytes memory message = abi.encodePacked(hash);
            valid = validateEthSignedMessage(message, sigData.signature, expectedSigner);
        } else if (sigData.sigType == SignatureType.CONTRACT) {
            valid = validateContractSignature(hash, sigData.signature, expectedSigner);
        } else {
            revert InvalidSignatureType(sigData.sigType);
        }

        emit SignatureValidated(expectedSigner, hash, sigData.sigType, valid);
    }

    /**
     * @notice Hash an EIP-712 domain
     * @param domain The domain to hash
     * @return domainSeparator The domain separator hash
     */
    function hashDomain(EIP712Domain memory domain) internal pure returns (bytes32 domainSeparator) {
        domainSeparator = keccak256(
            abi.encode(
                Constants.EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(domain.name)),
                keccak256(bytes(domain.version)),
                domain.chainId,
                domain.verifyingContract
            )
        );
    }

    /**
     * @notice Create a user operation hash for signing
     * @param userOpHash The user operation hash
     * @param entryPoint The entry point address
     * @param chainId The chain ID
     * @return hash The final hash for signing
     */
    function createUserOperationHash(
        bytes32 userOpHash,
        address entryPoint,
        uint256 chainId
    ) internal pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(userOpHash, entryPoint, chainId));
    }

    /**
     * @notice Split signature into r, s, v components
     * @param signature The signature bytes
     * @return r The r component
     * @return s The s component
     * @return v The v component
     */
    function splitSignature(bytes memory signature)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        if (signature.length != Constants.SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }
    }

    /**
     * @notice Check if signature parameters are valid
     * @param r The r component
     * @param s The s component
     * @param v The v component
     * @return valid True if parameters are valid
     */
    function isValidSignatureParameters(bytes32 r, bytes32 s, uint8 v)
        internal
        pure
        returns (bool valid)
    {
        // Check v value
        if (v != 27 && v != 28) {
            return false;
        }

        // Check r and s are not zero
        if (r == 0 || s == 0) {
            return false;
        }

        // Check s is in lower half of curve order (EIP-2)
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return false;
        }

        return true;
    }

    /**
     * @notice Create a meta-transaction hash
     * @param nonce The nonce
     * @param from The sender address
     * @param functionSignature The function signature
     * @param verifyingContract The contract that will verify
     * @return hash The meta-transaction hash
     */
    function createMetaTxHash(
        uint256 nonce,
        address from,
        bytes memory functionSignature,
        address verifyingContract
    ) internal view returns (bytes32 hash) {
        EIP712Domain memory domain = EIP712Domain({
            name: "BaseKitGasless",
            version: "1.0.0",
            chainId: block.chainid,
            verifyingContract: verifyingContract
        });

        bytes32 structHash = keccak256(
            abi.encode(
                Constants.META_TRANSACTION_TYPEHASH,
                nonce,
                from,
                keccak256(functionSignature)
            )
        );

        bytes32 domainSeparator = hashDomain(domain);
        hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

/**
 * @title IERC1271
 * @dev Interface for EIP-1271 signature validation
 */
interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        returns (bytes4 magicValue);
}