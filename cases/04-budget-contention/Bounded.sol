// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {BudgetLedger} from "./BudgetLedger.sol";

/// @title BoundedBudgetPaymaster (case 04, bounded, not solved)
/// @notice Validation stays a pure check. `postOp` never takes more than the
///         app has, and the owner keeps a buffer in the deposit for the rest.
/// @dev This is what Monarch does. It does not stop a bundle over-committing a
///      budget: nothing a paymaster can do inside validation stops that without
///      running into the reservation's problem. It decides where the overdraw
///      lands: in the owner's buffer, never in another app's budget. The
///      buffer has to be big enough, and the app's signer should not have
///      more sponsorships outstanding than its budget covers.
contract BoundedBudgetPaymaster is BudgetLedger {
    constructor(IEntryPoint entryPoint_) BudgetLedger(entryPoint_) {}

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory, uint256)
    {
        address app = _appOf(userOp);
        uint256 budget = budgets[app];
        if (budget < maxCost) revert InsufficientBudget(app, maxCost, budget);
        return (abi.encode(app), SIG_VALIDATION_SUCCESS);
    }

    function _postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        address app = abi.decode(context, (address));
        uint256 cost = _cost(actualGasCost, actualUserOpFeePerGas);

        // THE BOUND. Clamp instead of reverting, so this always settles and the
        // app is always charged what it has. Whatever the clamp leaves unpaid
        // comes out of the part of the deposit that no budget claims: the
        // owner's buffer, deposited through `deposit()`.
        uint256 budget = budgets[app];
        uint256 debit = cost > budget ? budget : cost;
        budgets[app] = budget - debit;
        totalBudgets -= debit;
    }

    /// @notice The owner's buffer: deposit not claimed by any budget.
    function freeBalance() external view returns (uint256) {
        uint256 held = entryPoint.balanceOf(address(this));
        return held > totalBudgets ? held - totalBudgets : 0;
    }
}
