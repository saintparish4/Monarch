// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {SimpleAccountFactory} from "account-abstraction/accounts/SimpleAccountFactory.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";
import {Guestbook, RevertingTarget} from "../helpers/Adversary.sol";

/// @notice The paymaster driven by real EntryPoint v0.8 bytecode through
///         `handleOps`, which is the only place its understanding of the
///         interface is actually tested.
/// @dev No fork, no RPC, no mock. What is still absent is the bundler's
///      off-chain ERC-7562 tracer, which is why this is integration and not
///      end to end.
contract BundleTest is Fixture {
    SimpleAccountFactory internal factory;
    Guestbook internal guestbook;
    RevertingTarget internal reverter;

    address internal accountOwner;
    uint256 internal accountOwnerKey;
    SimpleAccount internal account;

    address payable internal bundler = payable(makeAddr("bundler"));

    function setUp() public override {
        super.setUp();
        (accountOwner, accountOwnerKey) = makeAddrAndKey("accountOwner");

        factory = new SimpleAccountFactory(IEntryPoint(address(entryPoint)));
        guestbook = new Guestbook();
        reverter = new RevertingTarget();

        // v0.8 gates `createAccount` behind the EntryPoint's SenderCreator, so
        // deploying one in a test means impersonating it. Doing it here keeps
        // the tests about the paymaster rather than about account deployment.
        vm.prank(address(entryPoint.senderCreator()));
        account = factory.createAccount(accountOwner, 0);

        _fundApp(app, 5 ether);

        // Staking is not decoration: sponsored mode reads storage that is not
        // sender-associated, so a real bundler rejects these ops unstaked.
        vm.prank(owner);
        paymaster.addStake{value: 1 ether}(1 days);
    }

    // ------------------------------------------------------- the headline claim

    function test_sponsoredUserWithZeroEth_transacts() public {
        assertEq(address(account).balance, 0, "precondition: the user has nothing");

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredGuestbookOp("hello from a user with no ETH");
        entryPoint.handleOps(ops, bundler);

        assertEq(
            guestbook.entries(address(account)), "hello from a user with no ETH", "the call ran"
        );
        assertEq(address(account).balance, 0, "the user still has nothing");
        assertGt(bundler.balance, 0, "the bundler was paid");

        (uint96 budget,) = paymaster.apps(app);
        assertLt(budget, 5 ether, "the app paid for it");
        _assertSolvent("solvency after a real bundle");
    }

    function test_depositUserWithZeroEth_transacts() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(address(account));
        assertEq(address(account).balance, 0, "precondition: the user has nothing");

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _depositGuestbookOp("paid from my own prepaid balance");
        entryPoint.handleOps(ops, bundler);

        assertEq(
            guestbook.entries(address(account)), "paid from my own prepaid balance", "the call ran"
        );
        assertEq(address(account).balance, 0, "the user still holds no gas token");
        assertLt(paymaster.userDeposits(address(account)), 1 ether, "the prepaid balance paid");
        (uint96 budget,) = paymaster.apps(app);
        assertEq(budget, 5 ether, "no app was charged");
        _assertSolvent("solvency after a deposit-mode bundle");
    }

    // ------------------------------------------ the range the EntryPoint enforces

    function test_expiredSponsorship_isRejectedByEntryPoint() public {
        vm.warp(10_000);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredGuestbookOpWindow("too late", 9_000, 0);

        // The paymaster accepts and hands the range back; the EntryPoint is what
        // compares it against the clock. A unit test cannot reach this.
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, uint256(0), "AA32 paymaster expired or not due"
            )
        );
        entryPoint.handleOps(ops, bundler);
    }

    function test_notYetValidSponsorship_isRejected() public {
        vm.warp(10_000);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredGuestbookOpWindow("too early", 0, 20_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, uint256(0), "AA32 paymaster expired or not due"
            )
        );
        entryPoint.handleOps(ops, bundler);
    }

    // ------------------------------------------------- the case found by reading

    /// @notice Several operations from the same payer in one bundle.
    /// @dev The case I found by reading and could not settle without running.
    ///      Every op in a bundle validates against the same pre-bundle budget,
    ///      then each charges in `postOp`, so the payer can be debited more than
    ///      it had. The clamp keeps the arithmetic safe; what I did not know was
    ///      whether the shortfall breaks solvency.
    ///
    ///      It cannot, and the reason is the EntryPoint rather than anything in
    ///      this contract. The EntryPoint deducts a prefund of `maxCost` per op
    ///      from the paymaster's whole deposit, so a bundle of N ops only runs
    ///      if the deposit covers N * maxCost. Validation requires an app's
    ///      budget to be at least `maxCost`, so the free buffer must already be
    ///      at least (N-1) * maxCost — which is the largest shortfall the clamp
    ///      can ever produce. The buffer is structurally big enough to absorb
    ///      it before the bundle is allowed to start.
    ///
    ///      What the clamp costs is visible in the buffer: the app's ledger
    ///      stops at zero while the EntryPoint keeps taking real gas, so the
    ///      difference is drawn from the owner's excess. The owner subsidises.
    ///      Users and apps never do.
    function test_manyOpsFromOnePayerOverdrawIntoTheOwnerBuffer() public {
        // A budget just over one op's maxCost, so every op in the bundle passes
        // validation against the same stale value.
        vm.prank(app);
        paymaster.withdrawAppBudget(payable(app), 5 ether - 0.0008 ether);
        (uint96 startBudget,) = paymaster.apps(app);

        // The buffer that makes the bundle fundable at all.
        vm.prank(owner);
        paymaster.deposit{value: 1 ether}();
        uint256 freeBefore = paymaster.freeBalance();

        // Six, not four. Each op's `maxCost` is larger than what it actually
        // spends, so a bundle only over-commits the budget once enough ops have
        // validated against the same stale value to out-spend it.
        PackedUserOperation[] memory ops = new PackedUserOperation[](6);
        for (uint256 i = 0; i < 6; i++) {
            ops[i] = _sponsoredOpForNewAccount(i, "crowd");
        }
        entryPoint.handleOps(ops, bundler);

        (uint96 endBudget,) = paymaster.apps(app);
        uint256 freeAfter = paymaster.freeBalance();

        emit log_named_uint("budget before", startBudget);
        emit log_named_uint("budget after ", endBudget);
        emit log_named_uint("free before  ", freeBefore);
        emit log_named_uint("free after   ", freeAfter);

        assertEq(endBudget, 0, "the clamp fired: the budget is exhausted, not negative");

        assertEq(paymaster.totalAppBudgets(), 0, "the running total tracked the clamp exactly");
        assertGt(freeAfter, 0, "the owner buffer is still there to absorb the next one");
        _assertSolvent("solvency survives an over-subscribed bundle");
    }

    /// @notice The same bundle without an owner buffer.
    /// @dev The EntryPoint refuses it. Its prefund accounting is what stops an
    ///      app's budget being over-committed in the first place, so the
    ///      overdraw above is only reachable by an owner who funded the buffer
    ///      that pays for it.
    function test_withoutAnOwnerBufferTheEntryPointRefusesTheSecondOp() public {
        vm.prank(app);
        paymaster.withdrawAppBudget(payable(app), 5 ether - 0.0008 ether);
        assertEq(paymaster.freeBalance(), 0, "no buffer");

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = _sponsoredOpForNewAccount(0, "first");
        ops[1] = _sponsoredOpForNewAccount(1, "second");

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, uint256(1), "AA31 paymaster deposit too low"
            )
        );
        entryPoint.handleOps(ops, bundler);
    }

    function test_bundleWithBothModes() public {
        address secondOwner;
        uint256 secondOwnerKey;
        (secondOwner, secondOwnerKey) = makeAddrAndKey("secondOwner");
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount second = factory.createAccount(secondOwner, 0);

        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(address(second));

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = _sponsoredGuestbookOp("app pays");
        ops[1] = _depositOpFor(second, secondOwnerKey, "I pay");

        entryPoint.handleOps(ops, bundler);

        (uint96 budget,) = paymaster.apps(app);
        assertLt(budget, 5 ether, "the app paid for its own op");
        assertLt(paymaster.userDeposits(address(second)), 1 ether, "the user paid for theirs");
        _assertSolvent("solvency across mixed modes in one bundle");
    }

    // -------------------------------------------------------------- charging

    function test_revertingOpStillCharges() public {
        (uint96 before,) = paymaster.apps(app);

        PackedUserOperation memory op = _sponsoredOpWithCall(
            abi.encodeCall(
                BaseAccount.execute,
                (address(reverter), 0, abi.encodeCall(RevertingTarget.boom, ()))
            ),
            0,
            0
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, bundler);

        (uint96 afterBudget,) = paymaster.apps(app);
        assertLt(afterBudget, before, "the gas was burned, so the app pays anyway");
        _assertSolvent("solvency after a reverted operation");
    }

    function test_sponsoredOpDoesNotTouchOtherAppsBudgets() public {
        address otherApp = makeAddr("otherApp");
        vm.prank(owner);
        paymaster.registerApp(otherApp, makeAddr("otherSigner"));
        _fundApp(otherApp, 2 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _sponsoredGuestbookOp("mine");
        entryPoint.handleOps(ops, bundler);

        (uint96 otherBudget,) = paymaster.apps(otherApp);
        assertEq(otherBudget, 2 ether, "an unrelated app is untouched");
        _assertSolvent("solvency after a bundle with a second funded app");
    }

    // ------------------------------------------------------------- signatures

    /// @notice A sponsorship authorises one operation, not one sender.
    function test_thirdPartyCannotRepurposeASponsorship() public {
        PackedUserOperation memory signed = _sponsoredGuestbookOp("mine");

        address thiefOwner;
        uint256 thiefOwnerKey;
        (thiefOwner, thiefOwnerKey) = makeAddrAndKey("thiefOwner");
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount thief = factory.createAccount(thiefOwner, 0);

        // Lift the app's signed authorisation onto a different sender.
        PackedUserOperation memory stolen = _guestbookOp(thief, "stolen");
        stolen.paymasterAndData = signed.paymasterAndData;
        stolen.signature = _signAccount(thiefOwnerKey, stolen);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = stolen;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, uint256(0), "AA34 signature error"
            )
        );
        entryPoint.handleOps(ops, bundler);
    }

    /// @notice The digest covers both paymaster gas limits, so a bundler cannot
    ///         raise them after the app signed.
    function test_signatureCoversBothPaymasterGasLimits() public {
        PackedUserOperation memory op = _sponsoredGuestbookOp("mine");

        // Bump paymasterPostOpGasLimit (bytes 36:52) and leave everything else.
        bytes memory tampered = op.paymasterAndData;
        tampered[51] = bytes1(uint8(tampered[51]) ^ 0x01);
        op.paymasterAndData = tampered;
        op.signature = _signAccount(accountOwnerKey, op);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, uint256(0), "AA34 signature error"
            )
        );
        entryPoint.handleOps(ops, bundler);
    }

    // --------------------------------------------------------------- helpers

    /// @dev A sponsored op from a freshly deployed account, so a bundle can
    ///      hold several ops that share one paying app.
    function _sponsoredOpForNewAccount(uint256 seed, string memory message)
        internal
        returns (PackedUserOperation memory)
    {
        (, uint256 key) = makeAddrAndKey(string.concat("crowdOwner", vm.toString(seed)));
        vm.prank(address(entryPoint.senderCreator()));
        SimpleAccount who = factory.createAccount(vm.addr(key), seed + 1);
        return _sponsoredOpFor(who, key, message);
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

    function _sponsoredGuestbookOp(string memory message)
        internal
        view
        returns (PackedUserOperation memory)
    {
        return _sponsoredOpFor(account, accountOwnerKey, message);
    }

    function _sponsoredGuestbookOpWindow(string memory message, uint48 until, uint48 aft)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _guestbookOp(account, message);
        op = _attachSponsorship(op, until, aft);
        op.signature = _signAccount(accountOwnerKey, op);
    }

    function _sponsoredOpWithCall(bytes memory inner, uint48 until, uint48 aft)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = UserOpBuilder.base(address(account), entryPoint.getNonce(address(account), 0), inner);
        op = _attachSponsorship(op, until, aft);
        op.signature = _signAccount(accountOwnerKey, op);
    }

    function _sponsoredOpFor(SimpleAccount who, uint256 key, string memory message)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _guestbookOp(who, message);
        op = _attachSponsorship(op, 0, 0);
        op.signature = _signAccount(key, op);
    }

    function _depositGuestbookOp(string memory message)
        internal
        view
        returns (PackedUserOperation memory)
    {
        return _depositOpFor(account, accountOwnerKey, message);
    }

    function _depositOpFor(SimpleAccount who, uint256 key, string memory message)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _guestbookOp(who, message);
        op.paymasterAndData = UserOpBuilder.depositData(address(paymaster));
        op.signature = _signAccount(key, op);
    }

    function _attachSponsorship(PackedUserOperation memory op, uint48 until, uint48 aft)
        internal
        view
        returns (PackedUserOperation memory)
    {
        bytes memory prefix = UserOpBuilder.sponsoredPrefix(address(paymaster), app, until, aft);
        op.paymasterAndData = prefix;
        op.paymasterAndData =
            UserOpBuilder.withSignature(prefix, _signSponsorship(op, appSignerKey));
        return op;
    }

    /// @dev v0.8 `SimpleAccount` recovers from the raw `userOpHash`, which is
    ///      already an EIP-712 digest. No EIP-191 prefix. The account signature
    ///      must come last, because it covers `paymasterAndData`.
    function _signAccount(uint256 key, PackedUserOperation memory op)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, entryPoint.getUserOpHash(op));
        return abi.encodePacked(r, s, v);
    }
}
