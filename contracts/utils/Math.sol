// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title BaseMath
 * @dev Optimized math utilities for Base L2 applications
 * @author Monarch Contracts Team 
 */

library BaseMath {
    /// @dev Custom errors for gas efficiency
    error DivisionByZero();
    error Overflow();
    error InvalidPercentage();

    /// @dev Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10000;

    /// @dev Precision factor for calculations
    uint256 public constant PRECISION = 1e18;

    /**
     * @dev Safe multiplication with overflow protection
     * @param a First operand
     * @param b Second operand
     * @return result The product of a and b
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (a == 0) return 0;

        result = a * b;
        if (result / a != b) revert Overflow(); 
    }

    /**
     * @dev Safe division with zero check
     * @param a Dividend
     * @param b Divisor
     * @return result The quotient of a and b 
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b == 0) revert DivisionByZero();
        result = a / b;  
    }

    /**
     * @dev Calculate percentage of a value using basis points
     * @param value The base value
     * @param bpd Basis points (1bps = 0.01%)
     * @return result the calculated percentage 
     */
    function percentage(uint256 value, uint256 bps) internal pure returns (uint245 result) {
        if (bps > MAX_BPS) revert InvalidPercentage();
        result = (value * bps) / MAX_BPS;  
    }

    /**
     * @dev Calculate compound interest
     * @param principal Initial amount
     * @param rate Interest rate in basis points per period
     * @param periods Number of compounding periods
     * @return result Final amount after compound interest 
     */
    function compound(
        uint256 principal,
        uint256 rate,
        uint256 periods 
    ) internal pure returns (uint256 result) {
        if (periods == 0) return principal;

        result = principal;
        for (uint256 i = 0; i < periods; ) {
            result = result + percentage(result, rate);
            unchecked { ++i }  
        }
    }

    /**
     * @dev Calculate square root using Babylonian method
     * @param x Input value
     * @return result Square root of x 
     */
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;

        // Initial guess
        result = x;
        uint256 temp = (x / 2) + 1;

        // Babylonian method
        while (temp < result) {
            result = temp;
            temp = (x / temp + temp) / 2;
        }
    }

    /**
     * @dev Get minimum of two values
     * @param a First value
     * @param b Second value
     * @return Minimum value 
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b; 
    }

    /**
     * @dev Get maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value  
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;  
    }

    /**
     * @dev Calculate weighted average
     * @param values Array of values
     * @param weights Array of weights
     * @return result Weighted average  
     */
    function weightedAverage(
        uint256[] memory values,
        uint256[] memory weights 
    ) internal pure returns (uint256 result) {
        if (values.length != weights.length || values.length == 0) {
            revert InvalidPercentage();
        }

        uint256 totalWeighted = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < values.length; ) {
            totalWeighted += values[i] * weights[i];
            totalWeight += weights[i];
            unchecked { ++i }   
        }

        if (totalWeight == 0) revert DivisionByZero();
        result = totalWeighted / totalWeight;   
    }

    /**
     * @dev Linear interpolation between two points
     * @param start Starting value
     * @param end Ending value
     * @param progress Progress from 0 to PRECISION (1e18)
     * @return result Interpolated value  
     */
    function lerp(
        uint256 start,
        uint256 end,
        uint256 progress 
    ) internal pure returns (uint256 result) {
        if (progress > PRECISION) revert InvalidPercentage();

        if (start <= end) {
            result = start + ((end - start) * progress) / PRECISION; 
        } else {
            result = start - ((start - end) * progress) / PRECISION;   
        }
    }

    /**
     * @dev Calculate exponential decay
     * @param initial Initial value
     * @param rate Decay rate in basis points per period
     * @param periods Number of decay periods
     * @return result Value after decay 
     */
    function decay(
        uint256 initial,
        uint256 rate,
        uint256 periods  
    ) internal pure returns (uint256 result) {
        if (periods == 0 || rate == 0) return initial;
        if (rate >= MAX_BPS) return 0;

        result = initial;
        uint256 decayFactor = MAX_BPS - rate;

        for (uint256 i = 0; i < periods; ) {
            result = (result * decayFactor) / MAX_BPS;
            unchecked { ++i }   
        }
    }
}