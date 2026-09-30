// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {_packValidationData} from "account-abstraction/core/Helpers.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title WindowReturningPaymaster (case 01, fixed)
/// @notice The same expiry as `ClockCheckingPaymaster`, enforced without
///         reading the clock.
contract WindowReturningPaymaster is CasePaymaster {
    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) {}

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256)
        internal
        pure
        override
        returns (bytes memory, uint256)
    {
        uint48 validUntil = uint48(bytes6(userOp.paymasterAndData[DATA_OFFSET:DATA_OFFSET + 6]));

        // THE FIX. Return the window instead of judging it. The EntryPoint
        // compares it with the clock after validation has returned, where no
        // opcode rule applies, and refuses the operation with AA32 if it is
        // outside. The paymaster decides; it never observes.
        return ("", _packValidationData(false, validUntil, 0));
    }
}
