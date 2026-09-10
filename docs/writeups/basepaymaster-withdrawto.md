# The base class you cannot safely inherit

*Why `BasePaymaster.withdrawTo` is an owner function that drains user funds,
and why you cannot fix it by overriding.*

---

If you are writing an ERC-4337 paymaster, the obvious move is to inherit
`BasePaymaster` from `eth-infinitism/account-abstraction`. It is the reference
implementation. It handles the EntryPoint plumbing — deposits, stake, the
`_requireFromEntryPoint` check — so you only write your own policy.

I did not inherit it. This is the reason, and it is narrow enough to state
precisely.

## The setup

A paymaster keeps one balance at the EntryPoint. `entryPoint.balanceOf(paymaster)`
is a single number, and it is what the EntryPoint draws on to pay bundlers.

Most non-trivial paymasters put more than one claim on that single pot. Mine
has two:

- **User deposits.** A user tops up once and spends it across later operations
  without holding the chain's gas token.
- **App budgets.** An app funds a budget and sponsors its users' operations
  from it.

Both live in that one EntryPoint balance. So the paymaster owes:

```
totalUserDeposits + totalAppBudgets
```

and anything above that is genuinely the owner's — fees, over-funding, dust.
The solvency property is:

```
entryPoint.balanceOf(paymaster)  >=  totalUserDeposits + totalAppBudgets
```

The owner may withdraw the excess. Never more.

## The problem

`BasePaymaster` ships this:

```solidity
function withdrawTo(address payable withdrawAddress, uint256 amount)
    public
    onlyOwner
{
    entryPoint.withdrawTo(withdrawAddress, amount);
}
```

`amount` is unbounded against the **raw EntryPoint balance**. It knows nothing
about `totalUserDeposits` or `totalAppBudgets`, because those are my
bookkeeping and the base class has never heard of them.

So the owner can withdraw everything, including every user's deposit and every
app's budget.

This is not a bug in `BasePaymaster`. For a paymaster whose whole EntryPoint
balance genuinely belongs to the operator — which describes most of them — it
is exactly right. It becomes a vulnerability the moment you hold funds on
behalf of anyone else, and holding funds on behalf of someone else is what a
deposit-mode paymaster *is*.

## Why you cannot override it

The normal answer is to override and add the check:

```solidity
function withdrawTo(address payable to, uint256 amount) public override onlyOwner {
    require(amount <= freeBalance(), "would touch user funds");
    super.withdrawTo(to, amount);
}
```

That does not compile. **`withdrawTo` is not `virtual`.**

Solidity will not let you override a non-virtual function. There is no
modifier, no hook, no `_beforeWithdraw` to reach. Inheriting `BasePaymaster`
means shipping a `public onlyOwner` function that drains user funds, with no
mechanism available to you for closing it.

Worth being clear about what this is and is not. It is not a way for a stranger
to steal — it is `onlyOwner`. It is that the contract cannot make a promise it
has no way to keep. "Your deposit is safe" is false if the owner key can take
it, and the owner key includes whoever compromises it. A trust model you cannot
enforce in code is a trust model you are asking people to take on faith.

## What I did instead

Implemented `IPaymaster` directly and restated the roughly fifty lines of
EntryPoint forwarding — `deposit`, `addStake`, `unlockStake`, `withdrawStake`,
`getDeposit`, `_requireFromEntryPoint`. It is duplication, and I would rather
not have written it.

What it buys:

```solidity
function freeBalance() public view returns (uint256) {
    uint256 balance = entryPoint.balanceOf(address(this));
    uint256 owed = totalUserDeposits + totalAppBudgets;
    return balance > owed ? balance - owed : 0;
}

function withdrawTo(address payable to, uint256 amount) external onlyOwner {
    if (amount > freeBalance()) revert WouldBreakSolvency(amount, freeBalance());
    entryPoint.withdrawTo(to, amount);
}
```

The owner withdraws the excess. Never user funds, never app funds — not as a
policy, as a thing the contract will not do.

That property is checked as a stateful invariant over every value-moving
entrypoint, at 512 runs and depth 64 with `fail_on_revert = true`, and again
after every `handleOps` bundle the tests actually run. It is not a comment.

## The general shape

`virtual` is an API decision, not a formality. A base class that is not
`virtual` is a base class asserting that its behaviour is correct for every
subclass — and for a function that moves money, that assertion is almost never
safe to make.

The reason this one is worth writing down is that inheriting is the *default*
advice. "Extend the reference implementation" is what you would tell a junior
engineer, and it is usually right. Here it silently hands you a function you
cannot remove, guarding money that is not yours.

Three questions worth asking of any base class you inherit to handle funds:

1. **What can the owner do that the subclass cannot prevent?** Enumerate the
   `onlyOwner` surface and ask which functions move value.
2. **Is every one of them `virtual`?** If not, that behaviour is now yours
   whether you want it or not.
3. **Does the base class know about all the claims on the balance it manages?**
   If your subclass introduces a second claim, the base class's arithmetic is
   wrong by construction.

If the answers are bad, restating fifty lines is cheap. Cheaper than a
withdrawal function you have to explain in an audit and cannot fix.

---

*Source: [`saintparish4/Monarch`](https://github.com/saintparish4/Monarch) —
an ERC-4337 v0.8 paymaster. 96 tests against real EntryPoint bytecode, 99.2%
line coverage, and a Slither detector for the ERC-7562 validation rules that
nothing on-chain enforces.*
