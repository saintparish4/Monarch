// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title CappedPostOpPaymaster (case 02, broken)
/// @notice Sponsors any operation and records what each sender cost in
///         `postOp`. Refuses a `paymasterPostOpGasLimit` outside a band.
/// @dev The floor is right: case 03 is what happens without one. The ceiling
///      is the bug. It was added to stop a payer choosing a large limit, and it
///      makes the paymaster impossible to gas-estimate.
contract CappedPostOpPaymaster is CasePaymaster {
    uint256 public constant MIN_POSTOP_GAS_LIMIT = 20_000;
    uint256 public constant MAX_POSTOP_GAS_LIMIT = 40_000;

    mapping(address sender => uint256 cost) public spent;

    error PostOpGasLimitOutOfRange(uint256 limit, uint256 minimum, uint256 maximum);

    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) {}

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256)
        internal
        pure
        override
        returns (bytes memory, uint256)
    {
        uint256 limit = uint128(bytes16(userOp.paymasterAndData[36:DATA_OFFSET]));

        // THE BUG is the second comparison. Bundlers estimate gas by simulating
        // the operation with paymaster gas limits far above anything real, then
        // fill in measured ones. A paymaster that reverts on a large limit
        // reverts during that simulation, so the estimate fails, so the
        // operation is never sent.
        if (limit < MIN_POSTOP_GAS_LIMIT || limit > MAX_POSTOP_GAS_LIMIT) {
            revert PostOpGasLimitOutOfRange(limit, MIN_POSTOP_GAS_LIMIT, MAX_POSTOP_GAS_LIMIT);
        }
        return (abi.encode(userOp.sender), SIG_VALIDATION_SUCCESS);
    }

    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256)
        internal
        override
    {
        spent[abi.decode(context, (address))] += actualGasCost;
    }
}
