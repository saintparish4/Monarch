// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Every fixture below is a validation entry point plus exactly one thing to
// find, so a failing test names the rule it broke. The negative cases matter as
// much as the positive ones: a detector that fires on correct code gets turned
// off, and a detector that is turned off finds nothing.
//
// The coverage fixtures at the end are the exception. They exist so that every
// key in the opcode maps is proven to fire, and they group keys to keep the
// file readable.

// ---------------------------------------------------------------------------
// Negative cases
// ---------------------------------------------------------------------------

/// EXPECT: clean. Reads every spelling in `PERMITTED`, and the test fails if
/// any of them is reported. CHAINID is load-bearing: a sponsorship signature
/// that does not commit to the chain id replays across chains.
contract CleanPaymaster {
    function _value() internal view returns (uint256) {
        return msg.value;
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        uint256 chain;
        assembly {
            chain := chainid()
        }
        return (abi.encode(block.chainid, chain, msg.sender, msg.data, msg.sig, _value()), 0);
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

// ---------------------------------------------------------------------------
// Direct and transitive reads
// ---------------------------------------------------------------------------

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
contract NumberInModifier {
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

/// EXPECT: BLOCKHASH and NUMBER. Accounts are covered too, not only paymasters.
contract AccountEntropy {
    function validateUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (uint256)
    {
        return uint256(blockhash(block.number - 1));
    }
}

/// EXPECT: BLOCKHASH once. Two reads of the same builtin in one statement are
/// one finding, not two: the report is per line, and a line is fixed once.
/// Slither also drops identical results on its own, so this pins the outcome
/// rather than either mechanism.
contract RepeatedRead {
    function validateUserOp(bytes calldata, bytes32, uint256 n)
        external
        view
        returns (uint256)
    {
        return uint256(blockhash(n)) ^ uint256(blockhash(n + 1));
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

// ---------------------------------------------------------------------------
// Routes the walk has to follow besides internal calls
// ---------------------------------------------------------------------------

/// EXPECT: TIMESTAMP via the Yul builtin. Compiles to exactly the same opcode
/// as `block.timestamp`, and reads as "optimised" rather than suspicious.
contract AssemblyTimestamp {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        uint256 t;
        assembly {
            t := timestamp()
        }
        return ("", t);
    }
}

/// A library a paymaster might pull a time helper from.
library ValidityWindow {
    function until(uint256 span) internal view returns (uint256) {
        return block.timestamp + span;
    }
}

/// EXPECT: TIMESTAMP, attributed to the library's `until`.
contract LibraryTimestamp {
    using ValidityWindow for uint256;

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", uint256(1 days).until());
    }
}

/// EXPECT: TIMESTAMP, attributed to `clock`. An external call to itself is
/// still under the validation frame, and the tracer still sees it.
contract SelfCallTimestamp {
    function clock() external view returns (uint256) {
        return block.timestamp;
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", this.clock());
    }
}

/// EXPECT: clean. Its own `window` reads nothing banned.
contract SelfCallBase {
    function window() external view virtual returns (uint256) {
        return 0;
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", this.window());
    }
}

/// EXPECT: TIMESTAMP, attributed to the override. The `this.window()` call was
/// written in the base, but this contract is what gets deployed and this
/// override is what runs.
contract SelfCallOverride is SelfCallBase {
    function window() external view override returns (uint256) {
        return block.timestamp;
    }
}

// ---------------------------------------------------------------------------
// Which contracts are reported
// ---------------------------------------------------------------------------

/// EXPECT: silent. An interface has nothing to execute.
interface IPaymasterLike {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        returns (bytes memory, uint256);
}

/// EXPECT: silent. A library is never an ERC-4337 entity itself.
library ValidationHelpers {
    function validateUserOp(bytes calldata, bytes32, uint256) internal view returns (uint256) {
        return block.number;
    }
}

/// EXPECT: silent. Abstract, so it is never deployed as it stands.
abstract contract AbstractClockPaymaster {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", block.timestamp);
    }

    function _hook() internal virtual;
}

/// EXPECT: TIMESTAMP, reported against this contract, not the abstract base.
contract ConcreteClockPaymaster is AbstractClockPaymaster {
    function _hook() internal override {}
}

/// EXPECT: TIMESTAMP. Deployed in its own right and also extended below, which
/// is how paymasters are commonly versioned. `contracts_derived` would drop it.
contract PaymasterV1 {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        virtual
        returns (bytes memory, uint256)
    {
        return ("", block.timestamp);
    }
}

/// EXPECT: TIMESTAMP, the same inherited line, reported again for this contract.
contract PaymasterV2 is PaymasterV1 {}

// ---------------------------------------------------------------------------
// Coverage: every key in the opcode maps fires somewhere
// ---------------------------------------------------------------------------

/// EXPECT: DIFFICULTY, PREVRANDAO, GASLIMIT, BASEFEE, BLOBBASEFEE, BLOBHASH.
contract SolidityBlockFields {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return (
            abi.encode(
                block.difficulty,
                block.prevrandao,
                block.gaslimit,
                block.basefee,
                block.blobbasefee,
                blobhash(0)
            ),
            0
        );
    }
}

/// EXPECT: every banned Yul builtin that returns a value. `selfbalance()` and
/// `origin()` are reported under their Solidity spellings; see `rules.py`.
contract YulBuiltins {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        uint256[12] memory v;
        assembly {
            mstore(v, number())
            mstore(add(v, 0x20), prevrandao())
            mstore(add(v, 0x40), coinbase())
            mstore(add(v, 0x60), gaslimit())
            mstore(add(v, 0x80), basefee())
            mstore(add(v, 0xa0), blobbasefee())
            mstore(add(v, 0xc0), gasprice())
            mstore(add(v, 0xe0), balance(caller()))
            mstore(add(v, 0x100), selfbalance())
            mstore(add(v, 0x120), blockhash(0))
            mstore(add(v, 0x140), blobhash(0))
            mstore(add(v, 0x160), origin())
        }
        return (abi.encode(v), 0);
    }
}

/// EXPECT: SELFDESTRUCT, from Solidity and from Yul.
contract SelfDestructs {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256 maxCost)
        external
        returns (bytes memory, uint256)
    {
        if (maxCost == 1) selfdestruct(payable(msg.sender));
        if (maxCost == 2) {
            assembly {
                selfdestruct(caller())
            }
        }
        return ("", 0);
    }
}
