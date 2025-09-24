// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Math
 * @dev Mathematical operations and utilities for BaseKit gasless modules
 * @notice Provides safe math operations and gas cost calculations
 */
library Math {
    // Errors
    error MathOverflow();
    error MathUnderflow();
    error DivisionByZero();
    error InvalidPercentage(uint256 percentage);

    // Constants for gas calculations
    uint256 private constant GAS_PRICE_MULTIPLIER = 120; // 20% buffer for gas price fluctuations
    uint256 private constant PERCENTAGE_BASE = 10000; // Basis points (100% = 10000)

    /**
     * @notice Safe addition with overflow check
     * @param a First number
     * @param b Second number
     * @return result The sum of a and b
     */
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a + b;
        if (result < a) revert MathOverflow();
    }

    /**
     * @notice Safe subtraction with underflow check
     * @param a First number
     * @param b Second number
     * @return result The difference of a and b
     */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b > a) revert MathUnderflow();
        result = a - b;
    }

    /**
     * @notice Safe multiplication with overflow check
     * @param a First number
     * @param b Second number
     * @return result The product of a and b
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (a == 0) return 0;
        result = a * b;
        if (result / a != b) revert MathOverflow();
    }

    /**
     * @notice Safe division with zero check
     * @param a Dividend
     * @param b Divisor
     * @return result The quotient of a and b
     */
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b == 0) revert DivisionByZero();
        result = a / b;
    }

    /**
     * @notice Calculate percentage of a value
     * @param value The base value
     * @param percentage The percentage in basis points (100% = 10000)
     * @return result The calculated percentage
     */
    function calculatePercentage(uint256 value, uint256 percentage) 
        internal 
        pure 
        returns (uint256 result) 
    {
        if (percentage > PERCENTAGE_BASE) revert InvalidPercentage(percentage);
        result = safeMul(value, percentage) / PERCENTAGE_BASE;
    }

    /**
     * @notice Calculate gas cost with buffer
     * @param gasUsed The amount of gas used
     * @param gasPrice The gas price in wei
     * @return cost The total cost with buffer
     */
    function calculateGasCost(uint256 gasUsed, uint256 gasPrice) 
        internal 
        pure 
        returns (uint256 cost) 
    {
        uint256 baseCost = safeMul(gasUsed, gasPrice);
        cost = calculatePercentage(baseCost, GAS_PRICE_MULTIPLIER);
    }

    /**
     * @notice Calculate gas cost for user operation
     * @param callGasLimit Gas limit for the main call
     * @param verificationGasLimit Gas limit for verification
     * @param preVerificationGas Pre-verification gas
     * @param gasPrice Gas price in wei
     * @return totalCost The total estimated cost
     */
    function calculateUserOpGasCost(
        uint256 callGasLimit,
        uint256 verificationGasLimit,
        uint256 preVerificationGas,
        uint256 gasPrice
    ) internal pure returns (uint256 totalCost) {
        uint256 totalGas = safeAdd(
            safeAdd(callGasLimit, verificationGasLimit), 
            preVerificationGas
        );
        totalCost = calculateGasCost(totalGas, gasPrice);
    }

    /**
     * @notice Return the minimum of two numbers
     * @param a First number
     * @param b Second number
     * @return result The smaller of the two numbers
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a < b ? a : b;
    }

    /**
     * @notice Return the maximum of two numbers
     * @param a First number
     * @param b Second number
     * @return result The larger of the two numbers
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a > b ? a : b;
    }

    /**
     * @notice Calculate the ceiling of a division
     * @param a Dividend
     * @param b Divisor
     * @return result The ceiling of a/b
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b == 0) revert DivisionByZero();
        result = (a + b - 1) / b;
    }

    /**
     * @notice Check if a number is within a range (inclusive)
     * @param value The value to check
     * @param minValue The minimum allowed value
     * @param maxValue The maximum allowed value
     * @return inRange True if value is within range
     */
    function isInRange(uint256 value, uint256 minValue, uint256 maxValue) 
        internal 
        pure 
        returns (bool inRange) 
    {
        return value >= minValue && value <= maxValue;
    }

    /**
     * @notice Calculate compound growth
     * @param principal The initial amount
     * @param rate The growth rate per period (in basis points)
     * @param periods The number of periods
     * @return result The final amount after compound growth
     */
    function compoundGrowth(uint256 principal, uint256 rate, uint256 periods) 
        internal 
        pure 
        returns (uint256 result) 
    {
        if (periods == 0) return principal;
        
        result = principal;
        for (uint256 i = 0; i < periods; i++) {
            uint256 growth = calculatePercentage(result, rate);
            result = safeAdd(result, growth);
        }
    }

    /**
     * @notice Calculate the square root of a number (Babylonian method)
     * @param x The number to find square root of
     * @return result The square root
     */
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        // Initial guess
        result = x;
        uint256 k = (x / 2) + 1;
        
        while (k < result) {
            result = k;
            k = (x / k + k) / 2;
        }
    }

    /**
     * @notice Pack two uint128 values into a single uint256
     * @param upper The upper 128 bits
     * @param lower The lower 128 bits
     * @return packed The packed value
     */
    function pack128(uint128 upper, uint128 lower) internal pure returns (uint256 packed) {
        packed = (uint256(upper) << 128) | uint256(lower);
    }

    /**
     * @notice Unpack a uint256 into two uint128 values
     * @param packed The packed value
     * @return upper The upper 128 bits
     * @return lower The lower 128 bits
     */
    function unpack128(uint256 packed) internal pure returns (uint128 upper, uint128 lower) {
        upper = uint128(packed >> 128);
        lower = uint128(packed & 0xffffffffffffffffffffffffffffffff);
    }
}