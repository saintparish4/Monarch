# 05: A sponsorship signature that leaves fields out

**The sender spends the app's money on something the app never agreed to. No
static check sees it.**

## What breaks

An app sponsors an operation by signing a digest off-chain; the paymaster
recovers the signer during validation. `CallBlindSponsorPaymaster` builds that
digest from the sender, the nonce, the time window, the chain and itself:

```solidity
keccak256(abi.encode(userOp.sender, userOp.nonce, validUntil, validAfter, block.chainid, address(this)))
```

Everything that identifies _whose_ operation it is. Nothing about _what_ it
does, or how much gas it may burn.

## What it looks like

The app's backend looks at an operation, decides it is worth paying for, and
signs. The sender then changes the operation and signs it again as the account
owner. The app's signature still recovers, because nothing it covered changed:

- `test_brokenSponsorsACallTheAppNeverApproved`: the sender swaps the call data
  for a different call. It runs, and the app pays.
- `test_brokenLetsTheSenderRaiseTheGasTheAppPaysFor`: the sender raises the call
  gas limit tenfold. The call uses no more gas, but EntryPoint v0.8 bills a
  tenth of unused call gas, so the app pays about 90,000 gas more for nothing.

## Why

The account's signature and the app's signature protect different people. The
account owner signs to prove the operation is theirs; the sender can re-sign
anything. The app's signature is the only thing that protects the app, so it has
to cover every field the app's decision depended on.

## The fix

`CallBoundSponsorPaymaster` hashes every field of the operation except the
account's signature, and `paymasterAndData` up to the app's signature, which
covers this paymaster, both paymaster gas limits and the time window in one
slice. Change any of them and the signature fails to recover: the EntryPoint
rejects the operation with `AA34 signature error`
(`test_fixedRefusesACallTheAppNeverApproved`, `test_fixedRefusesRaisedGasLimits`).

Two habits keep it that way:

- **Hash slices, not lists of fields.** Listing the fields by hand is how the
  gas limits get left out.
- **Serve the digest from the contract.** The app's backend should get it from
  `getHash` over an `eth_call`, not re-derive the packing. Two implementations
  of one hash drift.

## Run it

```bash
FOUNDRY_PROFILE=cases forge test --match-path 'cases/05-*/*'
```

The broken version runs no forbidden opcode: its digest is valid, just
incomplete.

## Where it came from

A decision Monarch had to get right rather than a bug it shipped. Its
`getSponsorshipHash` covers every field, and
[`MonarchPaymaster.signatures.t.sol`](../../test/unit/MonarchPaymaster.signatures.t.sol)
pins the digest field by field: call data, both account gas limits, both
paymaster gas limits, the time window, the nonce, the sender, the chain and the
paymaster.
