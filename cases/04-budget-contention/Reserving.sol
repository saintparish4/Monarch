// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {BudgetLedger} from "./BudgetLedger.sol";

/// @title ReservingBudgetPaymaster (case 04, the tempting fix, also broken)
/// @notice Reserves each operation's maximum cost during validation and refunds
///         the unused part in `postOp`, so the budget can never be overspent.
contract ReservingBudgetPaymaster is BudgetLedger {
    constructor(IEntryPoint entryPoint_) BudgetLedger(entryPoint_) {}

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        internal
        override
        returns (bytes memory, uint256)
    {
        address app = _appOf(userOp);
        uint256 budget = budgets[app];
        if (budget < maxCost) revert InsufficientBudget(app, maxCost, budget);

        // THE BUG, and it looks like the fix. Writing its own storage is
        // allowed for a staked paymaster (ERC-7562 STO-031), and this does keep
        // the ledger exact. But it makes each operation's validation depend on
        // the operations validated before it in the same bundle. A bundler
        // checks each operation alone, finds it valid, builds a bundle, and the
        // second operation fails inside it. Under GREP-040, an entity that
        // fails bundle creation after passing the second validation is BANNED.
        budgets[app] = budget - maxCost;
        return (abi.encode(app, maxCost), SIG_VALIDATION_SUCCESS);
    }

    function _postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        (address app, uint256 reserved) = abi.decode(context, (address, uint256));
        uint256 cost = _cost(actualGasCost, actualUserOpFeePerGas);
        // Cannot underflow while `paymasterPostOpGasLimit` is at least
        // `POSTOP_OVERHEAD`: `maxCost` includes that limit and `actualGasCost`
        // does not. A real version enforces that floor (case 03).
        budgets[app] += reserved - cost;
        totalBudgets -= cost;
    }
}
