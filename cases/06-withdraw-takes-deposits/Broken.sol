// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";

/// @title PooledDepositPaymaster (case 06, broken)
/// @notice Users prepay gas into a shared pot, built on upstream `BasePaymaster`.
/// @dev Invariant it means to keep: `entryPoint.balanceOf(this) >= totalDeposits`.
///
///      THE BUG is inherited, not written. `BasePaymaster.withdrawTo` lets the
///      owner withdraw any amount of this paymaster's EntryPoint deposit. That
///      is correct for the paymaster `BasePaymaster` was written for, whose
///      whole deposit is the owner's money. Here the same deposit holds every
///      user's prepaid balance, and nothing in `withdrawTo` knows that.
///
///      It cannot be fixed by overriding, because `withdrawTo` is not
///      `virtual`. This does not compile:
///
///          function withdrawTo(address payable to, uint256 amount) public override onlyOwner {
///              require(amount <= freeBalance());
///              entryPoint.withdrawTo(to, amount);
///          }
///
///      solc: "Trying to override non-virtual function. Did you forget to add
///      "virtual"?"
contract PooledDepositPaymaster is BasePaymaster {
    mapping(address user => uint256 balance) public deposits;
    uint256 public totalDeposits;

    error InsufficientDeposit(address user, uint256 required, uint256 available);

    constructor(IEntryPoint entryPoint_) BasePaymaster(entryPoint_) {}

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

    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
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
