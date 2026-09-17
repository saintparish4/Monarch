# Monarch

**An ERC-4337 paymaster that lets a consumer app pay its users' gas.**

**Live on Base Sepolia:** [`0xe81CEf1CbDce3a18b093005A2768aF85F78338d2`](https://base-sepolia.blockscout.com/address/0xe81CEf1CbDce3a18b093005A2768aF85F78338d2), source verified, staked, and sponsoring operations for wallets that hold zero ETH.

A new user of a consumer dApp has no ETH. Asking them to bridge some before they
can post, mint, or play is where most of them leave. Monarch is the contract an
app deploys so it can pick up that bill — for a specific user, for a specific
operation, within a budget it controls.

Built against [EntryPoint v0.8](https://github.com/eth-infinitism/account-abstraction/releases/tag/v0.8.0),
so it works with EIP-7702 delegated EOAs as well as deployed smart accounts.

## Status

Work in progress, rebuilt from an earlier draft. Nothing here is audited and
nothing is deployed to mainnet.

|                         |                                                                                                                                                                                           |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Builds                  | ✅ `forge build`, zero warnings                                                                                                                                                           |
| Tests                   | ✅ 96 passing — 84 unit, 11 integration, 6 invariants                                                                                                                                     |
| Coverage                | ✅ 99.2% lines, 95.5% branches, 100% functions                                                                                                                                            |
| Static analysis         | ✅ `slither` clean; `solhint` clean at cyclomatic complexity 7                                                                                                                            |
| Gas                     | ✅ published below and in [`.gas-snapshot`](.gas-snapshot)                                                                                                                                |
| Deployed (Base Sepolia) | ✅ [`0xe81CEf1C…38d2`](https://base-sepolia.blockscout.com/address/0xe81CEf1CbDce3a18b093005A2768aF85F78338d2), source verified on Sourcify and Blockscout; see [Deployment](#deployment) |
| Demo                    | ✅ a zero-ETH wallet sends sponsored operations through a public bundler; see [Demo](#demo)                                                                                               |
| Audit                   | ❌ none, and none planned                                                                                                                                                                 |

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
_structure_ still reverts — a bundler should have dropped that operation outright.

**`POSTOP_GAS_OVERHEAD` is measured, and the part that varies isn't a constant
at all.** Do not read it off the `postOp` frame in a trace; that frame costs
about 11,500 gas, and setting the constant from it breaks solvency, because the
EntryPoint finalises `actualGasCost` after `postOp` returns. The honest
measurement is the deficit a bundle leaves behind with no owner buffer.

That deficit has two parts. One is a fixed base cost, which the constant covers.
The other is a penalty of a tenth of whatever part of `paymasterPostOpGasLimit`
goes unused — unbounded, and chosen by the caller — so `postOp` reproduces the
EntryPoint's formula and bills it to the payer who asked for the limit. Pricing
it beats refusing it: bundlers estimate gas by simulating with limits far above
anything real, so a paymaster that reverts on a large limit cannot be estimated
and therefore cannot be used.

The one limit refused rather than priced is one too small for `postOp` to
finish. A starved `postOp` is swallowed by the EntryPoint, which settles without
calling it again, so the payer is never debited while the deposit is drained in
full — and there is no later moment at which to charge anyone.

**The contract this replaced is torn down in [`docs/teardown-basepaymaster.md`](docs/teardown-basepaymaster.md).**
It didn't compile, couldn't be called by any current EntryPoint, and read the
clock during validation. Each design rule above traces back to one of those
lines.

## Deployment

|                  | Base Sepolia (84532)                                                                                                                                                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| MonarchPaymaster | [`0xe81CEf1CbDce3a18b093005A2768aF85F78338d2`](https://base-sepolia.blockscout.com/address/0xe81CEf1CbDce3a18b093005A2768aF85F78338d2)                                                                                               |
| EntryPoint       | `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108` (v0.8)                                                                                                                                                                                  |
| Stake            | 0.01 ETH, one-day unstake delay                                                                                                                                                                                                      |
| Source           | exact match on [Sourcify](https://repo.sourcify.dev/84532/0xe81CEf1CbDce3a18b093005A2768aF85F78338d2); verified on [Blockscout](https://base-sepolia.blockscout.com/address/0xe81CEf1CbDce3a18b093005A2768aF85F78338d2?tab=contract) |

Every address and transaction hash is in
[`deployments/base-sepolia.json`](deployments/base-sepolia.json). Deploying,
staking and funding the owner buffer is one broadcast, so a deployment can't
stop at an unstaked contract that looks finished but sponsors nothing:

```bash
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast
PAYMASTER=0x… APP_SIGNER=0x… \
  forge script script/RegisterApp.s.sol --rpc-url base_sepolia --broadcast
```

The public bundler accepted a 0.01 ETH stake. ERC-7562 leaves the minimum to each
chain, so a mainnet deployment needs to check what its bundlers require.

## Demo

[`demo/`](demo) is one Next.js page. It generates an owner key in the browser, so
the wallet has never held ETH. It then derives a `SimpleAccount` and sends a call
through a public bundler. The app's backend route,
[`demo/app/api/sponsor/route.ts`](demo/app/api/sponsor/route.ts), decides whether
to sponsor and signs the authorisation. The paymaster charges the app's budget.

First live run, 2026-09-17:

| Operation                        | Transaction                                                                                                                    | Gas used | Charged to the app |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------- | ------------------ |
| First (also deploys the account) | [`0xc30a804a…17cd`](https://base-sepolia.blockscout.com/tx/0xc30a804ac6181b2b16c7ed502f7bb692fed744fe91d265fca1309af87a2017cd) | 274,445  | 0.0000017492 ETH   |
| Second                           | [`0x98a46358…1a72`](https://base-sepolia.blockscout.com/tx/0x98a463588fb8dce8b8c0c034e40c65f547febbba461c41fccdcba82d43ad1a72) | 132,635  | 0.0000008842 ETH   |

The owner key and the smart account both held 0 ETH before and after.

```bash
cd demo && npm install && npm run dev
```

The sponsor route signs with `APP_SIGNER_PRIVATE_KEY` from the repository's
`.env`, and only the registered signer's key works. To run it yourself, deploy
and register your own app with the scripts above. Then point
`deployments/base-sepolia.json` at your addresses. The endpoint is
unauthenticated, which is fine for a testnet budget and nothing else.

## Gas

EntryPoint v0.8, optimizer runs 200, taken from the end-to-end `handleOps`
traces. This is what Monarch adds to an operation:

| Path      | `validatePaymasterUserOp` | `postOp` |
| --------- | ------------------------- | -------- |
| Sponsored | 11,237                    | 11,693   |
| Deposit   | 4,248                     | 11,191   |

`postOp` costs a little more than it used to because it now prices the
EntryPoint's unused-gas penalty rather than folding a guess at it into a
constant. That trade is worth making: on Base Sepolia a repeat sponsored
operation used to be billed 12,311 gas more than the EntryPoint actually took,
and is now billed 2,136 more.

Runtime size 7,894 bytes. Per-test figures in [`.gas-snapshot`](.gas-snapshot),
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

| Corpus                                                  | Findings |
| ------------------------------------------------------- | -------- |
| `eth-infinitism/account-abstraction` v0.8, 48 contracts | 0        |
| This paymaster                                          | 0        |
| Monarch's own pre-rewrite code, from git history        | 3        |

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

## Layout

```
contracts/              MonarchPaymaster, plus Constants and Validation
test/unit/              branch coverage, fuzz, access matrix, defect regressions
test/integration/       handleOps against the real EntryPoint
test/invariant/         solvency and value conservation under stateful fuzzing
tools/slither-erc7562/  the ERC-7562 detector, with its own tests and corpus
script/                 deploy + stake, and register + fund an app
deployments/            deployed addresses and transaction hashes, per network
demo/                   a zero-ETH wallet sending a sponsored operation
docs/                   the teardown of the contract this replaced
```

## License

MIT — see [LICENSE](LICENSE).
