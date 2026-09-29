#!/usr/bin/env python
"""Tests for the ERC-7562 detectors.

Run with the interpreter Slither is installed under:

    $(which slither | xargs head -1 | cut -c3-) tests/test_detectors.py

No pytest dependency on purpose. The plugin has to be installed into Slither's
own environment to be useful at all, and that environment is not mine to add
packages to.

The detector is run end to end, registered with Slither exactly as the plugin
entry point registers it, and the assertions are made on the results it
renders. Calling its internals directly would skip the part most worth
locking in: which contracts get reported at all.
"""

import os
import re
import shutil
import sys
import tempfile
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from slither import Slither  # noqa: E402

from slither_erc7562.detectors import ValidationPhaseOpcodes, reachable_from  # noqa: E402
from slither_erc7562.rules import (  # noqa: E402
    BANNED_CALLS,
    BANNED_VARIABLES,
    PERMITTED,
    VALIDATION_ENTRY_POINTS,
)

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures", "Fixtures.sol")
SOLC = os.environ.get(
    "SOLC_BINARY", os.path.expanduser("~/.local/share/svm/0.8.28/solc-0.8.28")
)

# contract -> every (opcode, spelling) it should report, with multiplicity. A
# contract that is absent must report nothing; that is as load-bearing as the
# positive cases. Counts rather than sets, so a double report fails.
EXPECTED = {
    "DirectTimestamp": {("TIMESTAMP", "block.timestamp"): 1},
    "TransitiveTimestamp": {("TIMESTAMP", "block.timestamp"): 1},
    "NumberInModifier": {("NUMBER", "block.number"): 1},
    "BundlerAllowlist": {("ORIGIN", "tx.origin"): 1},
    "BalanceCheck": {("BALANCE", "balance(address)"): 1},
    "AccountEntropy": {
        ("BLOCKHASH", "blockhash(uint256)"): 1,
        ("NUMBER", "block.number"): 1,
    },
    "RepeatedRead": {("BLOCKHASH", "blockhash(uint256)"): 1},
    "TwoViolations": {
        ("COINBASE", "block.coinbase"): 1,
        ("GASPRICE", "tx.gasprice"): 1,
    },
    "AssemblyTimestamp": {("TIMESTAMP", "timestamp()"): 1},
    "LibraryTimestamp": {("TIMESTAMP", "block.timestamp"): 1},
    "SelfCallTimestamp": {("TIMESTAMP", "block.timestamp"): 1},
    "SelfCallOverride": {("TIMESTAMP", "block.timestamp"): 1},
    "ConcreteClockPaymaster": {("TIMESTAMP", "block.timestamp"): 1},
    "PaymasterV1": {("TIMESTAMP", "block.timestamp"): 1},
    "PaymasterV2": {("TIMESTAMP", "block.timestamp"): 1},
    "SolidityBlockFields": {
        ("DIFFICULTY", "block.difficulty"): 1,
        ("PREVRANDAO", "block.prevrandao"): 1,
        ("GASLIMIT", "block.gaslimit"): 1,
        ("BASEFEE", "block.basefee"): 1,
        ("BLOBBASEFEE", "block.blobbasefee"): 1,
        ("BLOBHASH", "blobhash(uint256)"): 1,
    },
    "YulBuiltins": {
        ("NUMBER", "number()"): 1,
        ("PREVRANDAO", "prevrandao()"): 1,
        ("COINBASE", "coinbase()"): 1,
        ("GASLIMIT", "gaslimit()"): 1,
        ("BASEFEE", "basefee()"): 1,
        ("BLOBBASEFEE", "blobbasefee()"): 1,
        ("GASPRICE", "gasprice()"): 1,
        ("BALANCE", "balance(uint256)"): 1,
        # `selfbalance()`: Slither rewrites it to `address(this).balance`.
        ("BALANCE", "balance(address)"): 1,
        ("BLOCKHASH", "blockhash(uint256)"): 1,
        ("BLOBHASH", "blobhash(uint256)"): 1,
        # `origin()`: Slither rewrites it to `tx.origin`.
        ("ORIGIN", "tx.origin"): 1,
    },
    "SelfDestructs": {
        ("SELFDESTRUCT", "selfdestruct(address)"): 1,
        ("SELFDESTRUCT", "selfdestruct(uint256)"): 1,
    },
}

# Where the finding should be attributed, for the cases where that is the point.
EXPECTED_LOCATION = {
    "TransitiveTimestamp": "_window",
    "NumberInModifier": "whenUnlocked",
    "LibraryTimestamp": "until",
    "SelfCallTimestamp": "clock",
    "SelfCallOverride": "window",
}

# Contracts that declare a validation entry point and must stay silent. Listed
# so that a fixture that stops compiling, or is renamed, fails loudly instead
# of passing by absence.
EXPECTED_SILENT = {
    "CleanPaymaster",
    "ClockOutsideValidation",
    "SelfCallBase",
    "IPaymasterLike",
    "ValidationHelpers",
    "AbstractClockPaymaster",
}

# The fixture that must read every PERMITTED spelling and report none of them.
PERMITTED_FIXTURE = "CleanPaymaster"

# The rendered description, as `_detect` builds it.
DESCRIPTION = re.compile(
    r"^(?P<contract>\w+)\.(?P<entry>\w+) reaches (?P<opcode>\w+) "
    r"via `(?P<spelling>[^`]+)`(?: in (?P<location>\w+))?, "
)


def expected_count():
    return sum(sum(findings.values()) for findings in EXPECTED.values())


def analyse():
    # Copy the fixture somewhere with no build system above it before analysing.
    # crytic-compile walks up from the working directory looking for a build
    # system, and this package lives inside a Foundry project — without this the
    # test shells out to `forge` and fails for reasons that have nothing to do
    # with the detector.
    workdir = tempfile.mkdtemp(prefix="erc7562-")
    shutil.copy(FIXTURES, os.path.join(workdir, "Fixtures.sol"))
    origin = os.getcwd()
    try:
        # The walk starts from the working directory, not from the target path.
        os.chdir(workdir)
        sl = Slither("Fixtures.sol", solc=SOLC, compile_force_framework="solc")
        sl.register_detector(ValidationPhaseOpcodes)
        results = [r for per_detector in sl.run_detectors() for r in per_detector]
        return sl, results
    finally:
        os.chdir(origin)
        shutil.rmtree(workdir, ignore_errors=True)


def spellings_read(function):
    """Every Solidity variable and builtin spelling a function's nodes touch."""
    spellings = set()
    for node in function.nodes:
        spellings.update(str(v) for v in node.solidity_variables_read)
        spellings.update(str(getattr(c, "function", c)) for c in node.solidity_calls)
    return spellings


def main():
    sl, results = analyse()
    failures = []

    found = {}
    where = {}
    for result in results:
        match = DESCRIPTION.match(result["description"])
        if not match:
            failures.append(f"unparseable result: {result['description']!r}")
            continue
        contract = match["contract"]
        found.setdefault(contract, Counter())[(match["opcode"], match["spelling"])] += 1
        where.setdefault(contract, set()).add(match["location"] or match["entry"])

    for name, expected in EXPECTED.items():
        actual = found.get(name, Counter())
        if actual != Counter(expected):
            failures.append(f"{name}: expected {dict(expected)}, got {dict(actual)}")
        else:
            print(f"  ok  {name:<24} {sorted(op for op, _ in expected)}")

    for name, expected_fn in EXPECTED_LOCATION.items():
        if expected_fn not in where.get(name, set()):
            failures.append(
                f"{name}: expected the finding attributed to {expected_fn}, "
                f"got {sorted(where.get(name, set()))}"
            )
        else:
            print(f"  ok  {name:<24} attributed to {expected_fn}")

    unexpected = set(found) - set(EXPECTED)
    if unexpected:
        failures.append(f"findings in contracts with no expectation: {sorted(unexpected)}")

    # Silence only counts if the contract was there to be silent about.
    declared = {c.name for c in sl.contracts}
    for name in sorted(EXPECTED_SILENT):
        if name not in declared:
            failures.append(f"{name}: expected silent, but the fixture is missing")
        elif name in found:
            failures.append(f"{name}: expected silent, got {dict(found[name])}")
        else:
            print(f"  ok  {name:<24} silent")

    # Every key in the opcode maps must be proven to fire. A key no source can
    # produce is a coverage claim the detector cannot keep.
    fired = {spelling for counts in found.values() for _, spelling in counts}
    dead = (set(BANNED_VARIABLES) | set(BANNED_CALLS)) - fired
    if dead:
        failures.append(f"map keys no fixture fires: {sorted(dead)}")
    else:
        print(f"  ok  every map key fires ({len(fired)} spellings)")

    # PERMITTED is enforced, not decorative: the clean fixture must actually
    # read each spelling, and (checked above) must report nothing.
    clean = next(c for c in sl.contracts if c.name == PERMITTED_FIXTURE)
    touched = set()
    for entry in clean.functions:
        if entry.name in VALIDATION_ENTRY_POINTS:
            for function in reachable_from(entry):
                touched |= spellings_read(function)
    overlap = PERMITTED & (set(BANNED_VARIABLES) | set(BANNED_CALLS))
    if overlap:
        failures.append(f"spellings both permitted and banned: {sorted(overlap)}")
    missing = PERMITTED - touched
    if missing:
        failures.append(f"{PERMITTED_FIXTURE} does not read permitted {sorted(missing)}")
    if not overlap and not missing:
        print(f"  ok  every permitted spelling read, none reported ({len(PERMITTED)})")

    if len(results) != expected_count():
        failures.append(f"expected {expected_count()} results in total, got {len(results)}")

    print()
    if failures:
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"\n{len(failures)} failed")
        return 1
    print(f"all passed: {expected_count()} findings across {len(EXPECTED)} fixtures")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--expected-count"]:
        # For run-corpus.sh, so its self-check row never hardcodes a number.
        print(expected_count())
        sys.exit(0)
    sys.exit(main())
