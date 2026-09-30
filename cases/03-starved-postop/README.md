# 03: Too little gas for `postOp`

**The paymaster pays, nobody is charged, and the sender can repeat it. No
static check sees it.**

## What breaks

`UnflooredDepositPaymaster` holds users' prepaid gas in one EntryPoint deposit
and charges each operation to its sender in `postOp`. It never checks
`paymasterPostOpGasLimit`, which the sender chooses.

## What it looks like

Nothing fails. The bundle succeeds, and the paymaster's deposit goes down. The
sender's balance does not (`test_brokenChargesNobodyWhenPostOpIsStarved`).

Because the sender's balance never falls, validation never stops them. Twenty
rounds later the paymaster holds less than it owes its users
(`test_repeatingItDrainsSomeoneElsesDeposit`). The owner's buffer goes first,
then other users' deposits.

## Why

With too little gas, `postOp` runs out partway through. EntryPoint v0.8 does not
fail the bundle over that. It rolls the operation back, settles it in
`postOpReverted` mode, which never calls `postOp` again, and takes the cost from
the paymaster's deposit. The debit that `postOp` would have recorded against the
sender never happens.

The operation's own effects are rolled back too, so the sender gains nothing but
free gas. That makes it griefing rather than theft, but it ends in insolvency.

## The fix

Refuse an operation this paymaster could not charge for:

```solidity
if (limit < MIN_POSTOP_GAS_LIMIT) revert PostOpGasLimitTooLow(limit, MIN_POSTOP_GAS_LIMIT);
```

A revert rather than a signature failure: the check reads only the operation's
own fields, so a bundler's simulation sees it and drops the operation before it
is ever in a bundle. And a floor only; [case 02](../02-postop-gas-ceiling) is
why there is no ceiling.

Measure the floor for your own `postOp`, then add a margin.
`test_theFloorLeavesRoomToSpare` finds where this one starves (9,000 gas) and
checks the 20,000 floor clears it by at least half again. Monarch's `postOp`
starves at 11,000, and its floor is also 20,000.

## Run it

```bash
FOUNDRY_PROFILE=cases forge test --match-path 'cases/03-*/*' -vv
```

`-vv` prints what the drained paymaster owes against what it holds, and where
this `postOp` starves.

## Where it came from

The first Monarch deployed to Base Sepolia had no floor. I found this while
calibrating its gas overhead, and the floor went into the next version, which
also shipped the ceiling in [case 02](../02-postop-gas-ceiling).
