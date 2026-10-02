#!/usr/bin/env bash
# Run the detector over a corpus of real paymasters and accounts.
#
# The point is that the numbers in the write-up are reproducible rather than
# asserted. Fetches what it needs into $WORK and prints one line per target:
# how many findings, and what was scanned to get them. Exits non-zero when a
# row is not what the README says it is. Needs `slither`, `forge`, `git` and
# network access.
#
#   REQUIRE_ALL_ROWS=true ./run-corpus.sh   # a skipped row fails too (CI)
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/erc7562-corpus}
DETECT="--detect erc7562-validation-opcodes --json -"
SOLC=${SOLC_BINARY:-$(ls -d "$HOME"/.local/share/svm/0.8.28/solc-0.8.28 2>/dev/null || echo solc)}
# Slither's own interpreter, which is where the plugin and its tests live.
PY=$(head -1 "$(command -v slither)" | cut -c3-)
FAILED=0

# What the corpus is made of. Every version is pinned, and checked against what
# is actually on disk before it is analysed: $WORK outlives a run, and a number
# from last month's checkout under this month's label is worse than no number.
AA_TAG=v0.8.0
OZ_TAG=v5.1.0
# Monarch as it was: the last commit before the rewrite, which is the one the
# teardown quotes from.
PRE_REWRITE=e78766495460129359bfc18210cd66155a625acd

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

# What the detector scanned, from the same list the detector walks. A count
# with nothing beside it cannot tell "clean" from "never looked": see
# corpus/scanned.py for the three ways a target reports zero without being
# clean, each of which comes back from here as ERROR.
scanned() { "$PY" "$HERE/corpus/scanned.py" "$@" 2>/dev/null; }

# One row: label, the count the README claims ("" for a target with no claim),
# the count found, and what was scanned. The run fails on a count that is not a
# number, on a count that is not the one claimed, and on a scan that could not
# vouch for it.
row() {
  local verdict=""
  if [ "$3" = ERROR ] || [ "${4#ERROR}" != "$4" ]; then
    verdict="  <- FAILED"; FAILED=1
  elif [ -n "$2" ] && [ "$3" != "$2" ]; then
    verdict="  <- expected $2"; FAILED=1
  fi
  printf '%-44s %-9s %s%s\n' "$1" "$3" "$4" "$verdict"
}
skipped() {
  printf '%-44s %s\n' "$1" "skipped: $2"
  if [ "${REQUIRE_ALL_ROWS:-}" = true ]; then FAILED=1; fi
}

mkdir -p "$WORK"

# The reference implementation is a Hardhat project and compiling it needs npm.
# A three-line Foundry project that imports the same contracts reaches the same
# code with one tool, so that is what the corpus uses.
at_tag() {
  local head; head=$(git -C "$WORK/upstream/lib/$1" rev-parse HEAD 2>/dev/null) || return 1
  [ "$head" = "$(git -C "$WORK/upstream/lib/$1" rev-parse "$2^{commit}" 2>/dev/null)" ]
}
upstream_is_pinned() {
  at_tag account-abstraction "$AA_TAG" && at_tag openzeppelin-contracts "$OZ_TAG"
}
if ! upstream_is_pinned; then
  rm -rf "$WORK/upstream"
  mkdir -p "$WORK/upstream/src"
  ( cd "$WORK/upstream"
    printf '[profile.default]\nsrc = "src"\nlibs = ["lib"]\nsolc = "0.8.28"\nevm_version = "cancun"\n' > foundry.toml
    # `forge install` uses git submodules, so it needs a repository to install into.
    # The identity is for this throwaway commit only; a CI runner has none.
    git init -q . && git -c user.name=corpus -c user.email=corpus@localhost commit -q --allow-empty -m init
    forge install "eth-infinitism/account-abstraction@$AA_TAG" >/dev/null 2>&1
    forge install "OpenZeppelin/openzeppelin-contracts@$OZ_TAG" >/dev/null 2>&1
    printf 'account-abstraction/=lib/account-abstraction/contracts/\n@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/\n' > remappings.txt
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

echo "target                                       findings  scanned"
echo "------------------------------------------------------------------------------"
# The expected count comes from the test suite, so neither this label nor the
# check behind it can go stale when a fixture is added.
FIXTURES=$("$PY" "$HERE/tests/test_detectors.py" --expected-count)
row "fixtures (self-check, expect $FIXTURES)" "$FIXTURES" \
    "$( cd "$WORK" && slither Fixtures.sol $DETECT --solc "$SOLC" \
        --compile-force-framework solc 2>/dev/null | count )" \
    "$( cd "$WORK" && scanned Fixtures.sol --solc "$SOLC" )"

# Zero here is a claim about the two accounts and four paymasters upstream
# ships, so each of them has to have been scanned for the zero to count.
if upstream_is_pinned; then
  row "eth-infinitism/account-abstraction $AA_TAG" 0 \
      "$( cd "$WORK/upstream" && slither . $DETECT --filter-paths 'src/Corpus' 2>/dev/null | count )" \
      "$( cd "$WORK/upstream" && scanned . --require SimpleAccount,Simple7702Account,TestPaymasterAcceptAll,TestExpirePaymaster,TestPaymasterWithPostOp,TestPaymasterRevertCustomError )"
else
  row "eth-infinitism/account-abstraction $AA_TAG" 0 ERROR "ERROR (could not install the pinned versions)"
fi

# The paymaster this detector was written alongside. Found automatically when
# this runs from inside the Monarch repository; anywhere else, point MONARCH at
# a clone of it.
MONARCH=${MONARCH:-$HERE/../..}
if [ -f "$MONARCH/contracts/MonarchPaymaster.sol" ]; then
  row "monarch (current)" 0 \
      "$( cd "$MONARCH" && slither . $DETECT 2>/dev/null | count )" \
      "$( cd "$MONARCH" && scanned . --require MonarchPaymaster )"
else
  skipped "monarch (current)" "set MONARCH=/path/to/monarch"
fi

# The same repository before the rewrite, out of its history. That code does
# not compile, so corpus/pre-rewrite.patch repairs the three errors first; it is a
# diff so that what was changed to get this number is on the page. None of it
# is in a validation path. A shallow clone does not have the commit.
PRE_LABEL="monarch (pre-rewrite, ${PRE_REWRITE:0:7})"
if git -C "$MONARCH" cat-file -e "$PRE_REWRITE^{commit}" 2>/dev/null; then
  rm -rf "$WORK/pre-rewrite" && mkdir -p "$WORK/pre-rewrite"
  # Line endings as committed, whatever this machine's git is set to do.
  if git -C "$MONARCH" -c core.autocrlf=false archive "$PRE_REWRITE" contracts \
       | tar -x -C "$WORK/pre-rewrite" \
     && ( cd "$WORK/pre-rewrite" && git apply "$HERE/corpus/pre-rewrite.patch" ); then
    row "$PRE_LABEL" 4 \
        "$( cd "$WORK/pre-rewrite" && slither contracts/libraries/BasePayments.sol $DETECT \
            --solc "$SOLC" --compile-force-framework solc 2>/dev/null | count )" \
        "$( cd "$WORK/pre-rewrite" && scanned contracts/libraries/BasePayments.sol \
            --solc "$SOLC" --require BasePaymaster )"
  else
    row "$PRE_LABEL" 4 ERROR "ERROR (the repair patch did not apply)"
  fi
else
  skipped "$PRE_LABEL" "needs Monarch's full history (git fetch --unshallow)"
fi

if [ -n "${EXTRA_TARGET:-}" ]; then
  row "$(basename "$EXTRA_TARGET")" "" \
      "$( cd "$EXTRA_TARGET" && slither . $DETECT \
          --filter-paths 'lib|test|script' 2>/dev/null | count )" \
      "$( cd "$EXTRA_TARGET" && scanned . --filter-paths 'lib|test|script' )"
fi

exit "$FAILED"
