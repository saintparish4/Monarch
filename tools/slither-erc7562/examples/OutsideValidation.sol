// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./UserOperation.sol";

// The rules apply to validation only. `postOp` runs in the execution phase,
// where the clock and the rest of the environment are fair game.

/// SILENT. Validation decides from its inputs alone; `postOp` records when the
/// operation happened.
contract ClockInPostOpPaymaster {
    mapping(address sender => uint256 at) public lastSponsoredAt;

    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256)
        external
        pure
        returns (bytes memory context, uint256 validationData)
    {
        return (abi.encode(userOp.sender), 0);
    }

    function postOp(uint8, bytes calldata context, uint256, uint256) external {
        lastSponsoredAt[abi.decode(context, (address))] = block.timestamp;
    }
}
