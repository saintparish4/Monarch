// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Constants.sol";

/**
 * @title Validation
 * @dev Input validation utilities for BaseKit gasless modules
 * @notice Provides comprehensive validation functions for user operations and parameters
 */
library Validation {
    // Errors
    error InvalidAddress(address addr);
    error InvalidAmount(uint256 amount, uint256 minAmount, uint256 maxAmount);
    error InvalidGasLimit(uint256 gasLimit, uint256 min, uint256 max);
    error InvalidTimeRange(uint256 start, uint256 end);
    error InvalidArrayLength(uint256 length, uint256 expected);
    error InvalidNonce(uint256 nonce, uint256 expected);
    error InvalidCallData(bytes data);
    error InvalidDuration(uint256 duration, uint256 maxDuration);

    /**
     * @notice Validate an address is not zero
     * @param addr The address to validate
     */
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert InvalidAddress(addr);
    }

    /**
     * @notice Validate multiple addresses are not zero
     * @param addresses Array of addresses to validate
     */
    function validateAddresses(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            validateAddress(addresses[i]);
        }
    }

    /**
     * @notice Validate an amount is within bounds
     * @param amount The amount to validate
     * @param minAmount Minimum allowed amount
     * @param maxAmount Maximum allowed amount
     */
    function validateAmount(uint256 amount, uint256 minAmount, uint256 maxAmount) internal pure {
        if (amount < minAmount || amount > maxAmount) {
            revert InvalidAmount(amount, minAmount, maxAmount);
        }
    }

    /**
     * @notice Validate gas limits for user operation
     * @param callGasLimit Gas limit for the main call
     * @param verificationGasLimit Gas limit for verification
     * @param preVerificationGas Pre-verification gas
     */
    function validateUserOpGasLimits(
        uint256 callGasLimit,
        uint256 verificationGasLimit,
        uint256 preVerificationGas
    ) internal pure {
        if (callGasLimit < Constants.MIN_GAS_LIMIT || callGasLimit > Constants.MAX_CALL_GAS_LIMIT) {
            revert InvalidGasLimit(callGasLimit, Constants.MIN_GAS_LIMIT, Constants.MAX_CALL_GAS_LIMIT);
        }

        if (verificationGasLimit > Constants.MAX_VERIFICATION_GAS) {
            revert InvalidGasLimit(verificationGasLimit, 0, Constants.MAX_VERIFICATION_GAS);
        }

        if (preVerificationGas > Constants.MAX_PRE_VERIFICATION_GAS) {
            revert InvalidGasLimit(preVerificationGas, 0, Constants.MAX_PRE_VERIFICATION_GAS);
        }
    }

    /**
     * @notice Validate time range is logical
     * @param startTime Start timestamp
     * @param endTime End timestamp
     */
    function validateTimeRange(uint256 startTime, uint256 endTime) internal view {
        if (startTime >= endTime) {
            revert InvalidTimeRange(startTime, endTime);
        }
        
        if (startTime < block.timestamp) {
            revert InvalidTimeRange(startTime, block.timestamp);
        }
    }

    /**
     * @notice Validate array lengths match
     * @param array1 First array
     * @param array2 Second array
     */
    function validateArrayLengths(bytes[] memory array1, uint256[] memory array2) internal pure {
        if (array1.length != array2.length) {
            revert InvalidArrayLength(array1.length, array2.length);
        }
    }

    /**
     * @notice Validate array lengths match for addresses and values
     * @param addresses Array of addresses
     * @param values Array of values
     */
    function validateArrayLengths(address[] memory addresses, uint256[] memory values) internal pure {
        if (addresses.length != values.length) {
            revert InvalidArrayLength(addresses.length, values.length);
        }
    }

    /**
     * @notice Validate array is not empty
     * @param array Array to check
     */
    function validateNotEmpty(bytes[] memory array) internal pure {
        if (array.length == 0) {
            revert InvalidArrayLength(0, 1);
        }
    }

    /**
     * @notice Validate nonce is expected value
     * @param nonce The provided nonce
     * @param expectedNonce The expected nonce
     */
    function validateNonce(uint256 nonce, uint256 expectedNonce) internal pure {
        if (nonce != expectedNonce) {
            revert InvalidNonce(nonce, expectedNonce);
        }
    }

    /**
     * @notice Validate call data is not empty for execution
     * @param data Call data to validate
     */
    function validateCallData(bytes memory data) internal pure {
        if (data.length == 0) revert InvalidCallData(data);
        
        // Ensure data has at least function selector (4 bytes)
        if (data.length < 4) revert InvalidCallData(data);
    }

    /**
     * @notice Validate subscription duration
     * @param duration Duration to validate
     */
    function validateSubscriptionDuration(uint256 duration) internal pure {
        if (duration == 0 || duration > Constants.MAX_SUBSCRIPTION_DURATION) {
            revert InvalidDuration(duration, Constants.MAX_SUBSCRIPTION_DURATION);
        }
    }

    /**
     * @notice Validate monthly gas limit for subscriptions
     * @param monthlyLimit Monthly gas limit to validate
     */
    function validateMonthlyLimit(uint256 monthlyLimit) internal pure {
        validateAmount(monthlyLimit, Constants.MIN_MONTHLY_LIMIT, Constants.MAX_MONTHLY_LIMIT);
    }

    /**
     * @notice Validate deposit amount
     * @param amount Deposit amount to validate
     */
    function validateDepositAmount(uint256 amount) internal pure {
        if (amount < Constants.MIN_DEPOSIT) {
            revert InvalidAmount(amount, Constants.MIN_DEPOSIT, type(uint256).max);
        }
    }

    /**
     * @notice Validate signature length
     * @param signature Signature to validate
     */
    function validateSignatureLength(bytes memory signature) internal pure {
        if (signature.length != Constants.SIGNATURE_LENGTH && signature.length > 0) {
            revert InvalidCallData(signature);
        }
    }

    /**
     * @notice Validate execution targets are not empty
     * @param targets Array of target addresses
     */
    function validateExecutionTargets(address[] memory targets) internal pure {
        if (targets.length == 0) {
            revert InvalidArrayLength(0, 1);
        }
        
        validateAddresses(targets);
    }

    /**
     * @notice Validate fee parameters
     * @param maxFeePerGas Maximum fee per gas
     * @param maxPriorityFeePerGas Maximum priority fee per gas
     */
    function validateFeeParameters(uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) internal pure {
        if (maxFeePerGas == 0) {
            revert InvalidAmount(maxFeePerGas, 1, type(uint256).max);
        }
        
        if (maxPriorityFeePerGas > maxFeePerGas) {
            revert InvalidAmount(maxPriorityFeePerGas, 0, maxFeePerGas);
        }
    }

    /**
     * @notice Validate initCode for account deployment
     * @param initCode Initialization code
     */
    function validateInitCode(bytes memory initCode) internal pure {
        // InitCode can be empty (account already deployed) or contain factory address + calldata
        if (initCode.length > 0 && initCode.length < 20) {
            revert InvalidCallData(initCode);
        }
    }

    /**
     * @notice Validate paymaster data
     * @param paymasterAndData Paymaster address and data
     */
    function validatePaymasterData(bytes memory paymasterAndData) internal pure {
        // PaymasterAndData can be empty (no paymaster) or contain paymaster address + data
        if (paymasterAndData.length > 0 && paymasterAndData.length < 20) {
            revert InvalidCallData(paymasterAndData);
        }
    }

    /**
     * @notice Check if value is a power of 2
     * @param value Value to check
     * @return isPowerOf2 True if value is power of 2
     */
    function isPowerOfTwo(uint256 value) internal pure returns (bool isPowerOf2) {
        return value != 0 && (value & (value - 1)) == 0;
    }

    /**
     * @notice Validate percentage value (0-10000 basis points)
     * @param percentage Percentage in basis points
     */
    function validatePercentage(uint256 percentage) internal pure {
        if (percentage > 10000) {
            revert InvalidAmount(percentage, 0, 10000);
        }
    }

    /**
     * @notice Validate chain ID matches current chain
     * @param chainId Chain ID to validate
     */
    function validateChainId(uint256 chainId) internal view {
        if (chainId != block.chainid) {
            revert InvalidAmount(chainId, block.chainid, block.chainid);
        }
    }

    /**
     * @notice Validate contract has code at address
     * @param contractAddr Address to check
     */
    function validateContract(address contractAddr) internal view {
        validateAddress(contractAddr);
        
        uint256 size;
        assembly {
            size := extcodesize(contractAddr)
        }
        
        if (size == 0) revert InvalidAddress(contractAddr);
    }
}