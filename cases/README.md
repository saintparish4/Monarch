# Paymaster failure cases

Six ways a paymaster fails that its own tests do not show. Each one is a broken
contract, its fix, and a test against the real EntryPoint v0.8 that tells the
two apart.

They answer the question I kept asking while building Monarch: **my paymaster
works in my tests, so why does the bundler reject it, and does its accounting
survive failure?**

> These contracts are written to be wrong. None of them is audited, and none of
> them is for deployment, on a testnet or anywhere else.

| #                                   | Case                                                     | What goes wrong                                              | Static check sees it? |
| ----------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------ | --------------------- |
| [01](01-validation-reads-the-clock) | Validation reads the clock                               | Every bundler drops the operation                            | Yes                   |
| [02](02-postop-gas-ceiling)         | A ceiling on the postOp gas limit                        | The paymaster cannot be gas-estimated, so it is never used   | No                    |
| [03](03-starved-postop)             | Too little gas for `postOp`                              | The paymaster pays, nobody is charged, and it repeats        | No                    |
| [04](04-budget-contention)          | Several sponsorships against one budget                  | The overdraw lands on other apps, or the paymaster is banned | No                    |
| [05](05-unbound-sponsorship)        | A sponsorship signature that leaves fields out           | The sender spends the app's money on something else          | No                    |
| [06](06-withdraw-takes-deposits)    | The owner withdraws against the whole EntryPoint deposit | The owner can take users' prepaid balances                   | No                    |

## Run them

You need Foundry and this repository's submodules (`git submodule update --init
--recursive`).

```bash
npm run test:cases                                             # all six
FOUNDRY_PROFILE=cases forge test --match-path 'cases/03-*/*'   # one case
```

The cases have their own Foundry profile, so the rest of the repository's
gates (build, coverage, `slither .`, the gas snapshot) never compile a contract
that is broken on purpose.

## What a case holds

- **`README.md`:** what breaks, what it looks like from outside, why, and the
  fix.
- **`Broken.sol` and `Fixed.sol`.** Case 04 has three versions instead of two,
  because the obvious fix is also broken.
- **`CaseNN.t.sol`:** tests that run both versions through `handleOps` and show
  the difference. Every fixed version was broken once, by putting its bug back,
  to prove its tests fail when they should.

## The harness, and what it is not

[`shared/CaseTest.sol`](shared/CaseTest.sol) deploys the real EntryPoint v0.8,
real `SimpleAccount`s from the real factory, and calls `handleOps` the way a
bundler does. There are no mocks.

What it cannot be is a bundler. Nothing on chain enforces ERC-7562, the rules
bundlers apply while they validate an operation. The harness stands in for the
smallest part of that: `_bannedOpcodeInValidation` records every opcode a
paymaster's validation executes, using Foundry's debug trace, and checks them
against ERC-7562's OP-011 and OP-080. A bundler checks far more: storage access,
which addresses validation calls, staking and reputation. A zero from the
harness means "none of those opcodes ran", not "a bundler will accept this".

## What a static check can see

Only case 01. [`slither-erc7562`](../tools/slither-erc7562) finds it in the
source before anything is deployed, and
[`check-detector.py`](check-detector.py) confirms in CI that it reports exactly
that case and nothing else here, and that the last column of the table above
says the same. The other five are about limits, accounting, and what a
signature binds. They are found by tests like these, by a bundler, or in
production.

The detector's silence about the other twelve paymasters is not taken on its
word. Each of them, broken and fixed, has a test that traces its validation and
finds none of those opcodes, so the static answer and the executed one are
checked against each other for every contract here.

## Where these come from

All six are from building Monarch, and none is a finding about anyone else's
code.

- **Four are failures I shipped.** Cases 01 and 06 were in the first version of
  this paymaster; [the teardown](../docs/teardown-basepaymaster.md) tells that
  story. Case 03 was live on Base Sepolia until I found it, and case 02 was
  deployed there as the fix for case 03 and could not send a single operation.
- **Two are decisions Monarch had to make:** cases 04 and 05, each shown with
  the version Monarch did not choose, and why.
