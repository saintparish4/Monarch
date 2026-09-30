#!/usr/bin/env bash
# Run the detector over a corpus of real paymasters and accounts.
#
# The point is that the numbers in the write-up are reproducible rather than
# asserted. Fetches what it needs into $WORK and prints one line per target.
# Needs `slither`, `forge` and network access.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/erc7562-corpus}
DETECT="--detect erc7562-validation-opcodes --json -"
SOLC=${SOLC_BINARY:-$(ls -d "$HOME"/.local/share/svm/0.8.28/solc-0.8.28 2>/dev/null || echo solc)}
# Slither's own interpreter, which is where the plugin and its tests live.
PY=$(head -1 "$(command -v slither)" | cut -c3-)

# Counts findings from Slither's JSON output, which is a stable interface; the
# "N result(s) found" line in its human output is not. Prints ERROR, with the
# tail of the output on stderr, when Slither did not produce a result at all,
# so a compile failure can never read as "0 findings".
count() {
  local out; out=$(cat)
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    report = json.loads(sys.stdin.read())
except ValueError:
    sys.exit(1)
if not report.get("success"):
    sys.exit(1)
print(len(report.get("results", {}).get("detectors", [])))
' || { echo "ERROR"; printf '%s\n' "$out" | tail -3 >&2; }
}
row() { printf '%-44s %s\n' "$1" "$2"; }

mkdir -p "$WORK"

# The reference implementation is a Hardhat project and compiling it needs npm.
# A three-line Foundry project that imports the same contracts reaches the same
# code with one tool, so that is what the corpus uses.
if [ ! -d "$WORK/upstream" ]; then
  mkdir -p "$WORK/upstream/src"
  ( cd "$WORK/upstream"
    printf '[profile.default]\nsrc = "src"\nlibs = ["lib"]\nsolc = "0.8.28"\nevm_version = "cancun"\n' > foundry.toml
    # `forge install` uses git submodules, so it needs a repository to install into.
    git init -q . && git commit -q --allow-empty -m init
    forge install foundry-rs/forge-std >/dev/null 2>&1
    forge install eth-infinitism/account-abstraction@v0.8.0 >/dev/null 2>&1
    forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 >/dev/null 2>&1
    printf 'forge-std/=lib/forge-std/src/\naccount-abstraction/=lib/account-abstraction/contracts/\n@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/\n' > remappings.txt
    cat > src/Corpus.sol <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";
import {SimpleAccountFactory} from "account-abstraction/accounts/SimpleAccountFactory.sol";
import {Simple7702Account} from "account-abstraction/accounts/Simple7702Account.sol";
import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";
import {TestPaymasterAcceptAll} from "account-abstraction/test/TestPaymasterAcceptAll.sol";
import {TestExpirePaymaster} from "account-abstraction/test/TestExpirePaymaster.sol";
import {TestPaymasterWithPostOp} from "account-abstraction/test/TestPaymasterWithPostOp.sol";
import {TestPaymasterRevertCustomError} from "account-abstraction/test/TestPaymasterRevertCustomError.sol";
SOL
  )
fi

# Any additional target, as a path to a Foundry project:
#
#   EXTRA_TARGET=/path/to/some-paymaster ./run-corpus.sh
#
# Third-party repositories are not hard-coded here on purpose. Running a
# detector against someone else's deployed contract and publishing the count is
# a disclosure, not a benchmark, and the maintainers should hear it from me
# before anyone reads it in a table.

cp "$HERE/tests/fixtures/Fixtures.sol" "$WORK/Fixtures.sol"

echo "target                                       findings"
echo "-----------------------------------------------------"
# The expected count comes from the test suite, so this label can't go stale
# when a fixture is added.
row "fixtures (self-check, expect $("$PY" "$HERE/tests/test_detectors.py" --expected-count))" \
    "$( cd "$WORK" && slither Fixtures.sol $DETECT --solc "$SOLC" \
        --compile-force-framework solc 2>/dev/null | count )"
row "eth-infinitism/account-abstraction v0.8" \
    "$( cd "$WORK/upstream" && slither . $DETECT --filter-paths 'src/Corpus' 2>/dev/null | count )"
# The paymaster this detector was written alongside. Found automatically when
# this runs from inside the Monarch repository; anywhere else, point MONARCH at
# a clone of it.
MONARCH=${MONARCH:-$HERE/../..}
if [ -f "$MONARCH/contracts/MonarchPaymaster.sol" ]; then
  row "monarch (current)" \
      "$( cd "$MONARCH" && slither . $DETECT 2>/dev/null | count )"
else
  row "monarch (current)" "skipped: set MONARCH=/path/to/monarch"
fi

if [ -n "${EXTRA_TARGET:-}" ]; then
  row "$(basename "$EXTRA_TARGET")" \
      "$( cd "$EXTRA_TARGET" && slither . $DETECT \
          --filter-paths 'lib|test|script' 2>/dev/null | count )"
fi
