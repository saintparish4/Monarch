# Monarch

**An ERC-4337 paymaster that lets a consumer app pay its users' gas.**

A new user of a consumer dApp has no ETH. Asking them to bridge some before they
can post, mint, or play is where most of them leave. Monarch is the contract an
app deploys so it can pick up that bill — for a specific user, for a specific
operation, within a budget it controls.

Built against [EntryPoint v0.8](https://github.com/eth-infinitism/account-abstraction/releases/tag/v0.8.0),
so it works with EIP-7702 delegated EOAs as well as deployed smart accounts.

## Status

Work in progress, rebuilt from an earlier draft. Nothing here is audited and
nothing is deployed to mainnet.

| | |
|---|---|
| Builds | ✅ `forge build`, zero warnings |
| Tests | ✅ 96 passing — 84 unit, 11 integration, 6 invariants |
| Coverage | ✅ 99.2% lines, 95.5% branches, 100% functions |
| Static analysis | ✅ `slither` clean, `solhint` clean at complexity 7 |
| Deployed (Base Sepolia) | 🚧 not yet |
| Demo | 🚧 not yet |
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
app funds. This is checked as a fuzzed invariant across every value-moving
entrypoint, and again after every real `handleOps` bundle in the tests.

## Design notes worth knowing

**It does not inherit upstream `BasePaymaster`.** That contract ships
`withdrawTo` as `public onlyOwner` and non-virtual, withdrawing against the raw
EntryPoint balance — the same pot backing every deposit and budget. Because it
is not `virtual` it cannot be overridden, so inheriting it would mean shipping an
owner function that drains user funds with no way to close it. Monarch implements
the canonical `IPaymaster` directly and restates the ~50 lines of EntryPoint
forwarding, with a solvency check on `withdrawTo`.

**Validation never reads the clock.** ERC-7562 bans `TIMESTAMP` during the
validation phase. The app signs a `(validUntil, validAfter)` pair off-chain, the
paymaster returns it packed into `validationData`, and the EntryPoint does the
comparison. The internal validation path is `view`: it decides, it never records.

**Staking is not optional.** Sponsored mode reads storage keyed by an address
from calldata rather than by `userOp.sender`, which is not sender-associated
storage. Bundlers reject operations from an unstaked paymaster that does this.

## Gas

Measured with `forge snapshot`, EntryPoint v0.8, optimizer runs 200, from the
end-to-end `handleOps` traces. These are what Monarch adds to an operation:

| Path | `validatePaymasterUserOp` | `postOp` |
|---|---|---|
| Sponsored | 11,997 | 11,524 |
| Deposit | 3,983 | 11,022 |

Runtime size 7,896 bytes. Full per-test figures are in
[`.gas-snapshot`](.gas-snapshot).

## Build

```bash
forge install
forge build
forge test
npm install && npm run lint
```

Tests run against real EntryPoint v0.8 bytecode deployed into the test VM, not a
mock. A mock would agree with whatever the author believed about the interface,
and misreading that interface is the bug class this rewrite exists to remove.

## Layout

```
contracts/              MonarchPaymaster, plus Constants and Validation
test/unit/              branch coverage, fuzzed properties, access, regressions
test/integration/       handleOps against the real EntryPoint
test/invariant/         solvency and value conservation under stateful fuzzing
```

## License

MIT — see [LICENSE](LICENSE).
