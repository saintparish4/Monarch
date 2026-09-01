#!/usr/bin/env python
"""Tests for the ERC-7562 detectors.

Run with the interpreter Slither is installed under:

    $(which slither | xargs head -1 | cut -c3-) tests/test_detectors.py

No pytest dependency on purpose. The plugin has to be installed into Slither's
own environment to be useful at all, and that environment is not mine to add
packages to.
"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from slither import Slither  # noqa: E402

from slither_erc7562.detectors import ValidationPhaseOpcodes  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures", "Fixtures.sol")
SOLC = os.environ.get(
    "SOLC_BINARY", os.path.expanduser("~/.local/share/svm/0.8.28/solc-0.8.28")
)

# contract -> the opcodes it should report, exactly. An empty set is a negative
# case and is as load-bearing as the positive ones.
EXPECTED = {
    "CleanPaymaster": set(),
    "ClockOutsideValidation": set(),
    "DirectTimestamp": {"TIMESTAMP"},
    "TransitiveTimestamp": {"TIMESTAMP"},
    "TimestampInModifier": {"NUMBER"},
    "BundlerAllowlist": {"ORIGIN"},
    "BalanceCheck": {"BALANCE"},
    "AccountEntropy": {"BLOCKHASH", "NUMBER"},
    "TwoViolations": {"COINBASE", "GASPRICE"},
}

# Where the finding should be attributed, for the cases where that is the point.
EXPECTED_LOCATION = {
    "TransitiveTimestamp": "_window",
    "TimestampInModifier": "whenUnlocked",
}


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
        return _collect(sl)
    finally:
        os.chdir(origin)
        shutil.rmtree(workdir, ignore_errors=True)


def _collect(sl):
    found = {}
    where = {}
    for unit in sl.compilation_units:
        for contract in unit.contracts:
            for entry in contract.functions:
                if entry.name not in ("validatePaymasterUserOp", "validateUserOp"):
                    continue
                hits = ValidationPhaseOpcodes._scan(entry)
                found.setdefault(contract.name, set()).update(h[2] for h in hits)
                for function, _node, opcode, _spelling in hits:
                    where.setdefault(contract.name, set()).add(function.name)
    return found, where


def main():
    found, where = analyse()
    failures = []

    for name, expected in EXPECTED.items():
        actual = found.get(name, set())
        if actual != expected:
            failures.append(f"{name}: expected {sorted(expected)}, got {sorted(actual)}")
        else:
            print(f"  ok  {name:<24} {sorted(expected) or 'clean'}")

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

    print()
    if failures:
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"\n{len(failures)} failed")
        return 1
    print(f"{len(EXPECTED) + len(EXPECTED_LOCATION)} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
