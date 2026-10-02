#!/usr/bin/env python
"""Run the ERC-7562 detector over the failure cases and check what it reports.

Each case says whether a static check can see its failure. This holds those
claims to account: exactly the contracts listed below are reported, for exactly
the opcodes listed, and every other paymaster in `cases/` is scanned and stays
silent. The "Static check sees it?" column in `cases/README.md` is read and
has to agree, case by case. If a case's answer changes, this fails and the
case's README is wrong.

Needs `slither-analyzer` with `slither-erc7562` installed in the same
environment, and `forge`. Run from the repository root with that environment's
interpreter:

    python cases/check-detector.py

Slither logs one ERROR while it runs, about generating IR for the EntryPoint's
`_EIP712Version`. That is Slither failing on a function in OpenZeppelin's
`EIP712`, which the cases compile because they deploy the real EntryPoint. It
does not touch any paymaster. That is checked rather than assumed: Slither
marks every contract it only partly parsed, and a paymaster with that mark
fails here, because its silence would mean nothing.
"""

import os
import re
import sys
from collections import Counter

from slither import Slither
from slither_erc7562.detectors import ValidationPhaseOpcodes, entry_points

# Contract -> opcode -> number of findings. Anything else reported is a failure,
# and so is the right number of findings for the wrong opcode.
EXPECTED = {"ClockCheckingPaymaster": {"TIMESTAMP": 1}}

# The paymasters that must be scanned and silent. Listed so that a case that
# stops compiling, is renamed, or loses its entry point fails here instead of
# passing by absence.
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

# The rendered description, as the detector builds it.
DESCRIPTION = re.compile(r"^(?P<contract>\w+)\.\w+ reaches (?P<opcode>\w+) via ")

# A row of the table in cases/README.md: the case's directory, and its answer.
README_ROW = re.compile(r"^\| \[\d+\]\((?P<case>[^)]+)\).*\|\s*(?P<seen>Yes|No)\s*\|\s*$")


def case_of(contract):
    """The case directory a contract's source is in, or None outside `cases/`."""
    parts = contract.source_mapping.filename.relative.replace(os.sep, "/").split("/")
    return parts[1] if len(parts) > 2 and parts[0] == "cases" else None


def readme_answers():
    """Case directory -> whether the README says a static check sees it."""
    with open(os.path.join("cases", "README.md"), encoding="utf-8") as handle:
        rows = (README_ROW.match(line) for line in handle)
        return {row["case"]: row["seen"] == "Yes" for row in rows if row}


def main():
    # The cases compile only under their own profile, and crytic-compile skips
    # a profile's test directory unless told to compile everything. Under this
    # profile the test directory is `cases/` itself.
    os.environ["FOUNDRY_PROFILE"] = "cases"
    sl = Slither(".", foundry_compile_all=True)
    sl.register_detector(ValidationPhaseOpcodes)
    results = [r for per_detector in sl.run_detectors() for r in per_detector]

    failures = []
    found = {}
    for result in results:
        match = DESCRIPTION.match(result["description"])
        if not match:
            failures.append(f"unparseable result: {result['description']!r}")
            continue
        found.setdefault(match["contract"], Counter())[match["opcode"]] += 1

    for name, expected in EXPECTED.items():
        actual = found.get(name, Counter())
        if actual != Counter(expected):
            failures.append(f"{name}: expected {dict(expected)}, got {dict(actual)}")
    for name in sorted(set(found) - set(EXPECTED)):
        failures.append(f"{name}: expected silent, got {dict(found[name])}")

    # Silence counts only for a contract the detector walked, and walked whole.
    # "Declared" is not enough: a paymaster whose entry point the detector does
    # not recognise is silent whatever is in it, and so is one Slither could not
    # build its IR for.
    scanned = {
        contract.name: contract
        for unit in sl.compilation_units
        for contract, _ in entry_points(unit)
    }
    for name in sorted(EXPECTED_SILENT | set(EXPECTED)):
        if name not in scanned:
            failures.append(f"{name}: not scanned; did a case stop compiling?")
        elif scanned[name].is_incorrectly_constructed:
            failures.append(f"{name}: Slither only partly parsed it, so its result means nothing")

    # Every paymaster in a case directory has to be listed above, so a new case
    # cannot pass by being silent and unlisted.
    cases = {name: case_of(contract) for name, contract in scanned.items()}
    for name in sorted(n for n, case in cases.items() if case and case != "shared"):
        if name not in EXPECTED_SILENT | set(EXPECTED):
            failures.append(f"{name}: scanned in cases/{cases[name]}, but has no expectation here")

    # The README's column, against what was actually reported.
    answers = readme_answers()
    seen = {cases[name] for name in found if cases.get(name)}
    if not answers:
        failures.append("cases/README.md: no case rows found in the table")
    for case in sorted(set(answers) | seen | {c for c in cases.values() if c and c != "shared"}):
        if case not in answers:
            failures.append(f"cases/{case}: has a paymaster, but no row in cases/README.md")
        elif answers[case] != (case in seen):
            failures.append(
                f"cases/{case}: README says a static check "
                f"{'sees' if answers[case] else 'does not see'} it, "
                f"and the detector {'reported' if case in seen else 'did not report'} it"
            )

    if failures:
        for failure in failures:
            print(f"  FAIL {failure}")
        return 1
    print(
        f"ok: {sum(sum(e.values()) for e in EXPECTED.values())} finding(s) in "
        f"{len(EXPECTED)} broken paymaster(s); {len(EXPECTED_SILENT)} other paymasters "
        f"scanned and silent; {len(answers)} README answers agree"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
