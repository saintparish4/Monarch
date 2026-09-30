// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The two pieces of ERC-4337 v0.7/v0.8 the examples need, restated so each
// example compiles with plain `solc` and no dependencies. In a real project
// these come from `account-abstraction`.

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

/// @dev `validationData` as the EntryPoint reads it: a signature-failure flag
///      in the low 160 bits, then `validUntil`, then `validAfter`.
function packValidationData(bool sigFailed, uint48 validUntil, uint48 validAfter)
    pure
    returns (uint256)
{
    return (sigFailed ? 1 : 0) | (uint256(validUntil) << 160) | (uint256(validAfter) << 208);
}

/// @dev Where a paymaster's own data starts inside `paymasterAndData`.
uint256 constant PAYMASTER_DATA_OFFSET = 52;
