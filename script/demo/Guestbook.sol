// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Guestbook
/// @notice The thing the demo's users actually do. Deliberately trivial.
///
/// @dev This is NOT part of Monarch's audited surface. It lives under
///      `script/` because `foundry.toml` excludes that path from lint and
///      coverage, and because a demo target with its own storage would
///      otherwise read as a second production contract in `contracts/`.
///
///      Its only job is to give the demo a state change that a block explorer
///      shows: a wallet holding zero ETH writes a message, and the message is
///      there afterwards. Nothing here is reachable from the paymaster.
contract Guestbook {
    struct Entry {
        address author;
        uint64 timestamp;
        string message;
    }

    Entry[] private _entries;

    event Signed(address indexed author, uint256 indexed index, string message);

    error MessageEmpty();
    error MessageTooLong(uint256 length);

    /// @dev 280 characters, because an unbounded string here is an unbounded
    ///      gas cost billed to the app's budget rather than to the caller.
    uint256 public constant MAX_MESSAGE_BYTES = 280;

    function sign(string calldata message) external {
        uint256 len = bytes(message).length;
        if (len == 0) revert MessageEmpty();
        if (len > MAX_MESSAGE_BYTES) revert MessageTooLong(len);

        _entries.push(Entry({author: msg.sender, timestamp: uint64(block.timestamp), message: message}));
        emit Signed(msg.sender, _entries.length - 1, message);
    }

    function count() external view returns (uint256) {
        return _entries.length;
    }

    /// @notice The most recent `n` entries, newest first.
    /// @dev Bounded and paginated from the tail, so the demo page never asks a
    ///      node for an array that grows without limit.
    function latest(uint256 n) external view returns (Entry[] memory out) {
        uint256 total = _entries.length;
        if (n > total) n = total;
        out = new Entry[](n);
        for (uint256 i = 0; i < n; ++i) {
            out[i] = _entries[total - 1 - i];
        }
    }
}
