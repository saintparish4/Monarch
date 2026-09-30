# 06: The owner withdraws against the whole EntryPoint deposit

**The owner can take users' prepaid balances. No static check sees it.**

## What breaks

`PooledDepositPaymaster` lets users prepay gas. Their money goes into the
paymaster's EntryPoint deposit, and a ledger records whose it is. It is built on
upstream `BasePaymaster`, and inherits its `withdrawTo`:

```solidity
function withdrawTo(
  address payable withdrawAddress,
  uint256 amount
) public onlyOwner {
  entryPoint.withdrawTo(withdrawAddress, amount);
}
```

## What it looks like

The owner asks for the whole deposit and gets it. The ledger still says each
user has their balance; the EntryPoint says the paymaster holds nothing, and
the first user to try to withdraw gets `Withdraw amount too large`
(`test_brokenOwnerCanWithdrawTheUsersDeposit`).

## Why

`BasePaymaster.withdrawTo` is correct for the paymaster it was written for, one
whose whole deposit is the owner's money. A paymaster that pools users' funds
in the same deposit changes what that function means, and nothing in it knows.

The natural fix, overriding it with a solvency check, does not compile, because
`withdrawTo` is not `virtual`:

```text
Error (4334): Trying to override non-virtual function. Did you forget to add "virtual"?
```

## The fix

Don't inherit `BasePaymaster` once the deposit holds anyone else's money.
`SolventDepositPaymaster` restates the EntryPoint plumbing (about fifty lines in
Monarch) and writes its own `withdrawTo`, which only reaches the part of the
deposit no user has a claim on:

```solidity
uint256 free = freeBalance(); // EntryPoint deposit minus what users are owed
if (amount > free) revert WouldBreakSolvency(amount, free);
```

`test_fixedOwnerCannotWithdrawTheUsersDeposit` and
`test_fixedOwnerCanStillWithdrawTheirOwn` pin both sides. The upstream
interfaces and helpers are still used; only the base contract goes.

## Run it

```bash
FOUNDRY_PROFILE=cases forge test --match-path 'cases/06-*/*'
```

Validation is not where this bug lives, so nothing that inspects validation can
find it (`test_noOpcodeCheckCatchesTheBrokenVersion`).

## Where it came from

The first version of Monarch let an admin withdraw against the balance backing
user deposits: defects 5 and 6 in
[the teardown](../../docs/teardown-basepaymaster.md). Rewriting it, I found the
override would not compile, which is why Monarch does not inherit
`BasePaymaster` and why its `withdrawTo` checks `freeBalance()`.
