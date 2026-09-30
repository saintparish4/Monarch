// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./UserOperation.sol";

// The detector's known false-positive class: a banned opcode behind a flag
// that can switch it off.
//
// Both paymasters let their owner restrict sponsorship to chosen bundlers, and
// ship with the restriction off. With `allowAnyBundler` set, `||` short-circuits
// and `tx.origin` is never read, so on that path the paymaster is compliant.
// The detector reports reachability, not paths, and cannot see that.

/// REPORTED: ORIGIN via `tx.origin`.
contract OriginAllowlistPaymaster {
    bool public allowAnyBundler = true;
    mapping(address bundler => bool allowed) public isBundlerAllowed;

    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        if (!(allowAnyBundler || isBundlerAllowed[tx.origin])) return ("", 1);
        return ("", 0);
    }
}

/// SILENT, because a person triaged it. Suppress the one line, and write down
/// why next to it: the day someone turns the allowlist on, a bundler that
/// enforces ERC-7562 will drop this paymaster's operations, and the comment is
/// what tells them that.
contract TriagedAllowlistPaymaster {
    bool public allowAnyBundler = true;
    mapping(address bundler => bool allowed) public isBundlerAllowed;

    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        // Only read when the allowlist is on, which is for private bundlers.
        // slither-disable-next-line erc7562-validation-opcodes
        if (!(allowAnyBundler || isBundlerAllowed[tx.origin])) return ("", 1);
        return ("", 0);
    }
}
