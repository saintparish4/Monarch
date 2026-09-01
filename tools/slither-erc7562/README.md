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
entry point, it walks everything reachable from that function — through internal
calls **and through modifiers** — and reports any of:

| Solidity | Opcode |
|---|---|
| `block.timestamp` | TIMESTAMP |
| `block.number` | NUMBER |
| `block.difficulty` / `block.prevrandao` | DIFFICULTY / PREVRANDAO |
| `block.coinbase` | COINBASE |
| `block.gaslimit` | GASLIMIT |
| `block.basefee` / `block.blobbasefee` | BASEFEE / BLOBBASEFEE |
| `blockhash(...)` | BLOCKHASH |
| `blobhash(...)` | BLOBHASH |
| `tx.origin` | ORIGIN |
| `tx.gasprice` | GASPRICE |
| `address(x).balance` | BALANCE / SELFBALANCE |
| `selfdestruct(...)` | SELFDESTRUCT |

`block.chainid` is permitted and is not reported. It is also load-bearing: a
sponsorship signature that does not commit to the chain id replays across chains.

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
- **Storage access rules.** ERC-7562 also restricts *which* slots validation may
  read. That is the other half of the standard and the natural next detector.
- **Path sensitivity.** A banned opcode behind a flag that can disable it is
  still reported. See the note on `allowAllBundlers` below.

## Results on real code

Reproduce with `./run-corpus.sh`.

| Target | Findings |
|---|---|
| Fixture suite (self-check) | 9 |
| `eth-infinitism/account-abstraction` v0.8 — 48 contracts | 0 |
| `pimlicolabs/singleton-paymaster` | 6 |
| This project's current paymaster | 0 |

The Pimlico result deserves care, because it is a deployed, audited, widely used
contract and this is **not** a claim that it has a bug. `SingletonPaymaster`
V6, V7 and V8 read `tx.origin` during validation to enforce a bundler allowlist.
That is a deliberate design with an `allowAllBundlers` flag in `paymasterAndData`
that short-circuits the read per operation. When the flag is set, the operation
is ERC-7562-clean; when it is not, the paymaster has chosen to restrict itself to
bundlers that will tolerate the read.

That is exactly what a detector should surface and a human should triage — and it
is also a fair statement of this detector's main limitation, which is that it
reports reachability and cannot see that the read is optional. Suppress an
accepted deviation the ordinary way:

```solidity
// slither-disable-next-line erc7562-validation-opcodes
if (!allowAllBundlers && !isBundlerAllowed[tx.origin]) revert BundlerNotAllowed(tx.origin);
```

## Tests

```bash
"$(head -1 "$(which slither)" | cut -c3-)" tests/test_detectors.py
```

Nine fixtures and two attribution checks. The negative cases — a clean paymaster
using `block.chainid`, and a contract reading the clock *outside* validation —
matter as much as the positive ones. A detector that fires on correct code gets
turned off, and a detector that is turned off finds nothing.

## License

MIT.
