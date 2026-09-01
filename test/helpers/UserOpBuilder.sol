// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";

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
    uint128 internal constant DEFAULT_PM_POSTOP_GAS = 80_000;
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
        return
            abi.encodePacked(
                paymaster, DEFAULT_PM_VERIFICATION_GAS, DEFAULT_PM_POSTOP_GAS, uint8(0)
            );
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
        return abi.encodePacked(
            paymaster,
            DEFAULT_PM_VERIFICATION_GAS,
            DEFAULT_PM_POSTOP_GAS,
            uint8(1),
            app,
            validUntil,
            validAfter
        );
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
