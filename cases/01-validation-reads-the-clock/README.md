# 01: Validation reads the clock

**ERC-7562 OP-011. A static check sees it.**

## What breaks

`ClockCheckingPaymaster` sponsors operations until an expiry, and checks the
expiry itself:

```solidity
if (block.timestamp > validUntil) return ("", SIG_VALIDATION_FAILED);
```

## What it looks like

In your tests, nothing. The paymaster compiles, passes its unit tests, and
passes real `handleOps` calls against the real EntryPoint, because nothing on
chain enforces ERC-7562. `test_bothVersionsPassTheEntryPoint` is that trap.

In production, every bundler rejects every operation it sponsors, as an opcode
violation, when the operation is submitted. By then the paymaster is deployed,
staked and funded.

## Why

A bundler simulates validation before it builds a block, then pays gas to put
the operation on chain. If validation reads the clock, the answer the bundler
simulated is not the answer the block gets, and the bundler pays for the
difference. So ERC-7562 bans the opcodes whose values change between the two:
TIMESTAMP, NUMBER, BLOCKHASH and the rest of OP-011. Bundlers trace every
opcode validation executes, including inside modifiers, libraries and inline
assembly, and drop the operation if one of them appears.

`test_theBrokenVersionsAnswerDependsOnWhenItIsAsked` shows the reason: valid
when simulated, invalid an hour later.

## The fix

Return the window instead of judging it. `WindowReturningPaymaster` packs
`validUntil` into `validationData`, and the EntryPoint compares it with the
clock after validation, where no opcode rule applies. The window is still
enforced (`test_theFixedVersionStillEnforcesTheWindow`), by the EntryPoint
instead of the paymaster, which rejects the operation with
`AA32 paymaster expired or not due`.

The paymaster decides; it never observes.

## Run it

```bash
FOUNDRY_PROFILE=cases forge test --match-path 'cases/01-*/*'
```

`test_theBrokenVersionRunsTimestampDuringValidation` records the opcodes the
broken version's validation executes, as a bundler's tracer would, and finds
TIMESTAMP. The fixed version runs none of the opcodes OP-011 lists.

The detector finds it from source alone:

```text
ClockCheckingPaymaster.validatePaymasterUserOp reaches TIMESTAMP via `block.timestamp` in _validate.
ERC-7562 OP-011 forbids it during validation. [...]
	- block.timestamp > validUntil (cases/01-validation-reads-the-clock/Broken.sol#30)
```

## Where it came from

The first version of Monarch read `block.timestamp` inside
`validatePaymasterUserOp` four times, one of them two calls deep in a library.
It is defect 8 in [the teardown](../../docs/teardown-basepaymaster.md), and the
reason [`slither-erc7562`](../../tools/slither-erc7562) exists.
