# slither-erc7562

A Slither detector for the opcodes ERC-7562 forbids while a bundler validates
an ERC-4337 operation.

> **An early check, not a compliance verdict.** A clean run means this detector
> found none of the opcodes it looks for on any path it can follow from a
> validation entry point. It does not mean a bundler will accept your
> operations. ERC-7562 also has storage-access rules, staking and reputation
> rules, rules about which addresses validation may call, and rules each bundler
> applies locally. A static detector can see none of them. Run your operations
> through a real bundler before you deploy anything that holds funds.

## Why this exists

Bundlers enforce ERC-7562 off-chain, in a tracer, at the moment an operation is
submitted. **Nothing on-chain enforces it.** A paymaster that reads
`block.timestamp` during validation compiles, passes every unit test, passes a
real `EntryPoint.handleOps` call in a test VM — and is then dropped by every
bundler in production.

That is an unusually bad failure shape: the contract is deployed, staked and
funded before anyone finds out. This detector moves the discovery to build time.

## Install

Until the first PyPI release, install it from this repository:

```bash
pip install "slither-erc7562 @ git+https://github.com/saintparish4/monarch#subdirectory=tools/slither-erc7562"
pip install -e .                   # from a checkout
```

Install it into the same environment as Slither (`slither-analyzer` 0.11). If
Slither was installed with `uv tool`:

```bash
uv pip install --python "$(head -1 "$(which slither)" | cut -c3-)" -e .
```

Confirm it registered:

```bash
slither --list-detectors | grep erc7562
```

## Use

```bash
slither . --detect erc7562-validation-opcodes
```

Or leave it on with the rest of your detectors. It runs at Medium impact and
High confidence, so it trips a `fail_on: medium` gate or `--fail-medium`.

A finding names the rule and says what the bundler does about it:

```text
ClockCheckingPaymaster.validatePaymasterUserOp reaches TIMESTAMP via `block.timestamp`.
ERC-7562 OP-011 forbids it during validation. Its value can change between the
bundler's simulation and the block that includes the operation, so a bundler drops
any operation whose validation uses it:
	- block.timestamp > validUntil (Clock.sol#27)
```

### In CI

A GitHub Actions job for a Foundry project. Slither compiles through `forge`,
so the job needs Foundry and your submodules:

```yaml
erc7562:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        submodules: recursive
    - uses: foundry-rs/foundry-toolchain@v1
    - uses: actions/setup-python@v5
      with:
        python-version: "3.12"
    - run: >-
        pip install slither-analyzer==0.11.6
        "slither-erc7562 @ git+https://github.com/saintparish4/monarch#subdirectory=tools/slither-erc7562"
    - run: slither . --detect erc7562-validation-opcodes --fail-medium
```

## What it checks

For every concrete contract with a `validatePaymasterUserOp` or `validateUserOp`
entry point, it walks everything reachable from that function and reports any
opcode below. The walk follows every route the bundler's tracer would see
executed under the validation frame:

- internal calls,
- **modifiers**, the easiest place for a clock read to hide from a reader,
- library calls, internal or public,
- `this.f()` calls, resolved to the override the deployed contract runs.

It reports these, whether written in Solidity or in inline assembly. Rule
identifiers are ERC-7562's own, from its
[opcode rules](https://eips.ethereum.org/EIPS/eip-7562#opcode-rules).

| Rule   | Opcode                  | Solidity                                | Inline assembly (Yul)            |
| ------ | ----------------------- | --------------------------------------- | -------------------------------- |
| OP-011 | TIMESTAMP               | `block.timestamp`                       | `timestamp()`                    |
| OP-011 | NUMBER                  | `block.number`                          | `number()`                       |
| OP-011 | DIFFICULTY / PREVRANDAO | `block.difficulty` / `block.prevrandao` | `prevrandao()`                   |
| OP-011 | COINBASE                | `block.coinbase`                        | `coinbase()`                     |
| OP-011 | GASLIMIT                | `block.gaslimit`                        | `gaslimit()`                     |
| OP-011 | BASEFEE / BLOBBASEFEE   | `block.basefee` / `block.blobbasefee`   | `basefee()` / `blobbasefee()`    |
| OP-011 | BLOCKHASH               | `blockhash(...)`                        | `blockhash(...)`                 |
| OP-011 | BLOBHASH                | `blobhash(...)`                         | `blobhash(...)`                  |
| OP-011 | ORIGIN                  | `tx.origin`                             | `origin()`                       |
| OP-011 | GASPRICE                | `tx.gasprice`                           | `gasprice()`                     |
| OP-011 | SELFDESTRUCT            | `selfdestruct(...)`                     | `selfdestruct(...)`              |
| OP-011 | INVALID                 | none (`assert` is a Panic revert)       | `invalid()`                      |
| OP-080 | BALANCE / SELFBALANCE   | `address(x).balance`                    | `balance(...)` / `selfbalance()` |

`address(this).balance` and `selfbalance()` compile to SELFBALANCE but are
reported as BALANCE, because Slither presents both as a `balance` read. OP-080
treats the two the same way, so the finding is the same either way.

`block.chainid` and `chainid()` are permitted and are not reported. They are
also load-bearing: a sponsorship signature that does not commit to the chain id
replays across chains. `msg.sender`, `msg.value`, `msg.data` and `msg.sig` are
permitted too, and the test suite reads every one of them in a fixture that must
stay clean.

Entry points are matched **by function name, not by interface**. The contract
that motivated this plugin declared its own `IPaymaster` with the wrong argument
list, so an interface-based match would have skipped it.

## What it does not check

Listed rather than silently skipped, because a checker that quietly ignores a
rule is worse than one that says which rules it covers.

**Opcode rules it leaves out:**

- **GAS (OP-012).** Permitted immediately before a `*CALL`. Telling that apart
  from misuse needs dataflow this does not do, and flagging every `gasleft()`
  would be noise.
- **CREATE and CREATE2 (OP-011, OP-031, OP-032).** Permitted for deploying the
  sender. Same problem.
- **Where validation calls.** Addresses without code (OP-041), the EntryPoint
  beyond the permitted calls (OP-051 to OP-055), `CALL` with value (OP-061),
  and precompiles (OP-062). These are facts about addresses and deployments,
  not source.
- **Out-of-gas reverts (OP-020)** and **unassigned opcodes (OP-013).**

**The staked exception in OP-080.** BALANCE and SELFBALANCE are allowed in a
staked entity. Whether a contract is staked is a deployment fact, so the
detector reports the read either way, and the finding says so. If yours is
staked, suppress the line and write down why.

**Everything outside the opcode rules**, which is most of ERC-7562:

- the storage rules (STO-010 to STO-041), including which slots an unstaked
  entity may touch;
- the code rule (COD-010);
- staking and reputation (GREP, SREP, EREP and UREP), including the rules that
  ban an entity that passes validation alone and then fails inside a bundle;
- the local rules each bundler applies (STO-040, STO-041).

**Edges the walk does not cross**, each of which can hide a banned opcode:

- **Calls to other contracts.** Which code sits behind an address is a
  deployment fact, not a source fact, so the walk stops at the call.
- **Self-calls through a cast.** `this.f()` is followed;
  `IFoo(address(this)).f()` reaches the same code but is not recognised.
- **Function pointers.** A call through a function-typed variable is not
  resolved.
- **`difficulty()` in pre-Paris assembly.** solc rejects it from Paris on, and
  every fixture compiles for Cancun, so there is no test that could prove the
  mapping. Opcode 0x44 is still caught through `prevrandao()` and
  `block.difficulty`.

**Path sensitivity.** A banned opcode behind a flag that can switch it off is
still reported. This is the detector's known false-positive class; see
`examples/BundlerAllowlist.sol` and the section on third-party contracts below.

## Examples

Each file in [`examples/`](examples) pairs a contract that is reported with one
that is not, and says why in its comments. The test suite checks every one of
them, so this table cannot drift from what the detector does.

| File                    | Reported                                                         | Silent                                           |
| ----------------------- | ---------------------------------------------------------------- | ------------------------------------------------ |
| `Clock.sol`             | `ClockCheckingPaymaster`: TIMESTAMP (OP-011)                     | `WindowReturningPaymaster`: returns the window   |
| `HidingPlaces.sol`      | TIMESTAMP in a modifier, in a library, and in inline assembly    | (the fix is the one in `Clock.sol`)              |
| `Balance.sol`           | `BalanceCheckingPaymaster`: BALANCE (OP-080)                     | `DepositLedgerPaymaster`: reads a deposit ledger |
| `BundlerAllowlist.sol`  | `OriginAllowlistPaymaster`: ORIGIN behind an off switch (OP-011) | `TriagedAllowlistPaymaster`: suppressed, triaged |
| `OutsideValidation.sol` | nothing                                                          | `ClockInPostOpPaymaster`: the clock in `postOp`  |

Most ways a paymaster fails a bundler are not opcodes at all. The
[failure cases](https://github.com/saintparish4/monarch/tree/master/cases) that
ship with Monarch are six of them, each with a reproduction against the real
EntryPoint v0.8, and only the first is something this detector can see.

## Results on real code

Reproduce with `./run-corpus.sh`.

| Target                                                   | Findings |
| -------------------------------------------------------- | -------- |
| Fixture suite (self-check)                               | 38       |
| `eth-infinitism/account-abstraction` v0.8 — 48 contracts | 0        |
| The paymaster this was written alongside                 | 0        |
| That paymaster's own pre-rewrite code, from git history  | 4        |

The last row is the one that made me write this. Four `block.timestamp` reads
reachable from `validatePaymasterUserOp`, in code I had already deleted. One of
them I had found earlier by reading the file carefully, which took an evening;
the detector finds all four in under a second. The fourth sits two calls deep
inside an internal library function, and the first version of this detector
missed it, because Slither files that call under library calls rather than
internal ones. The walk follows both now.

Zero on the reference implementation matters just as much. A detector that fires
on audited, correct code gets switched off, and a detector that is switched off
finds nothing.

### On third-party contracts

I have run this against deployed third-party paymasters, and one of them
produces findings. I am not naming it here yet, and the corpus runner does not
fetch it, because running a detector against someone else's deployed contract and
publishing the count is a disclosure rather than a benchmark — the maintainers
should hear it from me before anyone reads it in a table.

What I can say generally, because it is the tool's main limitation rather than
anyone's bug: the pattern I found was a banned opcode read behind a flag that
disables it, so the contract is compliant on one path and not on the other. This
detector reports **reachability**. It cannot see that a read is optional, and it
will report a case like that as a finding. That is a real false-positive class,
and until it is path-sensitive the answer is a human triage and the ordinary
suppression:

```solidity
// slither-disable-next-line erc7562-validation-opcodes
if (!allowAnyBundler && !isBundlerAllowed[tx.origin]) revert NotAllowed();
```

Point the runner at your own project with `EXTRA_TARGET=/path/to/project`.
Outside the Monarch repository, set `MONARCH` to a clone of it for the
Monarch row, or it is skipped.

## Disclosure

If this detector finds something in a contract you did not write, tell its
maintainers privately before you tell anyone else, and give them time to
answer. That is the policy I hold myself to:

- Findings in someone else's code go to its maintainers first, privately.
- I do not publish counts or names for third-party contracts, in this README,
  in the corpus, or anywhere else, until the maintainers have had that chance.
- The corpus runs only against code whose authors publish it as a reference,
  and against my own.

A finding here is a lead, not a verdict, for all the reasons in
[What it does not check](#what-it-does-not-check). Confirm it by hand before you
report it.

## Tests

```bash
"$(head -1 "$(which slither)" | cut -c3-)" tests/test_detectors.py
```

It needs solc 0.8.28, found through `$SOLC_BINARY`, then Foundry's copy, then
`solc` on your `PATH` (`solc-select install 0.8.28 && solc-select use 0.8.28`
provides one without Foundry).

The suite runs the detector end to end, registered exactly as the plugin entry
point registers it, and asserts on the results it renders:

- the exact findings for each of 19 reporting fixtures, counted rather than
  collected into a set, so a double report fails;
- where each transitive finding is attributed: helper, modifier, library,
  self-call, override;
- that each finding names the rule ERC-7562 files its opcode under, checked
  against a copy of the spec's lists rather than against the detector's own;
- six contracts that must stay silent: a clean paymaster, a clock read outside
  validation, an interface, a library, an abstract base, and a self-call whose
  target reads nothing banned;
- that every key in the opcode maps fires on some fixture, so the table above
  cannot claim coverage the detector does not have;
- that every permitted spelling is read in a fixture and reported nowhere;
- every file in `examples/`, reported and silent, including the suppression.

The negative cases matter as much as the positive ones. A detector that fires
on correct code gets turned off, and a detector that is turned off finds
nothing.

## License

MIT.
