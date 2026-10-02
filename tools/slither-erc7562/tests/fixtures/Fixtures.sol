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
// Which implementation a call resolves to
// ---------------------------------------------------------------------------

/// The template-method shape, which is how upstream's `BasePaymaster` and most
/// paymasters built on it are written: the entry point lives in an abstract
/// base and calls a hook the deployed contract fills in.
abstract contract HookedPaymaster {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", _validate());
    }

    function _validate() internal view virtual returns (uint256);
}

/// EXPECT: TIMESTAMP, attributed to `_validate`. The entry point was written
/// in the base, and the read is in the override it never mentions.
contract HookReadsClock is HookedPaymaster {
    function _validate() internal view override returns (uint256) {
        return block.timestamp;
    }
}

/// The same shape with a default hook that reads the clock.
abstract contract ClockByDefault {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", _validate());
    }

    function _validate() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}

/// EXPECT: clean. The override replaces the default, so the read in the base
/// is code this contract never runs. Reporting it would be a false alarm about
/// a line the author already fixed.
contract HookReplacesClock is ClockByDefault {
    function _validate() internal pure override returns (uint256) {
        return 0;
    }
}

/// EXPECT: TIMESTAMP. The override calls back into the default it replaced.
contract HookCallsSuper is ClockByDefault {
    function _validate() internal view override returns (uint256) {
        return super._validate() + 1;
    }
}

/// A function declared outside any contract.
function fileLevelClock() view returns (uint256) {
    return block.timestamp;
}

/// EXPECT: TIMESTAMP, attributed to the file-level function.
contract FreeFunctionTimestamp {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", fileLevelClock());
    }
}

/// A library with an external function, which is linked and reached by
/// DELEGATECALL instead of being inlined.
library LinkedWindow {
    function until(uint256 span) external view returns (uint256) {
        return block.timestamp + span;
    }
}

/// EXPECT: TIMESTAMP, attributed to the library's `until`. The delegatecall
/// runs under the validation frame like any other code.
contract LinkedLibraryTimestamp {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", LinkedWindow.until(1 days));
    }
}

// ---------------------------------------------------------------------------
// Known misses
//
// Each contract below runs a banned opcode during validation, and a bundler
// would drop its operations. The detector says nothing about any of them. They
// are the README's "what it does not check" written as code: the test holds
// each one silent, so closing one of these gaps is a deliberate edit to the
// test and the README together, and a change that closes one by accident
// cannot pass unnoticed.
// ---------------------------------------------------------------------------

/// Not an ERC-4337 entity. Something a paymaster might ask the time.
contract ClockOracle {
    function clock() external view returns (uint256) {
        return block.timestamp;
    }
}

/// KNOWN MISS: TIMESTAMP, in another contract. The walk stops at a call to a
/// different address, because which code sits behind it is a deployment fact.
/// The source being in the same file, as it is here, does not change that.
contract AsksAnotherContract {
    ClockOracle internal oracle;

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", oracle.clock());
    }
}

interface IClock {
    function clock() external view returns (uint256);
}

/// KNOWN MISS: TIMESTAMP, through a self-call written as a cast. It reaches the
/// same code `this.clock()` does, and `SelfCallTimestamp` above is reported.
contract CastSelfCall {
    function clock() external view returns (uint256) {
        return block.timestamp;
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        return ("", IClock(address(this)).clock());
    }
}

/// KNOWN MISS: TIMESTAMP, through a function-typed variable. The call is not
/// resolved to the function the variable holds.
contract FunctionPointerClock {
    function _clock() internal view returns (uint256) {
        return block.timestamp;
    }

    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        view
        returns (bytes memory, uint256)
    {
        function() internal view returns (uint256) read = _clock;
        return ("", read());
    }
}

contract Deployed {}

/// KNOWN MISS: CREATE. OP-011 lists it, with an exception for deploying the
/// sender that this detector cannot tell apart from any other use, so `new` is
/// not reported at all.
contract DeploysInValidation {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256)
        external
        returns (bytes memory, uint256)
    {
        new Deployed();
        return ("", 0);
    }
}

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

/// EXPECT: INVALID, which ERC-7562 lists in OP-011 and only Yul can spell.
/// Solidity's `assert` compiles to a Panic revert rather than to INVALID, so the
/// `assert` here is correctly not reported.
contract InvalidOpcode {
    function validatePaymasterUserOp(bytes calldata, bytes32, uint256 maxCost)
        external
        pure
        returns (bytes memory, uint256)
    {
        assert(maxCost != 1);
        if (maxCost == 2) {
            assembly {
                invalid()
            }
        }
        return ("", 0);
    }
}
