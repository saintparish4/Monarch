#!/usr/bin/env python
"""Run the ERC-7562 detector over the failure cases and check what it reports.

Each case says whether a static check can see its failure. This holds those
claims to account: exactly the contracts listed below are reported, exactly as
often as listed, and every other paymaster in `cases/` is analysed and stays
silent. If a case's answer changes, this fails and the case's README is wrong.

Needs `slither-analyzer` with `slither-erc7562` installed in the same
environment, and `forge`. Run from the repository root with that environment's
interpreter:

    python cases/check-detector.py

Slither logs one ERROR while it runs, about generating IR for the EntryPoint's
`_EIP712Version`. That is Slither failing on a function in OpenZeppelin's
`EIP712`, which the cases compile because they deploy the real EntryPoint. It
does not touch any paymaster, and the counts below are unaffected.
"""

import os
import sys
from collections import Counter

from slither import Slither
from slither_erc7562.detectors import ValidationPhaseOpcodes

# Contract -> number of findings. Anything else reported is a failure.
EXPECTED = {"ClockCheckingPaymaster": 1}

# The paymasters that must be present and silent. Listed so that a case that
# stops compiling, or is renamed, fails here instead of passing by absence.
EXPECTED_SILENT = {
    "WindowReturningPaymaster",
    "CappedPostOpPaymaster",
    "FlooredPostOpPaymaster",
    "UnflooredDepositPaymaster",
    "FlooredDepositPaymaster",
    "CheckedBudgetPaymaster",
    "ReservingBudgetPaymaster",
    "BoundedBudgetPaymaster",
    "CallBlindSponsorPaymaster",
    "CallBoundSponsorPaymaster",
    "PooledDepositPaymaster",
    "SolventDepositPaymaster",
}


def main():
    # The cases compile only under their own profile, and crytic-compile skips
    # a profile's test directory unless told to compile everything. Under this
    # profile the test directory is `cases/` itself.
    os.environ["FOUNDRY_PROFILE"] = "cases"
    sl = Slither(".", foundry_compile_all=True)
    sl.register_detector(ValidationPhaseOpcodes)
    results = [r for per_detector in sl.run_detectors() for r in per_detector]

    found = Counter(r["description"].split(".", 1)[0] for r in results)
    declared = {c.name for c in sl.contracts}
    failures = []

    for name, count in EXPECTED.items():
        if found[name] != count:
            failures.append(f"{name}: expected {count} finding(s), got {found[name]}")
    for name in sorted(set(found) - set(EXPECTED)):
        failures.append(f"{name}: expected silent, got {found[name]} finding(s)")
    for name in sorted(EXPECTED_SILENT | set(EXPECTED)):
        if name not in declared:
            failures.append(f"{name}: not analysed; did a case stop compiling?")

    if failures:
        for failure in failures:
            print(f"  FAIL {failure}")
        return 1
    print(
        f"ok: {sum(EXPECTED.values())} finding(s) in {len(EXPECTED)} broken paymaster(s); "
        f"{len(EXPECTED_SILENT)} other paymasters analysed and silent"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
