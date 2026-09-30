// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title SolventDepositPaymaster (case 06, fixed)
/// @notice `PooledDepositPaymaster` without `BasePaymaster`, so the owner's
///         withdrawal can respect the users' money.
/// @dev The price of not inheriting is restating the EntryPoint plumbing
///      (`deposit`, `addStake` and the `IPaymaster` entry points, here in
///      `CasePaymaster`). The canonical interfaces and helpers are still the
///      upstream ones.
contract SolventDepositPaymaster is CasePaymaster, Ownable2Step {
    mapping(address user => uint256 balance) public deposits;
    uint256 public totalDeposits;

    error InsufficientDeposit(address user, uint256 required, uint256 available);
    error WouldBreakSolvency(uint256 requested, uint256 free);

    constructor(IEntryPoint entryPoint_) CasePaymaster(entryPoint_) Ownable(msg.sender) {}

    function depositFor(address user) external payable {
        deposits[user] += msg.value;
        totalDeposits += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    function withdrawDeposit(address payable to, uint256 amount) external {
        uint256 balance = deposits[msg.sender];
        if (amount > balance) revert InsufficientDeposit(msg.sender, amount, balance);
        deposits[msg.sender] = balance - amount;
        totalDeposits -= amount;
        entryPoint.withdrawTo(to, amount);
    }

    /// @notice THE FIX. The owner withdraws only what no user has a claim on.
    function withdrawTo(address payable to, uint256 amount) external onlyOwner {
        uint256 free = freeBalance();
        if (amount > free) revert WouldBreakSolvency(amount, free);
        entryPoint.withdrawTo(to, amount);
    }

    /// @notice The deposit above what users are owed: the owner's own money.
    function freeBalance() public view returns (uint256) {
        uint256 held = entryPoint.balanceOf(address(this));
        return held > totalDeposits ? held - totalDeposits : 0;
    }

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory, uint256)
    {
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
