// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {_packValidationData, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Constants} from "./libraries/Constants.sol";
import {Validation} from "./libraries/Validation.sol";

/// @title MonarchPaymaster
/// @notice An ERC-4337 v0.8 paymaster that lets a consumer app pay its users' gas.
///
/// @dev THE INVARIANT. Everything in this contract exists to preserve:
///
///        entryPoint.balanceOf(this) >= totalUserDeposits + totalAppBudgets
///
///      Money held here belongs to users (`userDeposits`) or to apps
///      (`apps[x].budget`). The owner may withdraw only the excess above that
///      sum, which is what `withdrawTo` enforces.
///
///      WHY THIS DOES NOT INHERIT `BasePaymaster`. Upstream `BasePaymaster`
///      ships `withdrawTo` as `public onlyOwner`, non-virtual, withdrawing
///      against the raw EntryPoint balance — the same pot backing every deposit
///      and budget. Because it is not `virtual` it cannot be overridden, so
///      inheriting it would ship an owner function that drains user funds and
///      no way to close it. The canonical `IPaymaster`, `PackedUserOperation`
///      and `_packValidationData` are still used; only the ~50 lines of
///      forwarding are restated, and `withdrawTo` is restated safely.
///
///      TWO PHASES, TWO SETS OF RULES. `validatePaymasterUserOp` runs under
///      ERC-7562 validation rules: no `TIMESTAMP`, no `BALANCE`, no calls to
///      arbitrary contracts. Its internal half is therefore `view` — it
///      decides, it never records. `postOp` runs in the execution phase where
///      those rules do not apply, and is the only place state changes.
///
///      STAKING IS NOT OPTIONAL. `Sponsored` mode reads `apps[app]`, keyed by
///      an address from calldata rather than by `userOp.sender`. That is not
///      sender-associated storage, so bundlers will reject operations unless
///      this paymaster is staked on the EntryPoint.
contract MonarchPaymaster is IPaymaster, Ownable2Step, ReentrancyGuard {
    /// @notice How an operation gets paid for.
    /// @dev The byte at `Constants.MODE_OFFSET` of `paymasterAndData`. This is
    ///      Monarch's own enum and has nothing to do with `IPaymaster.PostOpMode`
    ///      — conflating the two is the single worst bug in the implementation
    ///      this replaces.
    enum Mode {
        Deposit, // 0x00 — the user's own prepaid balance
        Sponsored // 0x01 — a registered app's budget, authorised off-chain
    }

    /// @dev Packs into one slot: 96 + 160 = 256 bits. `budget` is read on every
    ///      sponsored validation, so a second SLOAD here is a cost paid by
    ///      every user of every app.
    ///      `signer == address(0)` means "not registered" — a separate
    ///      `bool active` would spill into a second slot to encode what the
    ///      zero address already encodes.
    struct App {
        uint96 budget;
        address signer;
    }

    /// @notice The EntryPoint this paymaster is bound to, for life.
    /// @dev Lower-case against the SCREAMING_SNAKE_CASE convention for
    ///      immutables on purpose: `entryPoint()` is the getter every ERC-4337
    ///      tool and block explorer expects on a paymaster, and upstream
    ///      `BasePaymaster` names it this. Matching the ecosystem beats matching
    ///      a style rule.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IEntryPoint public immutable entryPoint;

    /// @dev EntryPoint v0.8's unused-gas penalty parameters, mirrored because
    ///      they are `private` there. After `postOp` returns, the EntryPoint
    ///      adds `(paymasterPostOpGasLimit - postOpGasUsed) / 10` to what it
    ///      bills this paymaster, unless the unused part is under the
    ///      threshold, in which case it adds nothing.
    uint256 internal constant PENALTY_GAS_THRESHOLD = 40_000;
    uint256 internal constant UNUSED_GAS_PENALTY_PERCENT = 10;

    /// @dev A deliberate UNDER-estimate of the gas the EntryPoint measures
    ///      `postOp` using — it is nearer 11,500. Only the EntryPoint can take
    ///      that measurement, so reproducing its penalty means standing
    ///      something in for it, and the direction of the error is the whole
    ///      point of the choice.
    ///
    ///      Too low and the penalty comes out slightly too large, so the payer
    ///      is overcharged by a tenth of the gap: 150 gas here. Too high and it
    ///      comes out too small and the paymaster absorbs the difference, which
    ///      is the direction that breaks solvency. Under-estimate, always.
    uint256 internal constant POSTOP_GAS_USED_FLOOR = 10_000;

    /// @notice The smallest `paymasterPostOpGasLimit` Monarch will accept.
    /// @dev A floor is not politeness about gas estimation. It closes a way to
    ///      take gas for free, and the call is the caller's to make: in Deposit
    ///      mode the user chooses this limit, and in Sponsored mode the app
    ///      does.
    ///
    ///      There is deliberately no matching ceiling. An oversized limit is a
    ///      cost, not a danger, and `_unusedPostOpGasPenalty` bills it to the
    ///      payer who asked for it. Refusing one instead would break gas
    ///      estimation outright: bundlers simulate with a limit far above
    ///      anything real — Pimlico uses 2,000,000 — so a paymaster that
    ///      reverts on a large limit cannot be estimated, and therefore cannot
    ///      be used.
    ///
    ///      When `postOp` runs out of gas the EntryPoint does not fail the
    ///      bundle. It catches the revert, emits `PostOpRevertReason`, and
    ///      re-runs its settlement in `postOpReverted` mode — which does not
    ///      call `postOp` again. The operation's own effects are rolled back, so
    ///      the sender gains nothing; but the EntryPoint still takes the full
    ///      cost out of this paymaster's deposit, and the debit that should have
    ///      been recorded against the payer never happens. The difference comes
    ///      out of `freeBalance()`. A sender holding no ETH can repeat that for
    ///      nothing until the free balance is gone, and then every further
    ///      operation eats into the deposits and budgets the invariant promises
    ///      are there. Griefing rather than theft, but it ends in insolvency.
    ///
    ///      Measured: `postOp` settles inside a real bundle at 12,000 gas and
    ///      is starved at 11,000, on both paths. 20,000 is that requirement
    ///      with two thirds again on top. Refusing a legitimate operation is
    ///      loud and immediate; being paid nothing for one is silent.
    uint256 public constant MIN_POSTOP_GAS_LIMIT = 20_000;

    /// @notice Gas the EntryPoint spends calling `postOp` that is not included
    ///         in `actualGasCost`.
    /// @dev Charged to the payer on top of `actualGasCost` so the paymaster
    ///      does not quietly subsidise its own accounting. `actualGasCost` is
    ///      computed before `postOp` runs, so the cost of `postOp` itself is the
    ///      part nobody has paid for yet.
    ///
    ///      Do NOT read this off the `postOp` frame in a trace. That frame costs
    ///      about 11,500 gas, and the unaccounted amount is larger: the
    ///      EntryPoint finalises `actualGasCost` after `postOp` returns, so it
    ///      also includes that call's own overhead and the EntryPoint's
    ///      bookkeeping around it.
    ///
    ///      Measure it as the deficit a bundle leaves behind with no owner
    ///      buffer. That deficit is a fixed base cost plus the unused-postOp-gas
    ///      penalty, and the penalty is charged separately by
    ///      `_unusedPostOpGasPenalty` — so what this covers is the base cost
    ///      alone, measured at 13,011 gas sponsored and 12,509 deposit in
    ///      `test/integration/GasLimits.t.sol`, against 12,689 billed live by
    ///      the version before this one. 15,000 rounds that up with 15% to spare.
    ///
    ///      This was 25,000 for as long as the penalty was rolled into it,
    ///      which could only ever be a guess: the six operations on Base Sepolia each
    ///      overcharged the sponsoring app by 12,311 gas, about 9% of a repeat
    ///      operation. Under-set, the paymaster pays part of its own accounting
    ///      and solvency fails; over-set, it overcharges users and apps into the
    ///      owner's excess, which is the recoverable direction. Round up.
    uint256 public constant POSTOP_GAS_OVERHEAD = 15_000;

    mapping(address app => App) public apps;
    mapping(address user => uint256 balance) public userDeposits;

    /// @dev The two halves of the invariant's right-hand side. Kept as running
    ///      totals rather than computed, because there is no way to enumerate
    ///      a mapping and the invariant must be checkable in O(1).
    uint256 public totalUserDeposits;
    uint256 public totalAppBudgets;

    event AppRegistered(address indexed app, address indexed signer);
    event AppSignerChanged(
        address indexed app, address indexed oldSigner, address indexed newSigner
    );
    event AppFunded(address indexed app, address indexed funder, uint256 amount);
    event AppWithdrew(address indexed app, address indexed to, uint256 amount);
    event UserDeposited(address indexed user, address indexed funder, uint256 amount);
    event UserWithdrew(address indexed user, address indexed to, uint256 amount);
    event SponsorshipCharged(address indexed app, address indexed user, uint256 amount);
    event DepositCharged(address indexed user, uint256 amount);

    error NotEntryPoint(address caller);
    error EntryPointInterfaceMismatch(address entryPoint);
    error MalformedPaymasterData(uint256 length);
    error PostOpGasLimitTooLow(uint256 limit, uint256 minimum);
    error UnknownMode(uint8 mode);
    error AppNotRegistered(address app);
    error AppAlreadyRegistered(address app);
    error InsufficientAppBudget(address app, uint256 required, uint256 available);
    error InsufficientUserDeposit(address user, uint256 required, uint256 available);
    error DepositTooSmall(uint256 amount);
    error BudgetOverflow(uint256 amount);
    error WouldBreakSolvency(uint256 requested, uint256 free);

    /// @param _entryPoint Must be EntryPoint v0.8. Monarch supports exactly one;
    ///        it is a constructor argument rather than `Constants.ENTRY_POINT_V8`
    ///        only so tests can inject a local deployment.
    constructor(IEntryPoint _entryPoint) Ownable(msg.sender) {
        Validation.validateContract(address(_entryPoint));
        // Same sanity check upstream `BasePaymaster` performs: an EntryPoint
        // compiled against a different `IEntryPoint` would accept the
        // constructor and then fail every operation.
        if (!IERC165(address(_entryPoint)).supportsInterface(type(IEntryPoint).interfaceId)) {
            revert EntryPointInterfaceMismatch(address(_entryPoint));
        }
        entryPoint = _entryPoint;
    }

    // ---------------------------------------------------------------------
    // Validation — ERC-7562 rules apply. `view`: decide, never record.
    // ---------------------------------------------------------------------

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        external
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        _requireFromEntryPoint();
        return _validate(userOp, maxCost);
    }

    /// @notice Decode the mode byte and dispatch.
    /// @dev Reverts on malformed *structure* but returns a signature failure in
    ///      `validationData` on a bad signature. The distinction matters: a
    ///      revert here makes the whole bundle unmineable and gets the paymaster
    ///      throttled by bundlers, so it is reserved for operations no honest
    ///      bundler should have included in the first place.
    function _validate(PackedUserOperation calldata userOp, uint256 maxCost)
        internal
        view
        returns (bytes memory, uint256)
    {
        bytes calldata pmData = userOp.paymasterAndData;
        if (pmData.length < Constants.DEPOSIT_DATA_LENGTH) {
            revert MalformedPaymasterData(pmData.length);
        }

        // Both paymaster gas limits are adjacent uint128s, so the slice below
        // is exactly one word: verification in the high half, postOp in the
        // low half that the cast keeps.
        uint256 postOpGasLimit =
            uint128(uint256(bytes32(pmData[Constants.GAS_LIMITS_OFFSET:Constants.MODE_OFFSET])));

        // A revert, not a signature failure, and deliberately so: too little
        // postOp gas starves the charge, and an operation this paymaster cannot
        // charge for is malformed structure by the same argument as a wrong
        // length. The check depends only on the operation's own fields, so a
        // bundler simulating it sees the revert and drops the operation rather
        // than ever putting it in a bundle.
        //
        // A floor and no ceiling. Large limits are priced by
        // `_unusedPostOpGasPenalty`, not refused — see `MIN_POSTOP_GAS_LIMIT`.
        if (postOpGasLimit < MIN_POSTOP_GAS_LIMIT) {
            revert PostOpGasLimitTooLow(postOpGasLimit, MIN_POSTOP_GAS_LIMIT);
        }

        uint8 rawMode = uint8(pmData[Constants.MODE_OFFSET]);
        if (rawMode == uint8(Mode.Deposit)) {
            return _validateDeposit(pmData, userOp.sender, maxCost, postOpGasLimit);
        }
        if (rawMode == uint8(Mode.Sponsored)) {
            return _validateSponsored(userOp, maxCost, postOpGasLimit);
        }
        revert UnknownMode(rawMode);
    }

    /// @notice The user spends a balance they prepaid.
    /// @dev `userDeposits` is keyed by `userOp.sender`, so this is
    ///      sender-associated storage and is legal to read even if the
    ///      paymaster is unstaked.
    function _validateDeposit(
        bytes calldata pmData,
        address sender,
        uint256 maxCost,
        uint256 postOpGasLimit
    ) internal view returns (bytes memory, uint256) {
        // Length is checked for equality, not as a minimum: tolerating a
        // trailing tail would let two distinct byte strings authorise the same
        // operation.
        if (pmData.length != Constants.DEPOSIT_DATA_LENGTH) {
            revert MalformedPaymasterData(pmData.length);
        }

        uint256 balance = userDeposits[sender];
        if (balance < maxCost) revert InsufficientUserDeposit(sender, maxCost, balance);

        // The gas limit travels in the context because `postOp` cannot see the
        // operation, and needs it to reproduce the EntryPoint's penalty.
        return
            (abi.encode(Mode.Deposit, sender, address(0), postOpGasLimit), SIG_VALIDATION_SUCCESS);
    }

    /// @notice A registered app's budget pays, authorised by its off-chain signer.
    /// @dev `apps[app]` is NOT sender-associated storage — this is what makes
    ///      staking mandatory.
    function _validateSponsored(
        PackedUserOperation calldata userOp,
        uint256 maxCost,
        uint256 postOpGasLimit
    ) internal view returns (bytes memory, uint256) {
        bytes calldata pmData = userOp.paymasterAndData;
        if (pmData.length != Constants.SPONSORED_DATA_LENGTH) {
            revert MalformedPaymasterData(pmData.length);
        }

        // app (20) | validUntil (6) | validAfter (6) is exactly 32 bytes, so one
        // word read and two shifts replace three sub-word calldata slices and
        // their bounds checks. The field widths are asserted against this
        // layout in `test_theSponsoredFieldsFillExactlyOneWord`.
        uint256 packed = uint256(bytes32(pmData[Constants.APP_OFFSET:Constants.SIGNATURE_OFFSET]));
        // Each cast below truncates on purpose: the shift has already moved the
        // wanted field to the bottom of the word, and the cast drops the fields
        // above it. Widths are asserted in `test_theSponsoredFieldsFillExactlyOneWord`.
        // forge-lint: disable-next-line(unsafe-typecast) — keeps the top 160 bits, the app address
        address app = address(uint160(packed >> 96));
        // forge-lint: disable-next-line(unsafe-typecast) — keeps the next 48 bits, validUntil
        uint48 validUntil = uint48(packed >> 48);
        // forge-lint: disable-next-line(unsafe-typecast) — keeps the low 48 bits, validAfter
        uint48 validAfter = uint48(packed);

        App memory a = apps[app];
        if (a.signer == address(0)) revert AppNotRegistered(app);
        if (a.budget < maxCost) revert InsufficientAppBudget(app, maxCost, a.budget);

        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(getSponsorshipHash(userOp));
        // The third return is `errArg`, a diagnostic detail: the offending `s`
        // value for a malleable signature, or the length for a malformed one.
        // The decision here rests on `err` and `recovered` alone, and there is
        // nowhere to report a diagnostic to during validation anyway.
        // slither-disable-next-line unused-return
        (address recovered, ECDSA.RecoverError err,) =
            ECDSA.tryRecover(digest, pmData[Constants.SIGNATURE_OFFSET:]);

        if (err != ECDSA.RecoverError.NoError || recovered != a.signer) {
            // Empty context: the EntryPoint will not call postOp for a failed
            // validation, and returning a live context would be misleading.
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        // The time range is *returned*, never evaluated here — the EntryPoint
        // compares it against the clock. Reading `block.timestamp` in this
        // function is a banned opcode under ERC-7562, and reading it there is
        // one of the bugs this contract exists to remove.
        return (
            abi.encode(Mode.Sponsored, userOp.sender, app, postOpGasLimit),
            _packValidationData(false, validUntil, validAfter)
        );
    }

    /// @notice The digest an app's signer must sign to sponsor `userOp`.
    /// @dev Public so an app's backend can compute it with one `eth_call`
    ///      instead of reimplementing this packing and getting it subtly wrong.
    ///
    ///      Hashing `paymasterAndData` up to the signature offset covers the
    ///      paymaster address, BOTH paymaster gas limits, the mode byte, the app
    ///      and the time range in one go — and structurally cannot include the
    ///      signature itself. Enumerating those fields by hand is how the two
    ///      gas-limit fields end up unsigned and malleable by the bundler.
    function getSponsorshipHash(PackedUserOperation calldata userOp) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                keccak256(userOp.paymasterAndData[:Constants.SIGNATURE_OFFSET]),
                block.chainid, // CHAINID is permitted during validation; TIMESTAMP is not
                address(this)
            )
        );
    }

    // ---------------------------------------------------------------------
    // Execution phase — the only place state changes.
    // ---------------------------------------------------------------------

    /// @inheritdoc IPaymaster
    /// @param mode Whether the *operation* succeeded. Deliberately unused when
    ///        choosing who pays: the gas was burned either way, so a reverted
    ///        op is charged exactly like a successful one. Reading this value
    ///        as a payment scheme is the worst bug in the code this replaces.
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external override {
        _requireFromEntryPoint();
        (mode); // see @param above — deliberately not read

        (Mode payer, address user, address app, uint256 postOpGasLimit) =
            abi.decode(context, (Mode, address, address, uint256));

        // Two separate things the EntryPoint bills after this function has
        // already decided what to charge: a fixed base cost, and a penalty for
        // however much of `paymasterPostOpGasLimit` goes unused. The base cost
        // is the same every time; the penalty is whatever the payer's own gas
        // limit makes it, so it is priced per operation rather than guessed at
        // once in a constant.
        uint256 overhead = POSTOP_GAS_OVERHEAD + _unusedPostOpGasPenalty(postOpGasLimit);
        uint256 charge = actualGasCost + overhead * actualUserOpFeePerGas;

        if (payer == Mode.Deposit) {
            uint256 balance = userDeposits[user];
            // Clamped rather than checked. Reverting here makes the EntryPoint
            // re-enter with `postOpReverted`; absorbing the shortfall into the
            // owner's excess is strictly cheaper.
            uint256 debit = charge > balance ? balance : charge;
            userDeposits[user] = balance - debit;
            totalUserDeposits -= debit;
            emit DepositCharged(user, debit);
        } else {
            App storage a = apps[app];
            uint256 balance = a.budget;
            uint256 debit = charge > balance ? balance : charge;
            // forge-lint: disable-next-line(unsafe-typecast) — `balance` is a uint96 and `debit <= balance`
            a.budget = uint96(balance - debit);
            totalAppBudgets -= debit;
            emit SponsorshipCharged(app, user, debit);
        }
    }

    /// @notice What the EntryPoint will add for unused postOp gas, reproduced.
    /// @dev Mirrors `EntryPoint._getUnusedGasPenalty` with
    ///      `POSTOP_GAS_USED_FLOOR` standing in for a measurement only the
    ///      EntryPoint can take. Both differences from the original round
    ///      against the payer and in favour of solvency: the amount comes out
    ///      slightly high, and the waiver cuts off slightly early.
    function _unusedPostOpGasPenalty(uint256 postOpGasLimit) internal pure returns (uint256) {
        unchecked {
            if (postOpGasLimit <= POSTOP_GAS_USED_FLOOR + PENALTY_GAS_THRESHOLD) return 0;
            return ((postOpGasLimit - POSTOP_GAS_USED_FLOOR) * UNUSED_GAS_PENALTY_PERCENT) / 100;
        }
    }

    // ---------------------------------------------------------------------
    // Apps
    // ---------------------------------------------------------------------

    /// @notice Register an app so it can sponsor operations.
    /// @dev Owner-gated. Permissionless registration would let anyone create
    ///      entries in a mapping that a staked paymaster reads during
    ///      validation, which is a reputation risk to the paymaster itself.
    function registerApp(address app, address signer) external onlyOwner {
        Validation.validateAddress(app);
        Validation.validateAddress(signer);
        if (apps[app].signer != address(0)) revert AppAlreadyRegistered(app);
        apps[app].signer = signer;
        emit AppRegistered(app, signer);
    }

    /// @notice Rotate an app's signing key.
    /// @dev The app rotates its own key; the owner cannot. An owner able to
    ///      set the signer could sponsor from any app's budget at will.
    function setAppSigner(address newSigner) external {
        Validation.validateAddress(newSigner);
        App storage a = apps[msg.sender];
        address old = a.signer;
        if (old == address(0)) revert AppNotRegistered(msg.sender);
        a.signer = newSigner;
        emit AppSignerChanged(msg.sender, old, newSigner);
    }

    /// @notice Top up an app's sponsorship budget.
    /// @dev Permissionless — anyone may fund any registered app. Funding
    ///      someone else's budget is a gift, never an attack.
    function fundApp(address app) external payable {
        App storage a = apps[app];
        if (a.signer == address(0)) revert AppNotRegistered(app);
        uint256 newBudget = uint256(a.budget) + msg.value;
        if (newBudget > type(uint96).max) revert BudgetOverflow(newBudget);

        // forge-lint: disable-next-line(unsafe-typecast) — bounded on the line above
        a.budget = uint96(newBudget);
        totalAppBudgets += msg.value;
        emit AppFunded(app, msg.sender, msg.value);
        // Forwarded immediately: value sitting on this contract rather than on
        // the EntryPoint cannot pay for anything. State and the event both
        // precede it, so a callback would find this contract already settled.
        // forge-lint: disable-next-line(reentrancy-no-eth) — callee is the immutable EntryPoint
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Withdraw an app's unspent budget. Only the app itself may call.
    function withdrawAppBudget(address payable to, uint256 amount) external nonReentrant {
        Validation.validateAddress(to);
        App storage a = apps[msg.sender];
        if (a.signer == address(0)) revert AppNotRegistered(msg.sender);
        uint256 balance = a.budget;
        if (amount > balance) revert InsufficientAppBudget(msg.sender, amount, balance);

        // forge-lint: disable-next-line(unsafe-typecast) — `balance` is a uint96 and `amount <= balance`
        a.budget = uint96(balance - amount);
        totalAppBudgets -= amount;
        emit AppWithdrew(msg.sender, to, amount);
        // Guarded by `nonReentrant`, and every balance is written above this
        // line. A recipient that calls back reaches only `depositFor` or
        // `fundApp`, which add funds — the accounting they would see is already
        // settled.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        entryPoint.withdrawTo(to, amount);
    }

    // ---------------------------------------------------------------------
    // User deposits
    // ---------------------------------------------------------------------

    /// @notice Prepay gas for `user`.
    /// @dev Permissionless, like `fundApp`, and for the same reason.
    function depositFor(address user) external payable {
        Validation.validateAddress(user);
        if (msg.value < Constants.MIN_DEPOSIT) revert DepositTooSmall(msg.value);

        userDeposits[user] += msg.value;
        totalUserDeposits += msg.value;
        emit UserDeposited(user, msg.sender, msg.value);
        // forge-lint: disable-next-line(reentrancy-no-eth) — callee is the immutable EntryPoint
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Withdraw your own prepaid balance to an address you choose.
    /// @dev Note what this is NOT: the implementation this replaces took a
    ///      `user` argument, debited that user, and paid `msg.sender` — so any
    ///      admin could drain any user. Here the debited account is always
    ///      `msg.sender`.
    function withdrawUserDeposit(address payable to, uint256 amount) external nonReentrant {
        Validation.validateAddress(to);
        uint256 balance = userDeposits[msg.sender];
        if (amount > balance) revert InsufficientUserDeposit(msg.sender, amount, balance);

        userDeposits[msg.sender] = balance - amount;
        totalUserDeposits -= amount;
        emit UserWithdrew(msg.sender, to, amount);
        // Guarded by `nonReentrant`, and every balance is written above this
        // line. A recipient that calls back reaches only `depositFor` or
        // `fundApp`, which add funds — the accounting they would see is already
        // settled.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        entryPoint.withdrawTo(to, amount);
    }

    // ---------------------------------------------------------------------
    // Owner and EntryPoint plumbing
    // ---------------------------------------------------------------------

    /// @notice Withdraw the owner's own funds — never a user's or an app's.
    /// @dev This solvency check is the reason this contract does not inherit
    ///      `BasePaymaster`: its `withdrawTo` is non-virtual and withdraws
    ///      against the raw EntryPoint balance, which is the same pot backing
    ///      every deposit and budget.
    function withdrawTo(address payable withdrawAddress, uint256 amount)
        external
        nonReentrant
        onlyOwner
    {
        Validation.validateAddress(withdrawAddress);
        uint256 free = freeBalance();
        if (amount > free) revert WouldBreakSolvency(amount, free);
        // Guarded by `nonReentrant`, and every balance is written above this
        // line. A recipient that calls back reaches only `depositFor` or
        // `fundApp`, which add funds — the accounting they would see is already
        // settled.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /// @notice EntryPoint balance not spoken for by a user deposit or app budget.
    /// @dev The invariant, restated as a number. Saturates at zero rather than
    ///      underflowing so that a monitoring caller sees `0` on an
    ///      undercollateralised paymaster instead of a revert.
    function freeBalance() public view returns (uint256) {
        uint256 reserved = totalUserDeposits + totalAppBudgets;
        uint256 balance = entryPoint.balanceOf(address(this));
        return balance > reserved ? balance - reserved : 0;
    }

    /// @notice This paymaster's deposit on the EntryPoint, including funds
    ///         reserved for users and apps.
    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /// @notice Add to the paymaster's own deposit without crediting anyone.
    /// @dev This is how the owner funds the buffer that absorbs the overdraw
    ///      case in `postOp`. It raises `freeBalance()`, never a user's or an
    ///      app's balance.
    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Stake on the EntryPoint. Not optional — see the contract notice.
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /// @notice Begin the unstake delay. The paymaster cannot serve sponsored
    ///         operations once unlocked, until it stakes again.
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /// @notice Withdraw the stake once the delay has elapsed.
    /// @dev The stake is a separate pot from the deposit, so this cannot touch
    ///      user or app funds and needs no solvency check.
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        Validation.validateAddress(withdrawAddress);
        entryPoint.withdrawStake(withdrawAddress);
    }

    function _requireFromEntryPoint() internal view {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint(msg.sender);
    }
}
