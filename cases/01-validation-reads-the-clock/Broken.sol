// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title ClockCheckingPaymaster (case 01, broken)
/// @notice Sponsors any operation until an expiry carried in `paymasterData`,
///         and checks the expiry itself.
/// @dev `paymasterData` is `validUntil` (6 bytes). Real code signs the window;
///      the signature is left out so the only difference from `Fixed.sol` is
///      the one that matters. Case 05 is about the signature.
contract ClockCheckingPaymaster is CasePaymaster {
    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) {}

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256)
        internal
        view
        override
        returns (bytes memory, uint256)
    {
        uint48 validUntil = uint48(bytes6(userOp.paymasterAndData[DATA_OFFSET:DATA_OFFSET + 6]));

        // THE BUG. TIMESTAMP during validation is forbidden by ERC-7562 (OP-011).
        // A bundler simulates this at one moment and the block runs it at
        // another, so the answer it simulated is not the answer it gets.
        if (block.timestamp > validUntil) return ("", SIG_VALIDATION_FAILED);
        return ("", SIG_VALIDATION_SUCCESS);
    }
}
