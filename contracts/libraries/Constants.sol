// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Constants
/// @notice Protocol-level constants for Monarch's ERC-4337 v0.8 paymaster.
/// @dev This library holds facts about the *standard*, not about Monarch's
///      policy. Anything tunable by the owner belongs in storage on
///      MonarchPaymaster, not here — a constant is a promise that it will
///      never need to change without a redeploy.
///
///      Everything here is `internal`, so it inlines and adds no deployed
///      bytecode of its own.
library Constants {
    /// @notice ERC-4337 EntryPoint v0.8, at the same address on every chain.
    /// @dev The v0.6 EntryPoint constant that used to sit beside this was
    ///      deleted. Monarch supports exactly one EntryPoint; supporting two
    ///      means two validation rule sets, two `postOp` arities, and two sets
    ///      of tests.
    address internal constant ENTRY_POINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    /// @dev Layout of `PackedUserOperation.paymasterAndData` under v0.7+:
    ///
    ///        [0:20]    paymaster address
    ///        [20:36]   paymasterVerificationGasLimit (uint128)
    ///        [36:52]   paymasterPostOpGasLimit       (uint128)
    ///        [52:]     paymasterData  <- everything below is ours
    ///
    ///      The implementation this replaces read its mode byte at index 20,
    ///      which was the v0.6 layout — under v0.7+ index 20 is the first byte
    ///      of the verification gas limit. That is why these are named
    ///      constants and not literals at the call site.
    uint256 internal constant PAYMASTER_DATA_OFFSET = 52;

    /// @notice Where the two paymaster gas limits start. They are adjacent
    ///         uint128s, so together they are exactly one 32-byte word:
    ///         `[GAS_LIMITS_OFFSET:MODE_OFFSET]`, verification in the high half
    ///         and postOp in the low half.
    /// @dev Monarch reads the postOp half during validation because the
    ///      EntryPoint charges a penalty for the part of it that goes unused,
    ///      and bills that penalty to the paymaster after `postOp` has already
    ///      decided what to charge, and because too small a limit starves
    ///      `postOp` entirely. See `MonarchPaymaster.MIN_POSTOP_GAS_LIMIT`.
    ///      Reading the whole word and masking is 104 gas cheaper than slicing
    ///      the 16 bytes out on their own.
    uint256 internal constant GAS_LIMITS_OFFSET = 20;

    /// @dev Monarch's own `paymasterData`, relative to PAYMASTER_DATA_OFFSET:
    ///
    ///        Deposit    [+0]      mode = 0x00
    ///        Sponsored  [+0]      mode = 0x01
    ///                   [+1:+21]  app address     (20 bytes)
    ///                   [+21:+27] validUntil      (uint48)
    ///                   [+27:+33] validAfter      (uint48)
    ///                   [+33:+98] ECDSA signature (65 bytes)
    uint256 internal constant MODE_OFFSET = PAYMASTER_DATA_OFFSET;
    uint256 internal constant APP_OFFSET = PAYMASTER_DATA_OFFSET + 1;
    uint256 internal constant VALID_UNTIL_OFFSET = PAYMASTER_DATA_OFFSET + 21;
    uint256 internal constant VALID_AFTER_OFFSET = PAYMASTER_DATA_OFFSET + 27;
    uint256 internal constant SIGNATURE_OFFSET = PAYMASTER_DATA_OFFSET + 33;

    /// @notice Total length of `paymasterAndData` for each mode.
    /// @dev Checked as an equality, not a minimum. A trailing-garbage
    ///      tolerance would let two different byte strings authorise the same
    ///      sponsorship.
    uint256 internal constant DEPOSIT_DATA_LENGTH = PAYMASTER_DATA_OFFSET + 1;
    uint256 internal constant SPONSORED_DATA_LENGTH = PAYMASTER_DATA_OFFSET + 98;

    /// @notice Canonical length of a packed `(r, s, v)` ECDSA signature.
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /// @notice Widths of the fields inside `paymasterData`, for slicing.
    /// @dev Named rather than written as literals at the call site for the same
    ///      reason the offsets are: an off-by-one here decodes a plausible
    ///      address rather than reverting.
    uint256 internal constant APP_WIDTH = 20;
    uint256 internal constant TIMESTAMP_WIDTH = 6;

    /// @notice Floor on a user's prepaid top-up.
    /// @dev Not a policy preference — dust deposits cost more gas to account
    ///      for than they can ever pay for, so accepting them is a way to lose
    ///      money on every call.
    uint256 internal constant MIN_DEPOSIT = 0.0001 ether;
}
