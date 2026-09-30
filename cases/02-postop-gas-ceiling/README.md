# 02: A ceiling on the postOp gas limit

**The paymaster cannot be gas-estimated, so it is never used. No static check
sees it.**

## What breaks

`CappedPostOpPaymaster` refuses a `paymasterPostOpGasLimit` outside a band:

```solidity
if (limit < MIN_POSTOP_GAS_LIMIT || limit > MAX_POSTOP_GAS_LIMIT) {
    revert PostOpGasLimitOutOfRange(limit, MIN_POSTOP_GAS_LIMIT, MAX_POSTOP_GAS_LIMIT);
}
```

The floor is right; [case 03](../03-starved-postop) is what happens without it.
The ceiling is the bug. It looks like prudence: a payer who asks for far more
postOp gas than `postOp` needs makes the paymaster pay a penalty on the unused
part.

## What it looks like

Every test that uses a sensible limit passes
(`test_brokenAcceptsTheLimitItWasTestedWith`). Then a real wallet tries to use
the paymaster and gets:

```text
AA33 reverted PostOpGasLimitOutOfRange(2000000, 20000, 40000)
```

That is the exact error Monarch's demo got from a public bundler on Base
Sepolia, and it came back before any operation was sent.

## Why

Before a wallet can send an operation it asks a bundler to estimate its gas
limits (`eth_estimateUserOperationGas`). The bundler does that by simulating the
operation with paymaster gas limits far above anything real, then measuring
what was used. The bundler behind Monarch's demo simulated with a postOp limit
of 2,000,000. A paymaster that reverts on a large limit reverts during that
simulation, so the estimate fails, so the wallet has nothing to send.

`test_brokenRejectsTheLimitABundlerEstimatesWith` reproduces it.

## The fix

A floor, and no ceiling. An oversized limit is a cost, not a danger: EntryPoint
v0.8 bills the paymaster a tenth of whatever part of the limit goes unused
(waived when the unused part is under 40,000 gas).
`test_anOversizedLimitCostsThePaymasterAPenalty` measures it. If that cost
matters to you, price it into what the payer is charged, which is what
Monarch's `_unusedPostOpGasPenalty` does. Never refuse the operation over it.

## Run it

```bash
FOUNDRY_PROFILE=cases forge test --match-path 'cases/02-*/*'
```

Neither version runs a forbidden opcode (`test_noOpcodeCheckCatchesTheBrokenVersion`).
The ceiling is legal; it is only wrong.

## Where it came from

I added the band to Monarch as the fix for [case 03](../03-starved-postop), and
deployed it to Base Sepolia as `0xB21BB74e…58531`. The demo could not send a
single operation through it. The next deployment removed the ceiling and priced
the penalty instead; the retired address and why it was retired are in
[`deployments/base-sepolia.json`](../../deployments/base-sepolia.json).
