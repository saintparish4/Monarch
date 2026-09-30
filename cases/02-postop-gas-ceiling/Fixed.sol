// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title FlooredPostOpPaymaster (case 02, fixed)
/// @notice `CappedPostOpPaymaster` with the ceiling removed.
contract FlooredPostOpPaymaster is CasePaymaster {
    uint256 public constant MIN_POSTOP_GAS_LIMIT = 20_000;

    mapping(address sender => uint256 cost) public spent;

    error PostOpGasLimitTooLow(uint256 limit, uint256 minimum);

    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) {}

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256)
        internal
        pure
        override
        returns (bytes memory, uint256)
    {
        uint256 limit = uint128(bytes16(userOp.paymasterAndData[36:DATA_OFFSET]));

        // THE FIX. A floor, and no ceiling. An oversized limit is a cost rather
        // than a danger: the EntryPoint bills the paymaster a tenth of whatever
        // part of the limit goes unused (above a 40,000 gas waiver). If that
        // cost matters, price it into what the payer is charged. Never refuse
        // the operation over it.
        if (limit < MIN_POSTOP_GAS_LIMIT) revert PostOpGasLimitTooLow(limit, MIN_POSTOP_GAS_LIMIT);
        return (abi.encode(userOp.sender), SIG_VALIDATION_SUCCESS);
    }

    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256)
        internal
        override
    {
        spent[abi.decode(context, (address))] += actualGasCost;
    }
}
