#!/usr/bin/env python
"""Say what the detector scanned in a target. Used by run-corpus.sh.

A count of findings says nothing on its own. Zero is what a clean target
reports, and it is also what a target reports when it holds no validation entry
point, when the contract that matters was filtered away, or when Slither gave
up on part of that contract and carried on. This prints the other half of the
row, so that a zero in the corpus is a zero about something:

    6 entry points in 48 contracts

It exits non-zero, with the reason on its one line of output, when:

  - nothing was scanned;
  - a contract named in `--require` was not scanned;
  - Slither only partly parsed a contract that was scanned. Slither logs an
    error for that and keeps going, and the function it skipped has nothing in
    it for a detector to find.

Run it with the interpreter Slither is installed under, from the directory
`slither` would be run from:

    scanned.py . --require MonarchPaymaster
    scanned.py Fixtures.sol --solc /path/to/solc-0.8.28

`filter_paths` is read from `slither.config.json` in that directory when there
is one, which is the file the `slither` command reads it from, so the two agree
about what is in scope. `--filter-paths` overrides it.
"""

import argparse
import json
import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from slither import Slither  # noqa: E402

from slither_erc7562.detectors import entry_points  # noqa: E402


def configured_filter():
    try:
        with open("slither.config.json", encoding="utf-8") as handle:
            return json.load(handle).get("filter_paths")
    except (OSError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("target")
    parser.add_argument("--solc", help="compile with this solc and no build system")
    parser.add_argument(
        "--require", default="", help="comma-separated contracts that must be scanned"
    )
    parser.add_argument("--filter-paths", help="regex of source paths that are out of scope")
    args = parser.parse_args()

    # Slither and the compilers it drives are noisy, and none of it is this
    # script's answer. What matters from that noise is read off the contracts
    # below instead of out of a log.
    logging.disable(logging.CRITICAL)

    kwargs = {"solc": args.solc, "compile_force_framework": "solc"} if args.solc else {}
    try:
        sl = Slither(args.target, **kwargs)
    except Exception as error:  # noqa: BLE001 - any failure to load is the answer
        print(f"ERROR (did not compile: {type(error).__name__})")
        return 1

    out_of_scope = args.filter_paths or configured_filter()
    scanned = []
    for unit in sl.compilation_units:
        for contract, entry in entry_points(unit):
            path = contract.source_mapping.filename.relative
            if out_of_scope and re.search(out_of_scope, path):
                continue
            scanned.append((contract, entry))

    names = {contract.name for contract, _ in scanned}
    missing = sorted(set(filter(None, args.require.split(","))) - names)
    partial = sorted({c.name for c, _ in scanned if c.is_incorrectly_constructed})

    if not scanned:
        print("ERROR (no validation entry point was scanned)")
        return 1
    if missing:
        print(f"ERROR (never scanned: {', '.join(missing)})")
        return 1
    if partial:
        print(f"ERROR (Slither only partly parsed: {', '.join(partial)})")
        return 1

    plural = "" if len(scanned) == 1 else "s"
    print(f"{len(scanned)} entry point{plural} in {len(sl.contracts)} contracts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
