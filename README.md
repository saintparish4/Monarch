# Monarch

**An ERC-4337 paymaster that lets a consumer app pay its users' gas.**

A new user of a consumer dApp has no ETH. Asking them to bridge some before they
can post, mint, or play is where most of them leave. Monarch is the contract an
app deploys so it can pick up that bill — for a specific user, for a specific
operation, within a budget it controls.

Built against [EntryPoint v0.8](https://github.com/eth-infinitism/account-abstraction/releases/tag/v0.8.0),
so it works with EIP-7702 delegated EOAs as well as deployed smart accounts.

## Status

The contract is complete and every claim below names the gate that enforces it.
It is not audited, and nothing is deployed to mainnet — nor should it be.

| | |
|---|---|
| Builds | ✅ `forge build`, zero warnings, `deny = "warnings"` |
| Tests | ✅ 96 passing — 84 unit, 11 integration, 6 invariants, against real EntryPoint v0.8 bytecode |
| Coverage | ✅ 99.2% lines, 95.5% branches, 100% functions |
| Static analysis | ✅ `slither` clean; `solhint` clean at cyclomatic complexity 7 |
| ERC-7562 compliance | ✅ enforced by [a Slither detector written for it](#tooling), 0 findings here, 3 on this repo's own pre-rewrite code |
| Gas | ✅ published below and in [`.gas-snapshot`](.gas-snapshot), which CI diffs rather than regenerates |
| Deploy | ✅ [one script](script/Deploy.s.sol) — deploy, stake, deposit, register, fund, then re-check solvency on chain |
| Demo | ✅ [`demo/`](demo) — a zero-ETH wallet writes to a contract, end to end |
| Deployed (Base Sepolia) | 🚧 one command away; see [Deploy](#deploy) |
| Audit | ❌ none, and none planned |

## How it works

Two ways an operation gets paid for:

**Sponsored** — an app registers, funds a budget, and nominates a signer. To
sponsor a user it signs a short authorisation off-chain; the paymaster recovers
the signer, checks the app's budget covers the cost, and charges the app in
`postOp`. This is the path for a user who has never held a token.

**Deposit** — a user tops up a balance on the paymaster once and spends it
across later operations, without holding the chain's gas token.

The property the whole test suite is built around:

```
entryPoint.balanceOf(paymaster)  >=  totalUserDeposits + totalAppBudgets
```

The owner can withdraw only the excess above that sum. Never user funds, never
app funds. It is checked as a stateful invariant over every value-moving
entrypoint, and again after every `handleOps` bundle the tests actually run.

## Design notes worth knowing

**It does not inherit upstream `BasePaymaster`.** That contract ships
`withdrawTo` as `public onlyOwner` and non-virtual, withdrawing against the raw
EntryPoint balance — the same pot backing every deposit and budget. Because it is
not `virtual` the solvency check cannot be added by override, so inheriting it
would mean shipping an owner function that drains user funds with no way to close
it. Monarch implements the canonical `IPaymaster` directly and restates the ~50
lines of EntryPoint forwarding, with the check on `withdrawTo`.

**Validation never reads the clock.** ERC-7562 bans `TIMESTAMP` during the
validation phase. The app signs a `(validUntil, validAfter)` pair off-chain, the
paymaster returns it packed into `validationData`, and the EntryPoint does the
comparison. The internal validation path is `view`: it decides, it never records.

**Staking is not optional.** Sponsored mode reads storage keyed by an address
from calldata rather than by `userOp.sender`, which is not sender-associated
storage. Bundlers reject operations from an unstaked paymaster that does this.

**A bad signature is a return value, not a revert.** Reverting during validation
makes the whole bundle unmineable and gets the paymaster throttled. Malformed
*structure* still reverts — a bundler should have dropped that operation outright.

**`POSTOP_GAS_OVERHEAD` is measured, not guessed.** Do not read it off the
`postOp` frame in a trace; that frame costs 11,524 gas, and setting the constant
from it breaks solvency, because the EntryPoint finalises `actualGasCost` after
`postOp` returns. The honest measurement is the deficit a bundle leaves behind
with no owner buffer.

## Gas

EntryPoint v0.8, optimizer runs 200, taken from the end-to-end `handleOps`
traces. This is what Monarch adds to an operation:

| Path | `validatePaymasterUserOp` | `postOp` |
|---|---|---|
| Sponsored | 11,997 | 11,524 |
| Deposit | 3,983 | 11,022 |

Runtime size 7,896 bytes. Per-test figures in [`.gas-snapshot`](.gas-snapshot),
which CI diffs rather than regenerates — a job that rebuilds its own baseline
lets a regression stay green. Invariant runs are excluded from the snapshot
because their gas is not deterministic across seeds.

## Testing

Tests run against real EntryPoint v0.8 bytecode deployed into the test VM, never
a mock. A mock agrees with whatever I believed about the interface, and
misreading that interface is the entire bug class this rewrite exists to remove.

Three tiers, by how much of the real system is present: **unit** (one function,
`vm.prank` in place of the EntryPoint), **integration** (paymaster + EntryPoint +
`SimpleAccount` through `handleOps`), and **invariant** (bounded random action
sequences, 512 runs at depth 64 with `fail_on_revert = true`). Crossed with how
the arguments are chosen: examples, fuzzed properties, and stateful sequences.

Two things the suite is built to do that a coverage number does not show. Every
"cannot" in the trust model — owner cannot touch user deposits, an app cannot
spend another app's budget — has a test named after it, so completeness is
mechanical rather than a judgement. And each historical defect in the code this
replaced has a numbered regression test, because a rewrite that does not lock
them out can reintroduce them.

## Tooling

The worst defect in the code this replaced was reading `block.timestamp` during
validation. That is not a Monarch-specific mistake: ERC-7562 forbids it in every
ERC-4337 paymaster, account and factory, bundlers enforce it off-chain in a
tracer, and **nothing on-chain enforces it at all**. A violating contract
compiles, passes every test, passes a real `handleOps` call — and is then dropped
by every bundler, after it has been deployed, staked and funded.

So it became a Slither detector: [`tools/slither-erc7562`](tools/slither-erc7562).
It walks everything reachable from `validatePaymasterUserOp` or `validateUserOp`,
through internal calls and modifiers, and reports the forbidden opcodes.

| Corpus | Findings |
|---|---|
| `eth-infinitism/account-abstraction` v0.8, 48 contracts | 0 |
| This paymaster | 0 |
| Monarch's own pre-rewrite code, from git history | 3 |

Reproduce with `tools/slither-erc7562/run-corpus.sh`. It runs as part of this
project's own static-analysis gate.

## Build

```bash
forge install
forge build
forge test
```

The full gate set, each of which fails rather than prints:

```bash
forge fmt --check                       # formatting
forge build --sizes                     # zero warnings, forge lint included
FOUNDRY_PROFILE=ci forge test           # 96 tests, invariants at depth 64
npm run snapshot:check                  # gas has not regressed
npm install && npm run lint             # solhint, cyclomatic complexity 7
npm run analyze                         # slither, zero high and zero medium
```

Both `--check` gates have been deliberately broken once to confirm they can
fail. A check that cannot fail is not checking anything.

## Deploy

```bash
export PRIVATE_KEY=0x...            # deployer; also becomes owner
export APP_ADDRESS=0x...            # the app whose budget pays
export APP_SIGNER_ADDRESS=0x...     # the key that authorises sponsorships
export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org

forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
```

The script does four things that are each easy to skip and each fatal:

1. **deploy**
2. **`addStake`** — sponsored mode reads `apps[app]`, keyed by an address from
   calldata rather than by `userOp.sender`. That is not sender-associated
   storage, so under ERC-7562 an *unstaked* paymaster doing it is dropped by
   every bundler. An unstaked deployment passes its own tests and then works
   for nobody.
3. **`deposit`** — stake and deposit are different pots. The EntryPoint pays
   the bundler out of the deposit; funding the stake is not funding it.
4. **`registerApp` + `fundApp`** — the budget `postOp` actually charges.

It then reads the chain back and asserts the same solvency identity the
invariant suite enforces, so a deployment that looks fine on a block explorer
but is not solvent fails at deploy time rather than at the first operation.

## Try it

[`demo/`](demo) is a two-process demo: a page that generates a burner key with
no ETH, and a sponsor backend holding the app signer. The page writes to a
guestbook contract; the app's budget pays.

```bash
cd demo && cp .env.example .env   # addresses the deploy script printed
npm install && npm run dev
```

The demo's TypeScript encoder and [`Constants.sol`](contracts/libraries/Constants.sol)
are two copies of one byte layout, so the demo's tests **parse the offsets out
of the Solidity source** and assert the TypeScript agrees. Drift there decodes a
plausible, wrong app address rather than failing loudly — the same bug class the
rest of this repository exists to remove.

## Layout

```
contracts/              MonarchPaymaster, plus Constants and Validation
test/unit/              branch coverage, fuzz, access matrix, defect regressions
test/integration/       handleOps against the real EntryPoint
test/invariant/         solvency and value conservation under stateful fuzzing
tools/slither-erc7562/  the ERC-7562 detector, with its own tests and corpus
script/                 deploy, and the demo's guestbook target
demo/                   the zero-ETH demo: sponsor backend + page
```

## License

MIT — see [LICENSE](LICENSE).
