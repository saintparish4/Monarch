// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Math
 * @dev Mathematical utilities optimized for Base L2 applications
 * @author BlueSky Labs Contracts Team
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Math: division by zero");

        // (a + b - 1) / b can overflow on addition, so we distribute
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @dev Calculates floor(sqrt(a)), following the selected rounding direction.
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`.
        // We also know that `k`, the position of the most significant bit, is such that `msb(a) = 2**k`.
        // This gives `2**k < a <= 2**(k+1)` → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2+1)`.
        // Using an algorithm similar to the msb computation, we are able to compute `result = 2**(k/2)` which is a
        // good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1;
        uint256 x = a;
        if (x >> 128 > 0) {
            x >>= 128;
            result <<= 64;
        }
        if (x >> 64 > 0) {
            x >>= 64;
            result <<= 32;
        }
        if (x >> 32 > 0) {
            x >>= 32;
            result <<= 16;
        }
        if (x >> 16 > 0) {
            x >>= 16;
            result <<= 8;
        }
        if (x >> 8 > 0) {
            x >>= 8;
            result <<= 4;
        }
        if (x >> 4 > 0) {
            x >>= 4;
            result <<= 2;
        }
        if (x >> 2 > 0) {
            result <<= 1;
        }

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @dev Calculates the percentage of a value
     * @param value The value to calculate percentage of
     * @param percentage The percentage in basis points (100 = 1%)
     * @return The percentage of the value
     */
    function percentageOf(uint256 value, uint256 percentage) internal pure returns (uint256) {
        return (value * percentage) / 10000;
    }

    /**
     * @dev Calculates compound interest
     * @param principal The principal amount
     * @param rate The interest rate in basis points per period
     * @param periods The number of periods
     * @return The final amount after compound interest
     */
    function compoundInterest(uint256 principal, uint256 rate, uint256 periods) internal pure returns (uint256) {
        if (periods == 0) return principal;

        uint256 result = principal;
        for (uint256 i = 0; i < periods; i++) {
            result = result + percentageOf(result, rate);
        }
        return result;
    }

    /**
     * @dev Calculates simple interest
     * @param principal The principal amount
     * @param rate The interest rate in basis points per period
     * @param periods The number of periods
     * @return The final amount after simple interest
     */
    function simpleInterest(uint256 principal, uint256 rate, uint256 periods) internal pure returns (uint256) {
        return principal + percentageOf(principal, rate * periods);
    }

    /**
     * @dev Calculate the power of a number using binary exponentiation
     * @param base The base number
     * @param exponent The exponent
     * @return The result of base^exponent
     */
    function pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0) return 1;
        if (base == 0) return 0;

        uint256 result = 1;
        uint256 currentBase = base;

        while (exponent > 0) {
            if (exponent & 1 == 1) {
                result = result * currentBase;
            }
            currentBase = currentBase * currentBase;
            exponent >>= 1;
        }

        return result;
    }

    /**
     * @dev Calculate absolute difference between two numbers
     * @param a First number
     * @param b Second number
     * @return The absolute difference
     */
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /**
     * @dev Check if a number is within a percentage range of another
     * @param value The value to check
     * @param target The target value
     * @param tolerance The tolerance in basis points
     * @return True if within range
     */
    function isWithinTolerance(uint256 value, uint256 target, uint256 tolerance) internal pure returns (bool) {
        uint256 diff = absDiff(value, target);
        uint256 maxDiff = percentageOf(target, tolerance);
        return diff <= maxDiff;
    }

    /**
     * @dev Linear interpolation between two values
     * @param a Starting value
     * @param b Ending value
     * @param t Interpolation factor (0-10000, where 10000 = 100%)
     * @return The interpolated value
     */
    function lerp(uint256 a, uint256 b, uint256 t) internal pure returns (uint256) {
        require(t <= 10000, "Math: t must be <= 10000");

        if (a == b) return a;

        uint256 diff = absDiff(a, b);
        uint256 interpolatedDiff = percentageOf(diff, t);

        return a < b ? a + interpolatedDiff : a - interpolatedDiff;
    }
}
