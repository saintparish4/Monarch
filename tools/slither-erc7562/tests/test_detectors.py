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

from slither_erc7562.detectors import (  # noqa: E402
    ValidationPhaseOpcodes,
    entry_points,
    reachable_from,
)
from slither_erc7562.rules import (  # noqa: E402
    BANNED_CALLS,
    BANNED_VARIABLES,
    PERMITTED,
    RULES,
    VALIDATION_ENTRY_POINTS,
)

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures", "Fixtures.sol")
EXAMPLES_DIR = os.path.join(os.path.dirname(__file__), "..", "examples")
README = os.path.join(os.path.dirname(__file__), "..", "README.md")
# solc 0.8.28: $SOLC_BINARY if set, else Foundry's copy if there is one, else
# whatever `solc` is on PATH (`solc-select install 0.8.28 && solc-select use 0.8.28`).
_FOUNDRY_SOLC = os.path.expanduser("~/.local/share/svm/0.8.28/solc-0.8.28")
SOLC = os.environ.get("SOLC_BINARY") or (
    _FOUNDRY_SOLC if os.path.exists(_FOUNDRY_SOLC) else shutil.which("solc") or "solc"
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
    "HookReadsClock": {("TIMESTAMP", "block.timestamp"): 1},
    "HookCallsSuper": {("TIMESTAMP", "block.timestamp"): 1},
    "FreeFunctionTimestamp": {("TIMESTAMP", "block.timestamp"): 1},
    "LinkedLibraryTimestamp": {("TIMESTAMP", "block.timestamp"): 1},
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
    "InvalidOpcode": {("INVALID", "invalid()"): 1},
}

# Where the finding should be attributed, for the cases where that is the point.
EXPECTED_LOCATION = {
    "TransitiveTimestamp": "_window",
    "NumberInModifier": "whenUnlocked",
    "LibraryTimestamp": "until",
    "SelfCallTimestamp": "clock",
    "SelfCallOverride": "window",
    "HookReadsClock": "_validate",
    "HookCallsSuper": "_validate",
    "FreeFunctionTimestamp": "fileLevelClock",
    "LinkedLibraryTimestamp": "until",
}

# Contracts the detector scans and must stay silent about, because nothing
# banned runs during their validation. Listed so that a fixture that stops
# compiling, or is renamed, fails loudly instead of passing by absence.
EXPECTED_SILENT = {
    "CleanPaymaster",
    "ClockOutsideValidation",
    "SelfCallBase",
    "HookReplacesClock",
}

# Contracts that declare a validation entry point and are never scanned at all:
# an interface, a library, and abstract bases. Kept apart from the set above
# because the two silences mean different things. One says "looked, and found
# nothing"; this one says "nothing here is ever deployed as it stands".
NEVER_SCANNED = {
    "IPaymasterLike",
    "ValidationHelpers",
    "AbstractClockPaymaster",
    "HookedPaymaster",
    "ClockByDefault",
}

# Contracts that run a banned opcode during validation and are not reported.
# These are wrong answers, held in place on purpose: each is a limit the README
# documents under "What it does not check", and the reason given here is the
# one given there. If a change makes one of them fire, move it to EXPECTED and
# take the limit out of the README in the same change.
KNOWN_MISSES = {
    "AsksAnotherContract": "the walk stops at a call to another contract",
    "CastSelfCall": "a self-call through a cast is not recognised as one",
    "FunctionPointerClock": "a call through a function pointer is not resolved",
    "DeploysInValidation": "CREATE is not reported (OP-031 and OP-032 exceptions)",
}

# The examples in `examples/` are documentation, and the README quotes what each
# one reports. Checked here with the same exactness as the fixtures, so the
# documentation cannot drift from the detector. file -> contract -> findings;
# every other contract with an entry point in that file must stay silent.
EXAMPLES = {
    "Clock.sol": {"ClockCheckingPaymaster": {("TIMESTAMP", "block.timestamp"): 1}},
    "HidingPlaces.sol": {
        "ClockInModifier": {("TIMESTAMP", "block.timestamp"): 1},
        "ClockInLibrary": {("TIMESTAMP", "block.timestamp"): 1},
        "ClockInAssembly": {("TIMESTAMP", "timestamp()"): 1},
    },
    "Balance.sol": {"BalanceCheckingPaymaster": {("BALANCE", "balance(address)"): 1}},
    "BundlerAllowlist.sol": {"OriginAllowlistPaymaster": {("ORIGIN", "tx.origin"): 1}},
    "OutsideValidation.sol": {},
}
# Scanned and silent, as above: each of these must have been looked at.
EXAMPLES_SILENT = {
    "Clock.sol": {"WindowReturningPaymaster"},
    "Balance.sol": {"DepositLedgerPaymaster"},
    # Silent only because of its `slither-disable-next-line`, which is the point.
    "BundlerAllowlist.sol": {"TriagedAllowlistPaymaster"},
    "OutsideValidation.sol": {"ClockInPostOpPaymaster"},
}

# The opcode lists of the two rules this detector reports, as ERC-7562 publishes
# them (eips.ethereum.org/EIPS/eip-7562#opcode-rules). Kept here rather than
# read from `rules.RULES`, so that a finding filed under the wrong rule fails
# against the spec instead of agreeing with itself.
SPEC_RULES = {
    "OP-011": {
        "ORIGIN", "GASPRICE", "BLOCKHASH", "COINBASE", "TIMESTAMP", "NUMBER",
        "PREVRANDAO", "DIFFICULTY", "GASLIMIT", "BASEFEE", "BLOBHASH",
        "BLOBBASEFEE", "CREATE", "INVALID", "SELFDESTRUCT",
    },
    "OP-080": {"BALANCE", "SELFBALANCE"},
}


def spec_rule(opcode):
    return next((rule for rule, opcodes in SPEC_RULES.items() if opcode in opcodes), None)


# The fixture that must read every PERMITTED spelling and report none of them.
PERMITTED_FIXTURE = "CleanPaymaster"

# The rendered description, as `_detect` builds it.
DESCRIPTION = re.compile(
    r"^(?P<contract>\w+)\.(?P<entry>\w+) reaches (?P<opcode>\w+) "
    r"via `(?P<spelling>[^`]+)`(?: in (?P<location>\w+))?\. "
    r"ERC-7562 (?P<rule>[A-Z]+-\d{3}) "
)


def expected_count():
    return sum(sum(findings.values()) for findings in EXPECTED.values())


def analyse(source=FIXTURES, siblings=()):
    # Copy the source somewhere with no build system above it before analysing.
    # crytic-compile walks up from the working directory looking for a build
    # system, and this package lives inside a Foundry project — without this the
    # test shells out to `forge` and fails for reasons that have nothing to do
    # with the detector.
    workdir = tempfile.mkdtemp(prefix="erc7562-")
    for path in (source, *siblings):
        shutil.copy(path, os.path.join(workdir, os.path.basename(path)))
    origin = os.getcwd()
    try:
        # The walk starts from the working directory, not from the target path.
        os.chdir(workdir)
        sl = Slither(os.path.basename(source), solc=SOLC, compile_force_framework="solc")
        sl.register_detector(ValidationPhaseOpcodes)
        results = [r for per_detector in sl.run_detectors() for r in per_detector]
        return sl, results
    finally:
        os.chdir(origin)
        shutil.rmtree(workdir, ignore_errors=True)


def scanned(sl):
    """Names of the contracts whose validation the detector walked."""
    return {
        contract.name
        for unit in sl.compilation_units
        for contract, _ in entry_points(unit)
    }


def partly_parsed(sl):
    """Contracts Slither gave up on part of, and went on without.

    Slither logs an error when it cannot build its IR for a function, marks the
    contract, and carries on. The function it skipped then has nothing in it
    for a detector to find, so that contract is silent whatever it does. A
    clean result from one of these is no result.
    """
    return sorted(c.name for c in sl.contracts if c.is_incorrectly_constructed)


def check_examples():
    """Failures in `examples/`, and the number of findings it rendered."""
    failures = []
    total = 0
    shared = os.path.join(EXAMPLES_DIR, "UserOperation.sol")
    for filename, expected in EXAMPLES.items():
        sl, results = analyse(os.path.join(EXAMPLES_DIR, filename), siblings=(shared,))
        total += len(results)
        found = {}
        for result in results:
            match = DESCRIPTION.match(result["description"])
            if not match:
                failures.append(f"{filename}: unparseable result {result['description']!r}")
                continue
            key = (match["opcode"], match["spelling"])
            found.setdefault(match["contract"], Counter())[key] += 1
        for name in sorted(set(expected) | set(found)):
            if found.get(name, Counter()) != Counter(expected.get(name, {})):
                failures.append(
                    f"{filename}: {name} expected {expected.get(name, {})}, "
                    f"got {dict(found.get(name, {}))}"
                )
        for name in partly_parsed(sl):
            failures.append(f"{filename}: Slither only partly parsed {name}")
        looked_at = scanned(sl)
        for name in sorted(EXAMPLES_SILENT.get(filename, set()) | set(expected)):
            if name not in looked_at:
                failures.append(f"{filename}: {name} was never scanned, or is missing")
        if not any(f.startswith(filename) for f in failures):
            print(f"  ok  examples/{filename:<22} {sum(len(v) for v in expected.values())} reported")
    return failures, total


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
        # The rule named must be the one ERC-7562 files that opcode under.
        if match["rule"] != spec_rule(match["opcode"]):
            failures.append(
                f"{contract}: {match['opcode']} reported under {match['rule']}, "
                f"but ERC-7562 lists it under {spec_rule(match['opcode'])}"
            )
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

    # Silence only counts if the contract was looked at. "Declared" is not
    # enough: a contract the detector skips is silent whatever is in it.
    declared = {c.name for c in sl.contracts}
    looked_at = scanned(sl)
    for name in partly_parsed(sl):
        failures.append(f"{name}: Slither only partly parsed it, so no result counts")
    for name in sorted(EXPECTED_SILENT):
        if name not in looked_at:
            failures.append(f"{name}: expected silent, but it was never scanned")
        elif name in found:
            failures.append(f"{name}: expected silent, got {dict(found[name])}")
        else:
            print(f"  ok  {name:<24} silent")

    for name in sorted(NEVER_SCANNED):
        if name not in declared:
            failures.append(f"{name}: expected declared and unscanned, but it is missing")
        elif name in looked_at:
            failures.append(f"{name}: scanned, but it is never deployed as it stands")
        else:
            print(f"  ok  {name:<24} not scanned")

    for name, limit in sorted(KNOWN_MISSES.items()):
        if name not in looked_at:
            failures.append(f"{name}: a known miss, but it was never scanned")
        elif name in found:
            failures.append(
                f"{name}: a known miss that is now reported as {dict(found[name])}. "
                f"Move it to EXPECTED and take the limit out of the README"
            )
        else:
            print(f"  miss {name:<23} silent: {limit}")

    # Every contract the detector scanned has to be accounted for above, so a
    # new fixture cannot pass by being silent and unlisted.
    unlisted = looked_at - set(EXPECTED) - EXPECTED_SILENT - set(KNOWN_MISSES)
    if unlisted:
        failures.append(f"scanned contracts with no expectation: {sorted(unlisted)}")

    # Every key in the opcode maps must be proven to fire. A key no source can
    # produce is a coverage claim the detector cannot keep.
    fired = {spelling for counts in found.values() for _, spelling in counts}
    dead = (set(BANNED_VARIABLES) | set(BANNED_CALLS)) - fired
    if dead:
        failures.append(f"map keys no fixture fires: {sorted(dead)}")
    else:
        print(f"  ok  every map key fires ({len(fired)} spellings)")

    # Every opcode the maps can report must name its rule and say why. A
    # finding without one would render as a KeyError halfway through a run.
    unexplained = (set(BANNED_VARIABLES.values()) | set(BANNED_CALLS.values())) - set(RULES)
    if unexplained:
        failures.append(f"opcodes with no ERC-7562 rule attached: {sorted(unexplained)}")
    else:
        print(f"  ok  every opcode names its rule ({len(RULES)} opcodes)")

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

    example_failures, example_total = check_examples()
    failures += example_failures

    # The README quotes the fixture count in its results table.
    with open(README, encoding="utf-8") as handle:
        quoted = re.search(r"Fixture suite \(self-check\)\s*\|\s*(\d+)", handle.read())
    if not quoted:
        failures.append("README: no fixture-suite row in the results table")
    elif int(quoted[1]) != expected_count():
        failures.append(
            f"README: results table says {quoted[1]} fixture findings, "
            f"the suite expects {expected_count()}"
        )
    else:
        print(f"  ok  README quotes the fixture count ({quoted[1]})")

    print()
    if failures:
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"\n{len(failures)} failed")
        return 1
    print(
        f"all passed: {expected_count()} findings across {len(EXPECTED)} fixtures, "
        f"{len(KNOWN_MISSES)} known misses held, "
        f"{example_total} across {len(EXAMPLES)} example files"
    )
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--expected-count"]:
        # For run-corpus.sh, so its self-check row never hardcodes a number.
        print(expected_count())
        sys.exit(0)
    sys.exit(main())
