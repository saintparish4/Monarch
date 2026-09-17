# Teardown: Monarch's first paymaster

Before `MonarchPaymaster` there was `BasePaymaster`: 603 lines in
`contracts/libraries/BasePayments.sol`, plus a hand-written `IPaymaster`, a
security library, a math library and an event-heavy module interface. I wrote it.
It was deleted in [`bf2de66`](https://github.com/saintparish4/Monarch/commit/bf2de667c92ef5885f8f591e55870cfb0b6c8102),
and every design rule in the contract that replaced it traces back to a line in
this one.

This is the teardown. Every quote below is from commit
[`e787664`](https://github.com/saintparish4/Monarch/tree/e78766495460129359bfc18210cd66155a625acd),
the last commit before the rewrite, and every claim about behaviour was checked
against the EntryPoint source or run, not inferred from reading alone.

## The short version

**It did not compile.** `solc` stops at the first of three errors:

```
Error: Expected '{' but got 'if'
   --> contracts/libraries/Security.sol:106:9
```

**Repaired, no current EntryPoint can call it.** It was written against the
ERC-4337 v0.6 interface: the unpacked `UserOperation` struct, a three-argument
`postOp`, the mode byte at offset 20. Its function selectors are the v0.6 ones
(`0xf465c77e`, `0xa9a23409`); v0.7 and v0.8 call different ones entirely
(`0x52b7512c`, `0x7c627b21`), so against either, every call reverts before
reaching a line of it.

**Against v0.6, the one EntryPoint that can call it, it rejects every
operation** — even with the EntryPoint deposit it never made (defect 4) supplied
from outside. Validation returns three values, `(context, validAfter, validUntil)`.
The EntryPoint decodes two, so `validationData` is `validAfter`, which is
`block.timestamp`. The low 160 bits of `validationData` are the signature
aggregator field, a timestamp there is non-zero, and a non-zero aggregator from a
paymaster is:

```solidity
if (pmAggregator != address(0)) {
    revert FailedOp(opIndex, "AA34 signature error");
}
```

I did not want to rest the claim on reading ABI decoding rules, so I reproduced
it: a contract with the old return shape, called through the v0.6 interface,
hands back `validationData == block.timestamp` with the context still decoding
cleanly. The aggregator field came out as `0x…6aa1f940`.

So the nine defects below were never nine ways it failed in production. It never
got there. They are worth writing down anyway, because each one is an easy
mistake to make again, and most of them would have survived the compile errors
being fixed.

## What was torn down

| File at `e787664`                                 | Lines | In the rewrite                                |
| ------------------------------------------------- | ----- | --------------------------------------------- |
| `contracts/libraries/BasePayments.sol`            | 603   | Deleted                                       |
| `contracts/gasless/interfaces/IPaymaster.sol`     | 185   | Deleted — replaced by the canonical interface |
| `contracts/gasless/interfaces/IUserOperation.sol` | 110   | Deleted — replaced by the canonical struct    |
| `contracts/libraries/Security.sol`                | 308   | Deleted                                       |
| `contracts/libraries/Math.sol`                    | 221   | Deleted                                       |
| `contracts/interfaces/IModule.sol`                | 84    | Deleted                                       |
| `contracts/libraries/Constants.sol`               | 108   | Rewritten                                     |
| `contracts/libraries/Validation.sol`              | 275   | Rewritten                                     |

`bf2de66` deleted thirteen Solidity files in total.

## The nine defects

| #   | Defect                                                                       | Where                              | Locked out by                                                         |
| --- | ---------------------------------------------------------------------------- | ---------------------------------- | --------------------------------------------------------------------- |
| 1   | `postOp` treats the EntryPoint's outcome code as a payment mode              | [`BasePayments.sol#L161-L179`][d1] | `test_defect1_postOpModeDoesNotSelectPayer`                           |
| 2   | `postOp` has three arguments; v0.7+ passes four                              | [`IPaymaster.sol#L86-L90`][d2]     | The compiler                                                          |
| 3   | Validation returns `(bytes, uint256, uint256)` instead of `(bytes, uint256)` | [`IPaymaster.sol#L74-L78`][d3]     | The compiler                                                          |
| 4   | Funds never reach the EntryPoint                                             | [`BasePayments.sol#L353-L364`][d4] | `test_defect4_fundsReachTheEntryPoint`                                |
| 5   | Withdrawal debits the named user and pays the caller                         | [`BasePayments.sol#L280-L290`][d5] | `test_defect5_withdrawDebitsTheCallerOnly`                            |
| 6   | Admin withdrawal draws on the balance backing user deposits                  | [`BasePayments.sol#L370-L376`][d6] | `test_defect6_withdrawToRespectsSolvency`                             |
| 7   | Mode byte read at offset 20, the v0.6 position                               | [`BasePayments.sol#L522-L531`][d7] | `test_defect7_modeByteIsReadAtOffset52NotOffset20`                    |
| 8   | `block.timestamp` read during validation                                     | [`BasePayments.sol#L146-L150`][d8] | `test_defect8_*` and the [Slither detector](../tools/slither-erc7562) |
| 9   | `totalUsersSponsored` declared, never written                                | [`BasePayments.sol#L51`][d9]       | The field no longer exists                                            |

### It restated an interface it did not own (2, 3)

The old code imported its `IPaymaster` from a file in this repository, not from
`eth-infinitism/account-abstraction`:

```solidity
function validatePaymasterUserOp(
  IUserOperation.UserOperation calldata userOp,
  bytes32 userOpHash,
  uint256 maxCost
)
  external
  returns (bytes memory context, uint256 validAfter, uint256 validUntil);

function postOp(
  PaymasterMode mode,
  bytes calldata context,
  uint256 actualGasCost
) external;
```

A local copy of an interface agrees with whatever its author believed, and the
compiler checks the implementation against the copy. Both declarations were
wrong in ways a compiler would have caught instantly against the real one.

The rewrite imports `IPaymaster`, `PackedUserOperation` and
`_packValidationData` from upstream and implements the real interface. That turns
defects 2 and 3 from runtime bugs into build errors, which is the strongest form
a guarantee takes, and is why neither has a test: a test that could only fail if
the build had already failed would be checking nothing.

### It confused two enums (1)

The first argument of `postOp` is the EntryPoint's `PostOpMode`: `opSucceeded`,
`opReverted`, `postOpReverted`. The old code declared the same slot as its own
payment-mode enum — `FREE`, `SUBSCRIPTION`, `TOKEN_PAYMENT`, `DEPOSIT_BASED` —
and chose the payer from it:

```solidity
function postOp(PaymasterMode mode, bytes calldata context, uint256 actualGasCost)
    external override onlyEntryPoint
{
    (address user, PaymasterMode contextMode, uint256 maxCost, uint256 timestamp) =
        abi.decode(context, (address, PaymasterMode, uint256, uint256));

    require(mode == contextMode, "Mode mismatch");
```

I had recorded this defect as "a succeeded operation is billed to a different
scheme than a reverted one". Reading it again for this write-up, that is not
what it does. The `require` compares the outcome code against the payment mode
stored in the context, and the two only coincide by numeric accident: the
`require` passes for a `FREE` operation that succeeded (0 = 0) and a
`SUBSCRIPTION` operation that reverted (1 = 1), and for nothing else. A subscription operation that _succeeds_
reverts with "Mode mismatch". A `DEPOSIT_BASED` operation is mode 3, which no
outcome code ever equals, so every deposit operation's `postOp` reverts and no
deposit is ever debited.

In the rewrite `postOp` names the argument, documents that it is deliberately
unused when choosing who pays, and reads the payer only from the context
validation wrote. The regression test runs the same sponsored context through
`opSucceeded` and `opReverted` and asserts the same budget is charged both times.

### It read the v0.6 layout (7)

```solidity
if (paymasterAndData.length >= 21) {
    uint8 modeValue = uint8(paymasterAndData[20]);
```

Under v0.6, byte 20 is the first byte after the paymaster address. Under v0.7 and
later, bytes 20–51 are the paymaster's two gas limits and its own data starts at
byte 52. Byte 20 is the most significant byte of a `uint128` gas limit, which is
zero for any limit below 2¹²⁰. Ported to v0.7 without this line changing, every
operation would have decoded as mode 0, `FREE`.

The rewrite names every offset in `Constants` rather than writing literals at the
call site, and the regression test builds `paymasterAndData` with byte 20 saying
"sponsored" and byte 52 saying "deposit", then asserts the paymaster believes
byte 52.

### The money never reached the EntryPoint (4)

A paymaster pays for operations out of its deposit _on the EntryPoint_. This one
kept every wei on itself and said so in the comments:

```solidity
function getPaymasterDeposit()
  external
  view
  override
  returns (uint256 balance)
{
  // In production, this would call entryPoint.balanceOf(address(this))
  return address(this).balance;
}

function addPaymasterDeposit() external payable override onlyAdmin {
  // In production, this would call entryPoint.depositTo{value: msg.value}(address(this))
  emit PaymasterDepositAdded(msg.value);
}
```

`entryPoint` was a bare `address` and no EntryPoint interface was imported; the
string `depositTo` appears in the old tree only inside that comment. A v0.6 EntryPoint
checks the paymaster's deposit before it calls the paymaster at all, so with a
zero deposit every operation stops at `AA31 paymaster deposit too low` — the
first of the two independent reasons nothing would have worked. "In production, this would" is the sentence to be most suspicious of in
any contract: there is no later build in which the comment becomes code.

### Anyone with admin could take anyone's deposit (5, 6)

```solidity
function withdrawDeposit(address user, uint256 amount) external override {
    require(msg.sender == user || _security.isAdmin(msg.sender), "Unauthorized");
    require(deposits[user] >= amount, "Insufficient deposit");

    deposits[user] = deposits[user].safeSub(amount);

    (bool success,) = payable(msg.sender).call{value: amount}("");
```

The account debited is `user`; the account paid is `msg.sender`. Any caller that
passes `isAdmin` can move any user's deposit into their own wallet.

```solidity
function withdrawPaymasterDeposit(uint256 amount) external override onlyAdmin {
    // In production, this would call entryPoint.withdrawTo(payable(msg.sender), amount)
    require(address(this).balance >= amount, "Insufficient balance");
    (bool success,) = payable(msg.sender).call{value: amount}("");
```

The only check is the contract's whole balance, which is the same ETH credited to
every `deposits[user]`. Nothing subtracts what users are owed. And `onlyAdmin`
does not check the admin role — `Security.requireAdmin` checks `isOperator`, a
looser one. In practice the contract had no function that granted either role,
so "any admin" meant the owner; the point is that the owner could take everything.

The rewrite is built around one inequality,

```
entryPoint.balanceOf(paymaster)  >=  totalUserDeposits + totalAppBudgets
```

and every value-moving function preserves it. `withdrawUserDeposit` has no `user`
argument and always debits `msg.sender`. The owner's `withdrawTo` is capped at
`freeBalance()`, the excess above that sum. The inequality is checked as a
stateful invariant over every value-moving entrypoint, not only in the two
regression tests named here.

### It read the clock during validation (8)

```solidity
context = abi.encode(user, mode, maxCost, block.timestamp);

// Set validity period (24 hours from now)
validAfter = block.timestamp;
validUntil = block.timestamp + Constants.SECONDS_PER_DAY;
```

ERC-7562 forbids `TIMESTAMP` during validation, because its value differs between
the bundler's simulation and inclusion. Bundlers enforce the rule off-chain, in a
tracer. Nothing on-chain enforces it: a violating paymaster compiles, passes
every test and passes a real `handleOps` call, and is then dropped by every
bundler after it has been deployed, staked and funded.

There is a fourth read, one call deeper. Subscription validation calls
`Constants.isInCurrentMonth`, which calls `getCurrentMonthStart`:

```solidity
function getCurrentMonthStart() internal view returns (uint256 monthStart) {
    uint256 currentTime = block.timestamp;
```

This defect is the one that became a tool. [`slither-erc7562`](../tools/slither-erc7562)
walks everything reachable from `validatePaymasterUserOp` and reports banned
opcodes. Against this code, with only the three compile errors repaired, it
reports lines 146, 149 and 150 in under a second. **It does not report the
fourth.** The detector follows `internal_calls`, and Slither files a call into an
internal library function such as `Constants.isInCurrentMonth(...)` under library
calls instead, so the walk never enters it. That is a false negative in my own
tool, found by writing this, and it is the next thing to fix there.

The old validation also _reverted_ when it declined to sponsor:
`revert PaymasterValidationFailed("Insufficient sponsorship")`. A revert during
validation makes the whole bundle unmineable and gets the paymaster throttled.
The rewrite's validation is `view`, returns its time window for the EntryPoint to
enforce rather than evaluating it, and reports a bad signature as a return value.

### Dead state (9)

`uint256 public totalUsersSponsored;` is declared and never assigned.
`maxGasSponsorshipPerMonth` is its sibling: written by `configure`, emitted in an
event, and never compared against anything. A public counter that is never
written reads as a guarantee to anyone integrating against it.

## What the list of nine missed

Found while writing this, each checked against the source:

- **The gas buffer is 1.2%, not 20%.** `GAS_PRICE_MULTIPLIER = 120; // 20% buffer`
  is passed to `calculatePercentage`, which divides by a basis-point base of
  10,000.
- **`FREE` mode compares wei to gas.** `addToWhitelist` requires the limit to be at
  least `MIN_GAS_LIMIT` (21,000 gas); validation then compares it to `maxCost`,
  which is wei.
- **Subscriptions never expire.** `createSubscription` validates a `duration` and
  never stores it.
- **Deposits are not reserved during validation.** Two operations in one bundle
  can both pass `deposits[user] >= maxCost` against the same balance, and the
  second `postOp`'s `safeSub` then reverts.
- **There is no stake.** Nothing calls `addStake`. A field named `minimumStake`
  exists, and is the fee an admin pays to create a subscription.
- **An out-of-range mode byte panics** converting to the enum (`0x21`) before the
  custom `InvalidPaymasterMode` error it was meant to raise can be built.
- **`UserOpSponsored` always logs `bytes32(0)`** as the operation hash.

## What changed because of it

- **Import the standard, don't restate it.** Two of nine defects became compile
  errors the moment the contract implemented the canonical `IPaymaster`.
- **One invariant, and every function answers to it.** Solvency is the property
  the contract exists to preserve, restated as `freeBalance()` and checked as a
  stateful invariant rather than hoped for.
- **Validation decides; `postOp` records.** No clock, no writes, no reverts for a
  bad signature.
- **No mocks of anything I do not own.** Every test runs against real EntryPoint
  v0.8 bytecode. A mock EntryPoint would have agreed with the local `IPaymaster`
  exactly as the compiler did, and that agreement is the bug class this list is
  mostly made of.
- **Every defect has a name in the test suite**, so a rewrite of the rewrite cannot
  quietly reintroduce one.

[d1]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L161-L179
[d2]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/gasless/interfaces/IPaymaster.sol#L86-L90
[d3]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/gasless/interfaces/IPaymaster.sol#L74-L78
[d4]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L353-L364
[d5]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L280-L290
[d6]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L370-L376
[d7]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L522-L531
[d8]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L146-L150
[d9]: https://github.com/saintparish4/Monarch/blob/e78766495460129359bfc18210cd66155a625acd/contracts/libraries/BasePayments.sol#L51
