// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation, packValidationData, PAYMASTER_DATA_OFFSET} from "./UserOperation.sol";

// ERC-7562 OP-011: reading the clock during validation.
//
// Both paymasters sponsor any operation until an expiry carried in
// `paymasterData`. Real code would also check a signature over that expiry; it
// is left out so the two differ in one place.

/// REPORTED: TIMESTAMP via `block.timestamp`.
///
/// Passes every unit test, and every `handleOps` call in a test VM, because
/// nothing on chain enforces ERC-7562. A bundler simulates validation before
/// the block exists, sees TIMESTAMP, and drops the operation: the answer it
/// simulated may not be the answer the block gets.
contract ClockCheckingPaymaster {
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        uint48 validUntil = uint48(
            bytes6(userOp.paymasterAndData[PAYMASTER_DATA_OFFSET:PAYMASTER_DATA_OFFSET + 6])
        );
        if (block.timestamp > validUntil) return ("", 1);
        return ("", 0);
    }
}

/// SILENT. The fix: return the window instead of judging it. The EntryPoint
/// compares it with the clock after validation, where no opcode rule applies,
/// and rejects the operation with AA32 once it has expired.
contract WindowReturningPaymaster {
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256)
        external
        pure
        returns (bytes memory context, uint256 validationData)
    {
        uint48 validUntil = uint48(
            bytes6(userOp.paymasterAndData[PAYMASTER_DATA_OFFSET:PAYMASTER_DATA_OFFSET + 6])
        );
        return ("", packValidationData(false, validUntil, 0));
    }
}
