// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {SimpleAccountFactory} from "account-abstraction/accounts/SimpleAccountFactory.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";
import {Guestbook} from "../helpers/Adversary.sol";
import {MeasuringPaymaster} from "../helpers/MeasuringPaymaster.sol";

/// @notice What `POSTOP_GAS_OVERHEAD` has to cover, measured rather than argued.
/// @dev This file exists because the constant was calibrated twice and got two
///      different answers. Locally, the deficit a bundle leaves behind put the
///      true overhead near 19,600. On Base Sepolia, every one of the first six
///      live operations came in near 12,700. Both measurements were correct;
///      they were measuring different quantities.
///
///      The EntryPoint bills the paymaster for two things after `postOp` has
///      already chosen what to charge:
///
///        1. `preGas - gasleft()` across `_postExecution` — the `postOp` call
///           itself plus the EntryPoint's own bookkeeping around it. Call this
///           the base cost. It does not depend on the gas limits.
///        2. `_getUnusedGasPenalty(postOpGasUsed, paymasterPostOpGasLimit)` — a
///           tenth of the unused part of the postOp gas limit, charged only
///           once the unused part exceeds `PENALTY_GAS_THRESHOLD` (40,000).
///
///      The local tests asked for 80,000 of postOp gas and used ~11,500 of it,
///      so they paid a penalty of roughly (80,000 - 11,500) / 10 = 6,850. The
///      live sponsor route asks for exactly 40,000, and because
///      `40,000 <= used + 40,000` holds for any `used`, the live penalty is
///      exactly zero. 19,600 - 6,850 is 12,750. That is the whole discrepancy.
///
///      The conclusion drives the design: the penalty is unbounded in the gas
///      limit, so no fixed constant can cover it. Monarch therefore charges it
///      rather than absorbing it — `_unusedPostOpGasPenalty` reproduces the
///      EntryPoint's formula and bills the payer who chose the limit — and
///      `POSTOP_GAS_OVERHEAD` covers only the base cost.
///
///      Capping the limit instead was tried first and is wrong. Bundlers
///      simulate with a limit far above anything real (Pimlico uses 2,000,000),
///      so a paymaster that reverts on a large limit cannot be gas-estimated.
///      That version reached Base Sepolia and the demo could not send a single
///      operation through it.
contract GasLimitsTest is Fixture {
    /// @dev Mirrors `EntryPoint.PENALTY_GAS_THRESHOLD`, which is `private`.
    uint256 internal constant PENALTY_GAS_THRESHOLD = 40_000;
    /// @dev Mirrors `EntryPoint.UNUSED_GAS_PENALTY_PERCENT`.
    uint256 internal constant UNUSED_GAS_PENALTY_PERCENT = 10;

    bytes32 internal constant USER_OPERATION_EVENT =
        keccak256("UserOperationEvent(bytes32,address,address,uint256,bool,uint256,uint256)");
    bytes32 internal constant SPONSORSHIP_CHARGED =
        keccak256("SponsorshipCharged(address,address,uint256)");
    bytes32 internal constant DEPOSIT_CHARGED = keccak256("DepositCharged(address,uint256)");
    bytes32 internal constant MEASURED = keccak256("Measured(uint256,uint256)");

    /// @dev The two limits `demo/app/api/sponsor/route.ts` signs into every
    ///      sponsorship. Restated here so a contract change that outgrows them
    ///      fails in CI rather than on someone's phone.
    ///
    ///      The postOp limit is chosen to sit above `MIN_POSTOP_GAS_LIMIT` and
    ///      at or below the EntryPoint's penalty threshold, so honest traffic
    ///      pays no penalty at all.
    uint128 internal constant ROUTE_PM_VERIFICATION_GAS = 35_000;
    uint128 internal constant ROUTE_PM_POSTOP_GAS = 40_000;

    SimpleAccountFactory internal factory;
    Guestbook internal guestbook;
    MeasuringPaymaster internal measurer;

    address internal accountOwner;
    uint256 internal accountOwnerKey;

    address payable internal bundler = payable(makeAddr("bundler"));

    function setUp() public override {
        super.setUp();
        (accountOwner, accountOwnerKey) = makeAddrAndKey("accountOwner");

        factory = new SimpleAccountFactory(IEntryPoint(address(entryPoint)));
        guestbook = new Guestbook();

        measurer = new MeasuringPaymaster(IEntryPoint(address(entryPoint)));
        measurer.deposit{value: 10 ether}();

        _fundApp(app, 50 ether);

        // A buffer big enough that nothing here is ever clamped: a clamped
        // charge would silently change what the measurement means.
        vm.prank(owner);
        paymaster.deposit{value: 10 ether}();

        vm.prank(owner);
        paymaster.addStake{value: 1 ether}(1 days);

        vm.deal(address(this), 100 ether);
    }

    // ------------------------------------------------------- the reconciliation

    /// @notice The overhead the EntryPoint bills after `postOp` grows by one gas
    ///         for every ten gas of `paymasterPostOpGasLimit` left unused.
    /// @dev Measured on `MeasuringPaymaster`, because Monarch now refuses the
    ///      limits that make the penalty visible.
    ///
    ///      The base cost is identical between two runs of identical code, so it
    ///      cancels and the difference is the penalty difference alone. Nothing
    ///      here needs to know what `postOp` costs, and nothing here assumes it.
    ///
    ///      This is the mechanism the whole phase turns on: the penalty has no
    ///      ceiling, so no constant can cover it, and a cap is the only defence.
    function test_theOverheadGrowsByATenthOfTheUnusedPostOpGasLimit() public {
        uint256 at80k = _measureUncapped(80_000, 1);
        uint256 at200k = _measureUncapped(200_000, 2);

        emit log_named_uint("unaccounted at  80,000", at80k);
        emit log_named_uint("unaccounted at 200,000", at200k);

        assertEq(
            at200k - at80k,
            (200_000 - 80_000) / UNUSED_GAS_PENALTY_PERCENT,
            "ten gas of unused postOp limit costs the paymaster one gas"
        );
    }

    /// @notice At or below the threshold the penalty is gone, and the overhead
    ///         stops depending on the gas limit at all.
    /// @dev The other half of the claim above, and the half the sponsor route's
    ///      choice of 40,000 relies on.
    function test_belowTheThresholdTheOverheadIsIndependentOfTheGasLimit() public {
        uint256 at40k = _measureUncapped(40_000, 3);
        uint256 at10k = _measureUncapped(10_000, 4);

        emit log_named_uint("unaccounted at 40,000", at40k);
        emit log_named_uint("unaccounted at 10,000", at10k);

        assertEq(at40k, at10k, "no penalty applies on either side of the gap");
    }

    // ------------------------------------------- what the constant has to cover

    /// @notice The base overhead, against the figure Base Sepolia billed.
    /// @dev Base Sepolia billed the sponsoring app 12,311 gas more than the
    ///      EntryPoint took on every one of the first six operations, against a
    ///      constant of 25,000 — so the live base overhead was 12,689 gas. The
    ///      sponsor route sends a 40,000 postOp gas limit, which attracts no
    ///      penalty, so that was the base cost alone.
    ///
    ///      It is a few hundred gas higher here because `postOp` now carries the
    ///      postOp gas limit through the context and prices the penalty, which
    ///      is a word more to encode, copy and decode. That is the cost of not
    ///      guessing.
    ///
    ///      The build guide's 19,613 was the same number plus the penalty its
    ///      tests paid on an 80,000 limit. Neither figure was wrong.
    function test_theBaseOverheadIsNearWhatBaseSepoliaBilled() public {
        uint256 sponsored = _measureSponsored(ROUTE_PM_POSTOP_GAS, 0);
        uint256 deposited = _measureDeposit(ROUTE_PM_POSTOP_GAS);

        emit log_named_uint("sponsored overhead", sponsored);
        emit log_named_uint("deposit overhead  ", deposited);

        assertApproxEqAbs(
            sponsored, 12_689, 500, "within a few hundred gas of the 12,689 billed live"
        );
        assertLt(sponsored, paymaster.POSTOP_GAS_OVERHEAD(), "and the constant still covers it");
        assertLt(deposited, sponsored, "the deposit path writes one slot fewer");
    }

    /// @notice The constant covers the worst case the contract will accept,
    ///         on both paths, with room to spare.
    function test_theConstantCoversTheSponsoredPathAtTheRouteLimit() public {
        uint256 unaccounted = _measureSponsored(ROUTE_PM_POSTOP_GAS, 0);
        assertLt(
            unaccounted,
            paymaster.POSTOP_GAS_OVERHEAD(),
            "sponsored: the charge covers what the EntryPoint takes"
        );
    }

    function test_theConstantCoversTheDepositPathAtTheRouteLimit() public {
        uint256 unaccounted = _measureDeposit(ROUTE_PM_POSTOP_GAS);
        assertLt(
            unaccounted,
            paymaster.POSTOP_GAS_OVERHEAD(),
            "deposit: the charge covers what the EntryPoint takes"
        );
    }

    /// @notice Monarch's copy of the penalty formula never charges less than
    ///         the EntryPoint does.
    /// @dev The copy stands `POSTOP_GAS_USED_FLOOR` in for a measurement only
    ///      the EntryPoint can take, so the two can differ. What matters is the
    ///      direction: charging more than the EntryPoint takes is an overcharge
    ///      into the owner's excess, charging less is insolvency. Swept across
    ///      the range a bundler might plausibly ask for.
    function testFuzz_theChargedPenaltyIsNeverLessThanTheEntryPointsPenalty(uint128 limit)
        public
        view
    {
        limit = uint128(bound(limit, paymaster.MIN_POSTOP_GAS_LIMIT(), 5_000_000));
        // The EntryPoint measures ~11,500 for a real `postOp`; anything less
        // makes its penalty larger, so sweep the pessimistic end too.
        for (uint256 used = 10_000; used <= 13_000; used += 500) {
            assertGe(
                _monarchPenalty(limit),
                _unusedGasPenalty(used, limit),
                "Monarch never undercharges the EntryPoint's penalty"
            );
        }
    }

    /// @notice An owner who never funds a buffer still ends the bundle solvent.
    /// @dev This is the measurement the build guide used, restated as an
    ///      assertion. With no free balance there is nothing to absorb an
    ///      under-set constant, so a deficit shows up directly as insolvency.
    function test_withNoOwnerBufferTheBundleStillLeavesThePaymasterSolvent() public {
        // Read first: `freeBalance()` is itself a call, and would otherwise
        // consume the prank meant for `withdrawTo`.
        uint256 free = paymaster.freeBalance();
        vm.prank(owner);
        paymaster.withdrawTo(payable(owner), free);
        assertEq(paymaster.freeBalance(), 0, "precondition: no buffer to hide a deficit");

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredOpFor(0, ROUTE_PM_POSTOP_GAS);
        entryPoint.handleOps(ops, bundler);

        _assertSolvent("no deficit at the postOp gas limit the route sends");
    }

    /// @notice And no deficit at the limit a bundler estimates with either,
    ///         which is where a fixed constant would have failed.
    /// @dev 2,000,000 of postOp gas carries a penalty of roughly 199,000 — more
    ///      than ten times `POSTOP_GAS_OVERHEAD`. With no owner buffer to hide
    ///      in, absorbing it instead of charging it would show up here as
    ///      insolvency on the first operation.
    function test_withNoOwnerBufferAnOversizedGasLimitIsStillSolvent() public {
        uint256 free = paymaster.freeBalance();
        vm.prank(owner);
        paymaster.withdrawTo(payable(owner), free);
        assertEq(paymaster.freeBalance(), 0, "precondition: no buffer to hide a deficit");

        (uint96 before,) = paymaster.apps(app);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredOpFor(1, 2_000_000);
        entryPoint.handleOps(ops, bundler);

        (uint96 afterBudget,) = paymaster.apps(app);
        assertGt(before - afterBudget, 199_000 * uint256(1 gwei), "the penalty reached the app");
        _assertSolvent("no deficit at a bundler's estimation gas limit");
    }

    // ------------------------------------------- the free-gas hole the floor shuts

    /// @notice A `postOp` that fails costs the paymaster the whole operation
    ///         and charges nobody for it.
    /// @dev The premise behind `MIN_POSTOP_GAS_LIMIT`, shown rather than
    ///      asserted from the EntryPoint's source. The EntryPoint catches the
    ///      failure, emits `PostOpRevertReason` and settles in `postOpReverted`
    ///      mode, which does not call `postOp` again — so a paymaster that
    ///      records its charges there records nothing, while its deposit is
    ///      debited for every gas burned.
    ///
    ///      Note what this is and is not. The operation's own effects are rolled
    ///      back with `innerHandleOp`, so the sender gains nothing: this buys
    ///      griefing, not free execution. That is bad enough. The bill lands on
    ///      `freeBalance()`, the sender pays nothing, and it can be repeated
    ///      until the free balance is gone — at which point the EntryPoint keeps
    ///      deducting and `balanceOf(this)` falls below the deposits and budgets
    ///      it is supposed to back. The solvency invariant is exactly what
    ///      breaks.
    ///
    ///      Running out of gas and reverting arrive at the EntryPoint the same
    ///      way, and the gas limit that decides which happens is chosen by the
    ///      caller: the user in Deposit mode, the app in Sponsored mode.
    function test_aFailedPostOpCostsThePaymasterAndChargesNobody() public {
        measurer.setFailInPostOp(true);
        uint256 depositBefore = entryPoint.balanceOf(address(measurer));

        (, uint256 key) = makeAddrAndKey("starved");
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount who = factory.createAccount(vm.addr(key), 777);

        PackedUserOperation memory op = _guestbookOp(who, "free gas");
        op.paymasterAndData = abi.encodePacked(
            address(measurer), UserOpBuilder.DEFAULT_PM_VERIFICATION_GAS, ROUTE_PM_POSTOP_GAS
        );
        op.signature = _signAccount(key, op);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, bundler);

        assertEq(guestbook.entries(address(who)), "", "the operation's own effects are rolled back");
        assertLt(
            entryPoint.balanceOf(address(measurer)),
            depositBefore,
            "but the paymaster paid for the gas anyway, having recorded no charge"
        );
    }

    /// @notice Monarch refuses the operation that would put it in that position.
    /// @dev The floor turns a silent, repeatable free ride into a revert during
    ///      validation, which a bundler sees when it simulates.
    function test_anOperationThatWouldStarvePostOpIsRefused() public {
        uint128 starving = uint128(paymaster.MIN_POSTOP_GAS_LIMIT() - 1);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredOpFor(42, starving);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                uint256(0),
                "AA33 reverted",
                abi.encodeWithSelector(
                    MonarchPaymaster.PostOpGasLimitTooLow.selector,
                    uint256(starving),
                    paymaster.MIN_POSTOP_GAS_LIMIT()
                )
            )
        );
        entryPoint.handleOps(ops, bundler);
    }

    /// @notice And the payer really is debited at the floor, so the floor is
    ///         not merely above the cliff by luck.
    function test_atTheFloorThePayerIsStillCharged() public {
        (uint96 before,) = paymaster.apps(app);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredOpFor(43, uint128(paymaster.MIN_POSTOP_GAS_LIMIT()));
        entryPoint.handleOps(ops, bundler);

        (uint96 afterBudget,) = paymaster.apps(app);
        assertLt(afterBudget, before, "postOp settled inside the floor");
    }

    // ----------------------------------- the limits the reference route sends

    /// @notice The verification limit the sponsor route signs is enough for a
    ///         real bundle, including the operation that deploys the account.
    /// @dev Worth its own test because the EntryPoint does not measure this
    ///      against the `validatePaymasterUserOp` frame. `AA36` compares
    ///      `preGas - gasleft()` across the deposit decrement, the re-encoding
    ///      of the whole userOp, the call and the returned context — measured at
    ///      22,750 gas, nearly twice the 12,131 the frame itself costs. Reading
    ///      the frame cost off a gas report and trimming to it would fail every
    ///      operation with `AA36 over paymasterVerificationGasLimit`.
    function test_theRouteVerificationGasLimitCoversADeployingOperation() public {
        (, uint256 key) = makeAddrAndKey("routeVerification");
        address who = factory.getAddress(vm.addr(key), 4_242);

        PackedUserOperation memory op = _guestbookOp(SimpleAccount(payable(who)), "route");
        op.initCode = abi.encodePacked(
            address(factory),
            abi.encodeCall(SimpleAccountFactory.createAccount, (vm.addr(key), 4_242))
        );
        op.accountGasLimits = UserOpBuilder.packLimits(600_000, 200_000);

        bytes memory prefix = abi.encodePacked(
            address(paymaster),
            ROUTE_PM_VERIFICATION_GAS,
            ROUTE_PM_POSTOP_GAS,
            uint8(1),
            app,
            uint48(0),
            uint48(0)
        );
        op.paymasterAndData = prefix;
        op.paymasterAndData =
            UserOpBuilder.withSignature(prefix, _signSponsorship(op, appSignerKey));
        op.signature = _signAccount(key, op);

        (uint96 before,) = paymaster.apps(app);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, bundler);

        assertEq(guestbook.entries(who), "route", "the operation ran and the account was deployed");
        (uint96 afterBudget,) = paymaster.apps(app);
        assertLt(afterBudget, before, "and the app was charged for it");
        _assertSolvent("solvency at the limits the route actually sends");
    }

    /// @notice The route's postOp limit is inside the band the contract accepts.
    /// @dev An off-by-one between the two would take the whole demo down.
    function test_theRouteGasLimitsAreInsideTheBand() public view {
        assertGe(ROUTE_PM_POSTOP_GAS, paymaster.MIN_POSTOP_GAS_LIMIT(), "route is above the floor");
        assertEq(_monarchPenalty(ROUTE_PM_POSTOP_GAS), 0, "and honest traffic pays no penalty");
    }

    // --------------------------------------------------------------- measuring

    /// @dev Runs one sponsored op and returns the gas the EntryPoint billed
    ///      that `postOp` did not know about, plus the postOp gas the EntryPoint
    ///      itself measured.
    ///
    ///      `amount / gasPrice` is the gas the paymaster charged, which is
    ///      `gasBeforePostOp + POSTOP_GAS_OVERHEAD`. `actualGasUsed` from the
    ///      EntryPoint's own event is `gasBeforePostOp + base + penalty`. The
    ///      difference, with the constant added back, is what the constant has
    ///      to cover.
    function _measureSponsored(uint128 postOpGasLimit, uint256 seed)
        internal
        returns (uint256 unaccounted)
    {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredOpFor(seed, postOpGasLimit);

        vm.recordLogs();
        entryPoint.handleOps(ops, bundler);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 actualGasUsed, uint256 gasPrice) = _readUserOperationEvent(logs);
        uint256 charged = _readAmount(logs, SPONSORSHIP_CHARGED);

        unaccounted = actualGasUsed + paymaster.POSTOP_GAS_OVERHEAD() - charged / gasPrice;
    }

    /// @dev The same measurement on `MeasuringPaymaster`, which has no cap, so
    ///      limits above the threshold can still be exercised. Here the
    ///      EntryPoint's own `actualGasCost` argument stands in for the charge.
    function _measureUncapped(uint128 postOpGasLimit, uint256 seed)
        internal
        returns (uint256 unaccounted)
    {
        (, uint256 key) = makeAddrAndKey(string.concat("uncapped", vm.toString(seed)));
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount who = factory.createAccount(vm.addr(key), 100 + seed);

        PackedUserOperation memory op = _guestbookOp(who, "measure");
        op.paymasterAndData = abi.encodePacked(
            address(measurer), UserOpBuilder.DEFAULT_PM_VERIFICATION_GAS, postOpGasLimit
        );
        op.signature = _signAccount(key, op);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.recordLogs();
        entryPoint.handleOps(ops, bundler);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 actualGasUsed,) = _readUserOperationEvent(logs);
        (uint256 costAtPostOp, uint256 feePerGas) = _readMeasured(logs);

        unaccounted = actualGasUsed - costAtPostOp / feePerGas;
    }

    function _measureDeposit(uint128 postOpGasLimit) internal returns (uint256 unaccounted) {
        (address depositOwner, uint256 depositOwnerKey) = makeAddrAndKey("depositOwner");
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount who = factory.createAccount(depositOwner, 9_000);

        vm.prank(alice);
        paymaster.depositFor{value: 5 ether}(address(who));

        PackedUserOperation memory op = _guestbookOp(who, "deposit");
        op.paymasterAndData = UserOpBuilder.depositData(address(paymaster), postOpGasLimit);
        op.signature = _signAccount(depositOwnerKey, op);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.recordLogs();
        entryPoint.handleOps(ops, bundler);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 actualGasUsed, uint256 gasPrice) = _readUserOperationEvent(logs);
        uint256 charged = _readAmount(logs, DEPOSIT_CHARGED);
        unaccounted = actualGasUsed + paymaster.POSTOP_GAS_OVERHEAD() - charged / gasPrice;
    }

    /// @dev Monarch's `_unusedPostOpGasPenalty`, restated. `internal` there, so
    ///      it cannot be called; restating it here is what makes the comparison
    ///      against the EntryPoint's own formula possible.
    function _monarchPenalty(uint256 postOpGasLimit) internal pure returns (uint256) {
        uint256 floor = 10_000; // POSTOP_GAS_USED_FLOOR
        if (postOpGasLimit <= floor + PENALTY_GAS_THRESHOLD) return 0;
        return ((postOpGasLimit - floor) * UNUSED_GAS_PENALTY_PERCENT) / 100;
    }

    function _unusedGasPenalty(uint256 gasUsed, uint256 gasLimit) internal pure returns (uint256) {
        if (gasLimit <= gasUsed + PENALTY_GAS_THRESHOLD) return 0;
        return ((gasLimit - gasUsed) * UNUSED_GAS_PENALTY_PERCENT) / 100;
    }

    function _readUserOperationEvent(Vm.Log[] memory logs)
        internal
        pure
        returns (uint256 actualGasUsed, uint256 gasPrice)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != USER_OPERATION_EVENT) continue;
            (,, uint256 actualGasCost, uint256 used) =
                abi.decode(logs[i].data, (uint256, bool, uint256, uint256));
            // Recovering the price from the EntryPoint's own two numbers keeps
            // this independent of how the builder packs `gasFees`.
            return (used, actualGasCost / used);
        }
        revert("no UserOperationEvent");
    }

    function _readMeasured(Vm.Log[] memory logs)
        internal
        pure
        returns (uint256 actualGasCost, uint256 feePerGas)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != MEASURED) continue;
            return abi.decode(logs[i].data, (uint256, uint256));
        }
        revert("no Measured event");
    }

    function _readAmount(Vm.Log[] memory logs, bytes32 topic)
        internal
        pure
        returns (uint256 amount)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) {
                return abi.decode(logs[i].data, (uint256));
            }
        }
        revert("no charge event");
    }

    // --------------------------------------------------------------- op building

    function _sponsoredOpFor(uint256 seed, uint128 postOpGasLimit)
        internal
        returns (PackedUserOperation memory op)
    {
        (, uint256 key) = makeAddrAndKey(string.concat("measured", vm.toString(seed)));
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount who = factory.createAccount(vm.addr(key), seed);

        op = _guestbookOp(who, "measure");
        bytes memory prefix =
            UserOpBuilder.sponsoredPrefix(address(paymaster), app, 0, 0, postOpGasLimit);
        op.paymasterAndData = prefix;
        op.paymasterAndData =
            UserOpBuilder.withSignature(prefix, _signSponsorship(op, appSignerKey));
        op.signature = _signAccount(key, op);
    }

    function _guestbookOp(SimpleAccount who, string memory message)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        bytes memory inner = abi.encodeCall(
            BaseAccount.execute, (address(guestbook), 0, abi.encodeCall(Guestbook.sign, (message)))
        );
        op = UserOpBuilder.base(address(who), entryPoint.getNonce(address(who), 0), inner);
    }

    function _signAccount(uint256 key, PackedUserOperation memory op)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, entryPoint.getUserOpHash(op));
        return abi.encodePacked(r, s, v);
    }
}
