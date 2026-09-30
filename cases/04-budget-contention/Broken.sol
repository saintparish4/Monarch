// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {BudgetLedger} from "./BudgetLedger.sol";

/// @title CheckedBudgetPaymaster (case 04, broken)
/// @notice Checks the app's budget in validation, spends it in `postOp`.
contract CheckedBudgetPaymaster is BudgetLedger {
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

        // THE BUG. In a bundle, every validation runs before any `postOp`, so
        // every operation above was checked against the same budget. Once the
        // earlier ones have spent it, this subtraction underflows and reverts.
        // The EntryPoint then rolls the operation back, settles it in
        // `postOpReverted` mode, which never calls `postOp` again, and takes
        // the cost from the whole deposit: from every other app's budget. The
        // app keeps what it had left.
        budgets[app] -= cost;
        totalBudgets -= cost;
    }
}
