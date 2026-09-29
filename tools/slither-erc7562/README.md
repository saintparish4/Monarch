# slither-erc7562

A Slither detector for opcodes that ERC-7562 forbids during the validation phase
of an ERC-4337 bundle.

## Why this exists

Bundlers enforce ERC-7562 off-chain, in a tracer, at the moment an operation is
submitted. **Nothing on-chain enforces it.** A paymaster that reads
`block.timestamp` during validation compiles, passes every unit test, passes a
real `EntryPoint.handleOps` call in a test VM — and is then dropped by every
bundler in production.

That is an unusually bad failure shape: the contract is deployed, staked and
funded before anyone finds out. This detector moves the discovery to build time.

## Install

```bash
pip install slither-erc7562        # once published
pip install -e .                   # from a checkout
```

Install it into the same environment as Slither. If Slither was installed with
`uv tool`:

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

Or leave it on with the rest of your detectors — it runs at Medium impact and
High confidence, so it will trip a `fail_on: medium` gate.

## What it checks

For every concrete contract with a `validatePaymasterUserOp` or `validateUserOp`
entry point, it walks everything reachable from that function and reports any
banned opcode it finds. The walk follows every route the bundler's tracer
would see executed under the validation frame:

- internal calls,
- **modifiers**, the easiest place for a clock read to hide from a reader,
- library calls, internal or public,
- `this.f()` calls, resolved to the override the deployed contract runs.

It reports these, whether written in Solidity or in inline assembly:

| Solidity                                | Inline assembly (Yul)            | Opcode                  |
| --------------------------------------- | -------------------------------- | ----------------------- |
| `block.timestamp`                       | `timestamp()`                    | TIMESTAMP               |
| `block.number`                          | `number()`                       | NUMBER                  |
| `block.difficulty` / `block.prevrandao` | `prevrandao()`                   | DIFFICULTY / PREVRANDAO |
| `block.coinbase`                        | `coinbase()`                     | COINBASE                |
| `block.gaslimit`                        | `gaslimit()`                     | GASLIMIT                |
| `block.basefee` / `block.blobbasefee`   | `basefee()` / `blobbasefee()`    | BASEFEE / BLOBBASEFEE   |
| `blockhash(...)`                        | `blockhash(...)`                 | BLOCKHASH               |
| `blobhash(...)`                         | `blobhash(...)`                  | BLOBHASH                |
| `tx.origin`                             | `origin()`                       | ORIGIN                  |
| `tx.gasprice`                           | `gasprice()`                     | GASPRICE                |
| `address(x).balance`                    | `balance(...)` / `selfbalance()` | BALANCE                 |
| `selfdestruct(...)`                     | `selfdestruct(...)`              | SELFDESTRUCT            |

`address(this).balance` and `selfbalance()` compile to SELFBALANCE but are
reported as BALANCE, because Slither presents both as a `balance` read. Both
opcodes are banned, so the finding stands either way.

`block.chainid` and `chainid()` are permitted and are not reported. They are
also load-bearing: a sponsorship signature that does not commit to the chain id
replays across chains. `msg.sender`, `msg.value`, `msg.data` and `msg.sig` are
permitted too, and the test suite reads every one of them in a fixture that must
stay clean.

Entry points are matched **by function name, not by interface**. The contract
that motivated this plugin declared its own `IPaymaster` with the wrong argument
list, so an interface-based match would have skipped it.

## What it does not check yet

Listed rather than silently skipped, because a checker that quietly ignores a
rule is worse than one that says which rules it covers.

- **GAS.** Permitted immediately before an external call. Telling that apart from
  misuse needs dataflow this does not do, and flagging every `gasleft()` would be
  noise.
- **CREATE.** Permitted for a factory deploying the sender. Same problem.
- **External calls to addresses that are not sender-associated.** The rule is
  about the address, not the call. Needs the storage-association analysis.
- **Storage access rules.** ERC-7562 also restricts _which_ slots validation may
  read. That is the other half of the standard and the natural next detector.
- **Path sensitivity.** A banned opcode behind a flag that can disable it is
  still reported. See the note on `allowAllBundlers` below.

The walk also has edges it does not cross, each of which can hide a banned
opcode:

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

## Results on real code

Reproduce with `./run-corpus.sh`.

| Target                                                   | Findings |
| -------------------------------------------------------- | -------- |
| Fixture suite (self-check)                               | 37       |
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

## Tests

```bash
"$(head -1 "$(which slither)" | cut -c3-)" tests/test_detectors.py
```

The suite runs the detector end to end, registered exactly as the plugin entry
point registers it, and asserts on the results it renders:

- the exact findings for each of 18 reporting fixtures, counted rather than
  collected into a set, so a double report fails;
- where each transitive finding is attributed: helper, modifier, library,
  self-call, override;
- six contracts that must stay silent: a clean paymaster, a clock read outside
  validation, an interface, a library, an abstract base, and a self-call whose
  target reads nothing banned;
- that every key in the opcode maps fires on some fixture, so the table above
  cannot claim coverage the detector does not have;
- that every permitted spelling is read in a fixture and reported nowhere.

The negative cases matter as much as the positive ones. A detector that fires
on correct code gets turned off, and a detector that is turned off finds
nothing.

## License

MIT.
