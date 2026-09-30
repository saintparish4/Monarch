// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title FlooredDepositPaymaster (case 03, fixed)
/// @notice `UnflooredDepositPaymaster` with a floor on the postOp gas limit.
contract FlooredDepositPaymaster is CasePaymaster {
    /// @dev Measure this for your own `postOp`, then add a margin: the test
    ///      `test_theFloorLeavesRoomToSpare` finds where this one starves.
    ///      Monarch's settles at 12,000 and starves at 11,000, and uses 20,000.
    uint256 public constant MIN_POSTOP_GAS_LIMIT = 20_000;

    mapping(address user => uint256 balance) public deposits;
    uint256 public totalDeposits;

    error InsufficientDeposit(address user, uint256 required, uint256 available);
    error PostOpGasLimitTooLow(uint256 limit, uint256 minimum);

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
        // THE FIX. Refuse an operation this paymaster could not charge for.
        // A revert, not a signature failure: the check reads only the
        // operation's own fields, so a bundler's simulation sees it and drops
        // the operation before it is ever in a bundle. A floor only; case 02 is
        // why there is no ceiling.
        uint256 limit = uint128(bytes16(userOp.paymasterAndData[36:DATA_OFFSET]));
        if (limit < MIN_POSTOP_GAS_LIMIT) revert PostOpGasLimitTooLow(limit, MIN_POSTOP_GAS_LIMIT);

        uint256 balance = deposits[userOp.sender];
        if (balance < maxCost) revert InsufficientDeposit(userOp.sender, maxCost, balance);
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
