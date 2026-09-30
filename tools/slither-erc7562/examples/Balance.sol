// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./UserOperation.sol";

// ERC-7562 OP-080: BALANCE and SELFBALANCE are allowed only in a staked entity.
//
// Both paymasters sponsor a sender only if the sender has something at stake:
// the first reads the sender's ETH balance, the second a deposit the sender
// made into the paymaster.

/// REPORTED: BALANCE via `balance(address)`.
///
/// Unstaked, a bundler drops every operation this sponsors. Staked, OP-080
/// allows it, and the finding does not apply: suppress it on that line and say
/// why. The detector cannot see stake, which is a deployment fact rather than a
/// source fact, so it reports the read either way.
contract BalanceCheckingPaymaster {
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        return ("", userOp.sender.balance >= maxCost ? 0 : 1);
    }
}

/// SILENT. The usual fix: keep the number in the paymaster's own storage, keyed
/// by the sender, so validation reads a slot instead of the environment. This
/// version executes no banned opcode. Whether a bundler accepts its storage
/// read is a question for ERC-7562's storage rules (STO-*), which this detector
/// does not check.
contract DepositLedgerPaymaster {
    mapping(address sender => uint256 balance) public deposits;

    function depositFor(address sender) external payable {
        deposits[sender] += msg.value;
    }

    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        return ("", deposits[userOp.sender] >= maxCost ? 0 : 1);
    }
}
