// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";

/// @title UserOpBuilder
/// @notice Test-only construction of `PackedUserOperation` and Monarch's
///         `paymasterAndData`.
/// @dev Exists so the ERC-4337 bit-packing is written once. A test that packs
///      its own `accountGasLimits` can be wrong in the same direction as the
///      assertion it is checking, and pass.
///
///      The mode byte sits at offset 52, after the paymaster address and both
///      paymaster gas limits. The implementation Monarch replaces read it at
///      offset 20, the v0.6 position.
library UserOpBuilder {
    uint128 internal constant DEFAULT_VERIFICATION_GAS = 300_000;
    uint128 internal constant DEFAULT_CALL_GAS = 200_000;
    uint128 internal constant DEFAULT_PM_VERIFICATION_GAS = 150_000;
    /// @dev 40,000, not the 80,000 this used to be. Above that the EntryPoint
    ///      charges the paymaster a penalty for the unused remainder, which
    ///      inflated every local calibration of `POSTOP_GAS_OVERHEAD` by about
    ///      6,850 gas. Monarch now prices that penalty rather than absorbing it,
    ///      but a default that does not attract one keeps the rest of the suite
    ///      measuring the thing it means to. This is also the value the
    ///      reference sponsor route sends.
    uint128 internal constant DEFAULT_PM_POSTOP_GAS = 40_000;
    uint256 internal constant DEFAULT_PREVERIFICATION_GAS = 60_000;

    function base(address sender, uint256 nonce, bytes memory callData)
        internal
        pure
        returns (PackedUserOperation memory op)
    {
        op.sender = sender;
        op.nonce = nonce;
        op.initCode = "";
        op.callData = callData;
        op.accountGasLimits = packLimits(DEFAULT_VERIFICATION_GAS, DEFAULT_CALL_GAS);
        op.preVerificationGas = DEFAULT_PREVERIFICATION_GAS;
        op.gasFees = packLimits(1 gwei, 1 gwei);
        op.paymasterAndData = "";
        op.signature = "";
    }

    /// @dev High 128 bits first. Used for both `accountGasLimits`
    ///      (verification, call) and `gasFees` (maxPriorityFee, maxFee).
    function packLimits(uint128 high, uint128 low) internal pure returns (bytes32) {
        return bytes32((uint256(high) << 128) | uint256(low));
    }

    /// @notice `paymasterAndData` for Deposit mode: header plus one mode byte.
    function depositData(address paymaster) internal pure returns (bytes memory) {
        return depositData(paymaster, DEFAULT_PM_POSTOP_GAS);
    }

    /// @notice Deposit mode with an explicit `paymasterPostOpGasLimit`.
    /// @dev That limit is not cosmetic. The EntryPoint charges a penalty of a
    ///      tenth of whatever part of it goes unused, and bills that penalty to
    ///      the paymaster *after* `postOp` has already decided what to charge —
    ///      so the limit chosen here moves the measured overhead. See
    ///      `test/integration/PostOpOverhead.t.sol`.
    function depositData(address paymaster, uint128 pmPostOpGas)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(paymaster, DEFAULT_PM_VERIFICATION_GAS, pmPostOpGas, uint8(0));
    }

    /// @notice The signed prefix of Sponsored `paymasterAndData` — everything
    ///         up to the signature, which is exactly what the digest covers.
    /// @dev Two-step by necessity: the digest covers these bytes, so the
    ///      signature can only be appended after they exist. Build this, hash it
    ///      via `getSponsorshipHash`, sign, then `withSignature`. Because the
    ///      digest reads only `[:SIGNATURE_OFFSET]`, hashing the prefix alone
    ///      gives the same answer as hashing the finished article.
    function sponsoredPrefix(address paymaster, address app, uint48 validUntil, uint48 validAfter)
        internal
        pure
        returns (bytes memory)
    {
        return sponsoredPrefix(paymaster, app, validUntil, validAfter, DEFAULT_PM_POSTOP_GAS);
    }

    /// @notice Sponsored prefix with an explicit `paymasterPostOpGasLimit`.
    /// @dev See `depositData` above for why that limit matters.
    function sponsoredPrefix(
        address paymaster,
        address app,
        uint48 validUntil,
        uint48 validAfter,
        uint128 pmPostOpGas
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            paymaster,
            DEFAULT_PM_VERIFICATION_GAS,
            pmPostOpGas,
            uint8(1),
            app,
            validUntil,
            validAfter
        );
    }

    /// @notice The context Monarch's validation hands to `postOp`.
    /// @dev It carries `paymasterPostOpGasLimit` as well as the payer, because
    ///      `postOp` cannot see the operation and needs that limit to reproduce
    ///      the EntryPoint's unused-gas penalty. Tests that drive `postOp`
    ///      directly build the context here, so its shape lives in one place.
    function context(MonarchPaymaster.Mode mode, address user, address app)
        internal
        pure
        returns (bytes memory)
    {
        return context(mode, user, app, DEFAULT_PM_POSTOP_GAS);
    }

    function context(MonarchPaymaster.Mode mode, address user, address app, uint256 postOpGasLimit)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(mode, user, app, postOpGasLimit);
    }

    /// @notice Append a signature to a prefix built above.
    function withSignature(bytes memory prefix, bytes memory signature)
        internal
        pure
        returns (bytes memory)
    {
        require(prefix.length == Constants.SIGNATURE_OFFSET, "UserOpBuilder: bad prefix length");
        require(signature.length == Constants.SIGNATURE_LENGTH, "UserOpBuilder: bad sig length");
        return bytes.concat(prefix, signature);
    }
}
