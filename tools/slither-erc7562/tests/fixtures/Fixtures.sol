// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Every fixture below is a validation entry point plus exactly one thing to
// find, so a failing test names the rule it broke. The negative cases matter as
// much as the positive ones: a detector that fires on correct code gets turned
// off, and a detector that is turned off finds nothing.

/// EXPECT: clean. CHAINID is permitted, and is load-bearing — a sponsorship
/// signature that does not commit to the chain id replays across chains.
contract CleanPaymaster {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return (abi.encode(block.chainid, msg.sender, address(this)), 0);
    }
}

/// EXPECT: clean. Reading the clock outside validation is ordinary code.
contract ClockOutsideValidation {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        pure
        returns (bytes memory, uint256)
    {
        return ("", 0);
    }

    function sweepAfter(uint256 deadline) external view returns (bool) {
        return block.timestamp > deadline;
    }
}

/// EXPECT: TIMESTAMP. The shape of the original Monarch defect — building a
/// validity window from the clock instead of from a signed pair.
contract DirectTimestamp {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", block.timestamp + 1 days);
    }
}

/// EXPECT: TIMESTAMP, attributed to `_window`, two internal calls deep.
contract TransitiveTimestamp {
    function _window() internal view returns (uint256) {
        return block.timestamp + 1 days;
    }

    function _outer() internal view returns (uint256) {
        return _window();
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", _outer());
    }
}

/// EXPECT: NUMBER, attributed to the modifier. The easiest place for a banned
/// opcode to hide from a reader, because the reader is looking at the body.
contract TimestampInModifier {
    uint256 public unlockAt;

    modifier whenUnlocked() {
        require(block.number >= unlockAt, "locked");
        _;
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        whenUnlocked
        returns (bytes memory, uint256)
    {
        return ("", 0);
    }
}

/// EXPECT: ORIGIN. A bundler allowlist, which is what production paymasters
/// actually use this for.
contract BundlerAllowlist {
    mapping(address => bool) public allowed;

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        require(allowed[tx.origin], "bundler not allowed");
        return ("", 0);
    }
}

/// EXPECT: BALANCE.
contract BalanceCheck {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        require(address(this).balance > 1 ether, "broke");
        return ("", 0);
    }
}

/// EXPECT: BLOCKHASH. Accounts are covered too, not only paymasters.
contract AccountEntropy {
    function validateUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (uint256)
    {
        return uint256(blockhash(block.number - 1));
    }
}

/// EXPECT: COINBASE and GASPRICE from one entry point.
contract TwoViolations {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return (abi.encode(block.coinbase, tx.gasprice), 0);
    }
}
