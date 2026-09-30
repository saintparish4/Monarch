// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title BudgetLedger
/// @notice What the three case 04 paymasters share: apps fund budgets into one
///         EntryPoint deposit, and each operation names the app that pays.
/// @dev Invariant all three mean to keep: `entryPoint.balanceOf(this) >= totalBudgets`.
///
///      `paymasterData` is the paying app's address (20 bytes). Real code
///      checks a signature from that app; it is left out so the three files
///      differ only in their accounting. Case 05 is about the signature.
///
///      Every version reads `budgets[app]`, which is not storage associated
///      with the sender, so every version must be staked (ERC-7562 STO-031,
///      STO-033), and every version returns a context, which needs a stake too
///      (EREP-050).
abstract contract BudgetLedger is CasePaymaster {
    /// @dev Gas the EntryPoint spends around `postOp`, which `actualGasCost`
    ///      is computed too early to include. Charged on top, so one operation
    ///      on its own leaves the ledger covered and anything that breaks it in
    ///      these tests is contention's doing:
    ///      `test_oneOperationAloneLeavesEveryVersionSolvent` is the control.
    ///      Measure your own. Monarch's is 15,000.
    uint256 internal constant POSTOP_OVERHEAD = 20_000;

    mapping(address app => uint256 budget) public budgets;
    uint256 public totalBudgets;

    error InsufficientBudget(address app, uint256 required, uint256 available);

    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) {}

    function fund(address app) external payable {
        budgets[app] += msg.value;
        totalBudgets += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    function _appOf(PackedUserOperation calldata userOp) internal pure returns (address) {
        return address(bytes20(userOp.paymasterAndData[DATA_OFFSET:DATA_OFFSET + 20]));
    }

    /// @dev What one operation really cost the deposit.
    function _cost(uint256 actualGasCost, uint256 feePerGas) internal pure returns (uint256) {
        return actualGasCost + POSTOP_OVERHEAD * feePerGas;
    }
}
