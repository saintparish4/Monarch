// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title UnflooredDepositPaymaster (case 03, broken)
/// @notice Users prepay gas into a shared pot; each operation is charged to
///         its sender's balance in `postOp`.
/// @dev Invariant it means to keep: `entryPoint.balanceOf(this) >= totalDeposits`.
contract UnflooredDepositPaymaster is CasePaymaster {
    mapping(address user => uint256 balance) public deposits;
    uint256 public totalDeposits;

    error InsufficientDeposit(address user, uint256 required, uint256 available);

    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) {}

    function depositFor(address user) external payable {
        deposits[user] += msg.value;
        totalDeposits += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory, uint256)
    {
        uint256 balance = deposits[userOp.sender];
        if (balance < maxCost) revert InsufficientDeposit(userOp.sender, maxCost, balance);

        // THE BUG is what isn't here. `paymasterPostOpGasLimit` is the sender's
        // to choose, and nothing stops them choosing too little for `postOp` to
        // finish. When `postOp` runs out of gas, the EntryPoint does not fail
        // the bundle: it rolls the operation back, settles in `postOpReverted`
        // mode, which never calls `postOp` again, and takes the whole cost from
        // this paymaster's deposit. The debit below never happens.
        return (abi.encode(userOp.sender), SIG_VALIDATION_SUCCESS);
    }

    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256)
        internal
        override
    {
        address user = abi.decode(context, (address));
        uint256 balance = deposits[user];
        uint256 debit = actualGasCost > balance ? balance : actualGasCost;
        deposits[user] = balance - debit;
        totalDeposits -= debit;
    }
}
