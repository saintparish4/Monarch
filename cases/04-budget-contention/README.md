# 04: Several sponsorships against one budget

**The overdraw lands on other apps, or the paymaster gets banned. No static
check sees it. This case ends in a limit, not a fix.**

## The setup

A paymaster holds budgets for several apps in one EntryPoint deposit. Each
operation names the app that pays, and validation checks that app's budget
covers the operation's maximum cost:

```solidity
if (budgets[app] < maxCost) revert InsufficientBudget(app, maxCost, budgets[app]);
```

In a bundle, the EntryPoint runs every operation's validation before any
operation's `postOp`. So every operation from the same app is checked against
the same budget, and a budget big enough for any one of them can be committed to
all of them. Validation cannot see what the others will spend. It is the
question "does its accounting survive failure?" at its sharpest.

There are three versions here, because the obvious fix is also broken.

## Broken: `CheckedBudgetPaymaster`

`postOp` subtracts with checked arithmetic. Once the earlier operations have
spent the budget, the next subtraction underflows, `postOp` reverts, and the
EntryPoint settles that operation in `postOpReverted` mode (see
[case 03](../03-starved-postop)): rolled back, charged to nobody, paid from the
whole deposit.

`test_brokenLetsTheOverdrawLandOnAnotherApp`: after a bundle of six, the app
still shows budget left, its last user's operation was rolled back, and the
deposit no longer covers the other app's budget.

## Also broken: `ReservingBudgetPaymaster`

The tempting fix: reserve `maxCost` during validation and refund the unused part
in `postOp`. A staked paymaster may write its own storage during validation
(ERC-7562 STO-031), and the ledger is now exact.

But each operation's validation now depends on the operations validated before
it in the same bundle. A bundler validates each operation on its own, finds each
one valid, builds a bundle from them, and the second one fails inside it
(`test_reservingPassesEachOperationAloneButFailsTheBundle`). ERC-7562's GREP-040
says an entity that fails bundle creation after passing the second validation
is **banned**.

## Bounded: `BoundedBudgetPaymaster`

What Monarch does. Validation stays a pure check. `postOp` never takes more than
the app has, and the owner keeps a buffer in the deposit that no budget claims.
The overdraw comes out of the buffer, never out of another app's budget
(`test_boundedKeepsTheOverdrawInTheOwnersBuffer`).

This bounds the damage; it does not remove it. Without a buffer, the clamp has
nowhere to put the overdraw but the rest of the deposit
(`test_theBoundNeedsTheBuffer`). Making it safe takes two things outside the
contract:

- **Size the buffer** for the worst case you will allow: the operations an app
  can have outstanding at once, times their maximum cost, minus its budget.
- **Bound outstanding sponsorships where they are signed.** The app's backend is
  the only party that knows how many sponsorships it has signed and not yet seen
  settle. Validation cannot know.

The only bundler-side limit is ERC-7562's EREP-010, which caps what a
paymaster's operations in the mempool may cost at its whole deposit, not at any
one app's budget.

## Run it

```bash
FOUNDRY_PROFILE=cases forge test --match-path 'cases/04-*/*' -vv
```

`test_oneOperationAloneLeavesEveryVersionSolvent` is the control: uncontended,
all three versions keep their books, so what breaks in the other tests is
contention and nothing else.

None of the three runs a forbidden opcode (`test_noOpcodeCheckCatchesAnyOfThem`).
What gets the reservation banned is behaviour across a bundle, which no opcode
check can see.

## Where it came from

Monarch's validation is `view` and its `postOp` clamps, for the reasons above.
Its own tests pin the same limit:
`test_manyOpsFromOnePayerOverdrawIntoTheOwnerBuffer` and
`test_withoutAnOwnerBufferTheEntryPointRefusesTheSecondOp`, in
[`test/integration/Bundle.t.sol`](../../test/integration/Bundle.t.sol).

The authorization is left out of all three versions, so the files differ only
in their accounting. [Case 05](../05-unbound-sponsorship) is about the
signature.
