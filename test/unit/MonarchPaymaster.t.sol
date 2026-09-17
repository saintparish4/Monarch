// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";
import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {Validation} from "../../contracts/libraries/Validation.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";
import {ReentrantReceiver} from "../helpers/Adversary.sol";

/// @notice Branch coverage of MonarchPaymaster, one behaviour per test.
contract MonarchPaymasterTest is Fixture {
    // ---------------------------------------------------------------- deposits

    function test_depositFor_creditsUserAndForwardsToEntryPoint() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);

        assertEq(paymaster.userDeposits(alice), 1 ether, "user credited");
        assertEq(paymaster.totalUserDeposits(), 1 ether, "running total credited");
        assertEq(entryPoint.balanceOf(address(paymaster)), 1 ether, "forwarded to the EntryPoint");
        assertEq(address(paymaster).balance, 0, "nothing left sitting on the contract");
    }

    function test_depositFor_rejectsDust() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.DepositTooSmall.selector, uint256(1))
        );
        paymaster.depositFor{value: 1}(alice);
    }

    function test_depositFor_rejectsZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.depositFor{value: 1 ether}(address(0));
    }

    function test_depositFor_isPermissionless() public {
        vm.prank(bob);
        paymaster.depositFor{value: 1 ether}(alice);
        assertEq(paymaster.userDeposits(alice), 1 ether, "bob may gift alice a balance");
        assertEq(paymaster.userDeposits(bob), 0, "bob credited nothing to himself");
    }

    function test_withdrawUserDeposit_onlyDebitsCaller() public {
        vm.prank(alice);
        paymaster.depositFor{value: 2 ether}(alice);
        vm.prank(bob);
        paymaster.depositFor{value: 2 ether}(bob);

        uint256 before = alice.balance;
        vm.prank(alice);
        paymaster.withdrawUserDeposit(payable(alice), 1 ether);

        assertEq(paymaster.userDeposits(alice), 1 ether, "alice debited");
        assertEq(paymaster.userDeposits(bob), 2 ether, "bob untouched");
        assertEq(alice.balance, before + 1 ether, "alice paid");
        assertEq(paymaster.totalUserDeposits(), 3 ether, "running total tracks");
    }

    function test_withdrawUserDeposit_cannotOverdraw() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.InsufficientUserDeposit.selector, alice, 2 ether, 1 ether
            )
        );
        paymaster.withdrawUserDeposit(payable(alice), 2 ether);
    }

    // ------------------------------------------------------------------- owner

    function test_ownerCannotWithdrawUserFunds() public {
        vm.prank(alice);
        paymaster.depositFor{value: 5 ether}(alice);

        assertEq(paymaster.freeBalance(), 0, "nothing is free - it is all alice's");

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.WouldBreakSolvency.selector, 1 wei, 0)
        );
        paymaster.withdrawTo(payable(owner), 1 wei);
    }

    function test_ownerCannotWithdrawAppFunds() public {
        _fundApp(app, 5 ether);
        assertEq(paymaster.freeBalance(), 0, "nothing is free - it is all the app's");

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.WouldBreakSolvency.selector, 1 wei, 0)
        );
        paymaster.withdrawTo(payable(owner), 1 wei);
    }

    function test_ownerCanWithdrawOnlyTheExcess() public {
        vm.prank(alice);
        paymaster.depositFor{value: 3 ether}(alice);

        // The owner's own buffer, credited to nobody.
        vm.prank(owner);
        paymaster.deposit{value: 2 ether}();

        assertEq(paymaster.freeBalance(), 2 ether, "the buffer is free, the deposit is not");

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.WouldBreakSolvency.selector, 2 ether + 1, 2 ether
            )
        );
        paymaster.withdrawTo(payable(owner), 2 ether + 1);

        uint256 before = owner.balance;
        vm.prank(owner);
        paymaster.withdrawTo(payable(owner), 2 ether);
        assertEq(owner.balance, before + 2 ether, "the excess, and only the excess");
        _assertSolvent("solvency after the owner sweeps");
    }

    // --------------------------------------------------------------------- apps

    function test_fundApp_requiresRegistration() public {
        address stranger = makeAddr("stranger");
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.AppNotRegistered.selector, stranger)
        );
        paymaster.fundApp{value: 1 ether}(stranger);
    }

    function test_registerApp_rejectsDuplicates() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.AppAlreadyRegistered.selector, app));
        paymaster.registerApp(app, makeAddr("other"));
    }

    function test_ownerCannotRotateAppSigner() public {
        // `setAppSigner` keys off msg.sender, so the owner calling it edits the
        // owner's own (non-existent) app rather than the app's.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.AppNotRegistered.selector, owner));
        paymaster.setAppSigner(makeAddr("attackerSigner"));

        (, address signer) = paymaster.apps(app);
        assertEq(signer, appSigner, "the app's signer is unchanged");
    }

    function test_appRotatesItsOwnSigner() public {
        address newSigner = makeAddr("newSigner");
        vm.prank(app);
        paymaster.setAppSigner(newSigner);
        (, address signer) = paymaster.apps(app);
        assertEq(signer, newSigner, "the app rotated its own key");
    }

    function test_withdrawAppBudget_onlyDebitsCaller() public {
        address otherApp = makeAddr("otherApp");
        vm.prank(owner);
        paymaster.registerApp(otherApp, makeAddr("otherSigner"));
        _fundApp(app, 3 ether);
        _fundApp(otherApp, 3 ether);

        vm.prank(app);
        paymaster.withdrawAppBudget(payable(app), 1 ether);

        (uint96 budget,) = paymaster.apps(app);
        (uint96 otherBudget,) = paymaster.apps(otherApp);
        assertEq(budget, 2 ether, "the caller's budget fell");
        assertEq(otherBudget, 3 ether, "the other app is untouched");
        assertEq(paymaster.totalAppBudgets(), 5 ether, "running total tracks");
    }

    // -------------------------------------------------------------- validation

    function test_depositMode_validatesAgainstBalance() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);

        (bytes memory context, uint256 validationData) = _validate(_depositOp(alice), 0.5 ether);

        assertEq(validationData, SIG_VALIDATION_SUCCESS, "accepted");
        (MonarchPaymaster.Mode payer, address user,) =
            abi.decode(context, (MonarchPaymaster.Mode, address, address));
        assertEq(uint8(payer), uint8(MonarchPaymaster.Mode.Deposit), "deposit mode");
        assertEq(user, alice, "context names the payer");
    }

    function test_depositMode_rejectsWhenUnderfunded() public {
        vm.prank(alice);
        paymaster.depositFor{value: 0.1 ether}(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.InsufficientUserDeposit.selector, alice, 1 ether, 0.1 ether
            )
        );
        _validate(_depositOp(alice), 1 ether);
    }

    function test_sponsoredMode_acceptsAppSignature() public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);

        (bytes memory context, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData, 0, "accepted, with an open-ended time range");
        (MonarchPaymaster.Mode payer, address user, address which) =
            abi.decode(context, (MonarchPaymaster.Mode, address, address));
        assertEq(uint8(payer), uint8(MonarchPaymaster.Mode.Sponsored), "sponsored mode");
        assertEq(user, alice, "context names the user");
        assertEq(which, app, "context names the paying app");
    }

    function test_badSignature_returnsFailureNotRevert() public {
        _fundApp(app, 5 ether);
        (, uint256 wrongKey) = makeAddrAndKey("impostor");
        PackedUserOperation memory op = _sponsoredOp(alice, app, wrongKey, 0, 0);

        // The whole point: this must NOT revert. A revert makes the bundle
        // unmineable and gets the paymaster throttled.
        (bytes memory context, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData & 1, 1, "signature failure is signalled, not thrown");
        assertEq(context.length, 0, "no context, so postOp is never called");
    }

    function test_sponsoredMode_timeRangeIsReturnedNotEvaluated() public {
        _fundApp(app, 5 ether);
        uint48 validUntil = 1000;
        uint48 validAfter = 500;

        // Far outside the window. The paymaster must still accept and hand the
        // range back — the EntryPoint is what compares it against the clock.
        vm.warp(50_000);
        PackedUserOperation memory op =
            _sponsoredOp(alice, app, appSignerKey, validUntil, validAfter);
        (, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData & 1, 0, "no signature failure");
        assertEq(uint48(validationData >> 160), validUntil, "validUntil returned verbatim");
        assertEq(uint48(validationData >> 208), validAfter, "validAfter returned verbatim");
    }

    function test_sponsoredMode_rejectsUnregisteredApp() public {
        address stranger = makeAddr("stranger");
        PackedUserOperation memory op = _sponsoredOp(alice, stranger, appSignerKey, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.AppNotRegistered.selector, stranger)
        );
        _validate(op, 1 ether);
    }

    function test_sponsoredMode_rejectsOverBudget() public {
        _fundApp(app, 1 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.InsufficientAppBudget.selector, app, 2 ether, 1 ether
            )
        );
        _validate(op, 2 ether);
    }

    function test_malformedData_reverts() public {
        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        op.paymasterAndData = abi.encodePacked(address(paymaster)); // 20 bytes, no mode byte
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.MalformedPaymasterData.selector, uint256(20))
        );
        _validate(op, 1 ether);
    }

    function test_depositMode_rejectsTrailingBytes() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);

        PackedUserOperation memory op = _depositOp(alice);
        op.paymasterAndData = bytes.concat(op.paymasterAndData, hex"ff");
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.MalformedPaymasterData.selector, Constants.DEPOSIT_DATA_LENGTH + 1
            )
        );
        _validate(op, 0.5 ether);
    }

    function test_sponsoredMode_rejectsTrailingBytes() public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        op.paymasterAndData = bytes.concat(op.paymasterAndData, hex"ff");
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.MalformedPaymasterData.selector,
                Constants.SPONSORED_DATA_LENGTH + 1
            )
        );
        _validate(op, 1 ether);
    }

    /// @notice The sponsored fields fill exactly one word, which is what lets
    ///         validation read them with a single calldata slice.
    /// @dev `_validateSponsored` reads `[APP_OFFSET:SIGNATURE_OFFSET]` as one
    ///      `bytes32` and shifts the three fields out of it, which is 1,025 gas
    ///      cheaper than three sub-word slices and their bounds checks. That is
    ///      only correct while the three widths still add to 32: widen the time
    ///      fields and the app address silently loses its low bytes. This is the
    ///      assertion that stops that being a runtime surprise.
    function test_theSponsoredFieldsFillExactlyOneWord() public pure {
        assertEq(
            Constants.APP_WIDTH + 2 * Constants.TIMESTAMP_WIDTH,
            32,
            "app + validUntil + validAfter is one word"
        );
        assertEq(
            Constants.SIGNATURE_OFFSET - Constants.APP_OFFSET,
            32,
            "and the slice validation takes is exactly that word"
        );
        assertEq(
            Constants.VALID_UNTIL_OFFSET - Constants.APP_OFFSET,
            Constants.APP_WIDTH,
            "validUntil begins where the app address ends"
        );
        assertEq(
            Constants.VALID_AFTER_OFFSET - Constants.VALID_UNTIL_OFFSET,
            Constants.TIMESTAMP_WIDTH,
            "and validAfter where validUntil ends"
        );
    }

    function test_unknownMode_reverts() public {
        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            UserOpBuilder.DEFAULT_PM_VERIFICATION_GAS,
            UserOpBuilder.DEFAULT_PM_POSTOP_GAS,
            uint8(2)
        );
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.UnknownMode.selector, uint8(2)));
        _validate(op, 1 ether);
    }

    /// @notice A large postOp gas limit is priced, not refused.
    /// @dev Refusing it would be the obvious move and it is the wrong one:
    ///      bundlers simulate with a limit far above anything real — Pimlico
    ///      uses 2,000,000 — so a paymaster that reverts on a large limit
    ///      cannot be gas-estimated, and therefore cannot be used at all. That
    ///      is not a hypothetical; it is how the first version of this check
    ///      was found to be wrong, on Base Sepolia, by the demo failing.
    function test_largePostOpGasLimit_isAcceptedRatherThanRefused() public {
        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        op.paymasterAndData = UserOpBuilder.depositData(address(paymaster), uint128(2_000_000));
        paymaster.depositFor{value: 1 ether}(alice);

        (bytes memory context, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 0, "the bundler's estimation limit is accepted");
        assertGt(context.length, 0, "and produces a live context");
    }

    /// @notice What it costs instead: the payer is billed the EntryPoint's
    ///         unused-gas penalty on the limit they asked for.
    /// @dev This is what makes refusing unnecessary. The penalty is a tenth of
    ///      the unused remainder, so an operation that reserves 500,000 of
    ///      postOp gas and uses 11,500 of it pays about 49,000 gas for the
    ///      privilege — out of its own budget, not the owner's.
    function test_anOversizedGasLimitIsChargedToThePayerNotTheOwner() public {
        paymaster.depositFor{value: 1 ether}(alice);
        uint256 feePerGas = 1 gwei;

        _postOp(
            UserOpBuilder.context(MonarchPaymaster.Mode.Deposit, alice, address(0), 500_000),
            0,
            feePerGas
        );
        uint256 charged = 1 ether - paymaster.userDeposits(alice);

        // (500,000 - 10,000) / 10 = 49,000, on top of the flat overhead.
        uint256 expected = (paymaster.POSTOP_GAS_OVERHEAD() + 49_000) * feePerGas;
        assertEq(charged, expected, "the penalty is charged to the payer who caused it");
    }

    /// @notice And a limit small enough to attract no penalty is charged none.
    function test_aGasLimitBelowTheThresholdCarriesNoPenalty() public {
        paymaster.depositFor{value: 1 ether}(alice);
        uint256 feePerGas = 1 gwei;

        _postOp(
            UserOpBuilder.context(MonarchPaymaster.Mode.Deposit, alice, address(0), 40_000),
            0,
            feePerGas
        );

        assertEq(
            1 ether - paymaster.userDeposits(alice),
            paymaster.POSTOP_GAS_OVERHEAD() * feePerGas,
            "the flat overhead and nothing more"
        );
    }

    /// @notice An operation asking for too little postOp gas is refused.
    /// @dev The dangerous direction, and the one a price cannot fix. A starved
    ///      `postOp` reverts, the EntryPoint swallows it and settles in
    ///      `postOpReverted` mode, and the payer is never debited at all — there
    ///      is no later moment at which to charge anyone. See the bundle-level
    ///      proof in `GasLimits.t.sol`.
    function test_insufficientPostOpGasLimit_reverts() public {
        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        op.paymasterAndData = UserOpBuilder.depositData(address(paymaster), uint128(11_000));
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.PostOpGasLimitTooLow.selector,
                uint256(11_000),
                paymaster.MIN_POSTOP_GAS_LIMIT()
            )
        );
        _validate(op, 1 ether);
    }

    /// @notice The floor itself is legal. Off-by-one here refuses honest
    ///         operations.
    function test_postOpGasLimitExactlyAtTheFloorIsAccepted() public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        bytes memory prefix = UserOpBuilder.sponsoredPrefix(
            address(paymaster), app, 0, 0, uint128(paymaster.MIN_POSTOP_GAS_LIMIT())
        );
        op.paymasterAndData = prefix;
        op.paymasterAndData =
            UserOpBuilder.withSignature(prefix, _signSponsorship(op, appSignerKey));

        (, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 0, "a limit exactly at the floor is accepted");
    }

    function test_onlyEntryPointMayValidate() public {
        PackedUserOperation memory op = _depositOp(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.NotEntryPoint.selector, alice));
        paymaster.validatePaymasterUserOp(op, bytes32(0), 1 ether);
    }

    function test_onlyEntryPointMayCallPostOp() public {
        bytes memory context =
            UserOpBuilder.context(MonarchPaymaster.Mode.Deposit, alice, address(0));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.NotEntryPoint.selector, alice));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 1 ether, 1);
    }

    // ------------------------------------------------------------------ postOp

    function test_postOp_chargesTheAppNotTheUser() public {
        _fundApp(app, 5 ether);
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);

        _postOp(UserOpBuilder.context(MonarchPaymaster.Mode.Sponsored, alice, app), 0.1 ether, 0);

        (uint96 budget,) = paymaster.apps(app);
        assertEq(budget, 5 ether - 0.1 ether, "the app paid");
        assertEq(paymaster.userDeposits(alice), 1 ether, "the user did not");
    }

    function test_postOp_chargesEvenWhenTheOpReverted() public {
        _fundApp(app, 5 ether);
        bytes memory context = UserOpBuilder.context(MonarchPaymaster.Mode.Sponsored, alice, app);

        // `opReverted` describes whether the operation succeeded. It must not
        // select a payment scheme — reading it as one is the bug this replaces.
        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opReverted, context, 0.1 ether, 0);

        (uint96 budget,) = paymaster.apps(app);
        assertEq(budget, 5 ether - 0.1 ether, "the gas was burned, so the app pays");
    }

    function test_postOp_clampsRatherThanUnderflowing() public {
        vm.prank(alice);
        paymaster.depositFor{value: 0.5 ether}(alice);

        _postOp(
            UserOpBuilder.context(MonarchPaymaster.Mode.Deposit, alice, address(0)), 10 ether, 0
        );

        assertEq(paymaster.userDeposits(alice), 0, "drained, not reverted");
        assertEq(paymaster.totalUserDeposits(), 0, "running total drained with it");
    }

    function test_postOp_chargesTheOverheadOnTopOfGas() public {
        _fundApp(app, 5 ether);
        _postOp(UserOpBuilder.context(MonarchPaymaster.Mode.Sponsored, alice, app), 0.1 ether, 2);

        (uint96 budget,) = paymaster.apps(app);
        uint256 expected = 5 ether - (0.1 ether + paymaster.POSTOP_GAS_OVERHEAD() * 2);
        assertEq(budget, expected, "gas plus the postOp overhead");
    }

    // ------------------------------------------------------------- reentrancy

    function test_reentrantWithdrawUserDeposit_isBlocked() public {
        ReentrantReceiver attacker = new ReentrantReceiver(paymaster);
        vm.deal(address(attacker), 2 ether);
        attacker.depositTo{value: 1 ether}(1 ether);

        attacker.armUser();
        vm.expectRevert(); // ReentrancyGuardReentrantCall, surfaced through the EntryPoint
        attacker.withdraw(0.5 ether);
    }

    function test_reentrantWithdrawAppBudget_isBlocked() public {
        ReentrantReceiver attacker = new ReentrantReceiver(paymaster);
        vm.prank(owner);
        paymaster.registerApp(address(attacker), makeAddr("attackerSigner"));
        vm.deal(address(attacker), 2 ether);
        vm.prank(address(attacker));
        paymaster.fundApp{value: 1 ether}(address(attacker));

        attacker.armApp();
        vm.expectRevert();
        attacker.withdrawBudget(0.5 ether);
    }

    function test_reentrantDepositDuringWithdraw_preservesSolvency() public {
        ReentrantReceiver attacker = new ReentrantReceiver(paymaster);
        vm.deal(address(attacker), 2 ether);
        attacker.depositTo{value: 1 ether}(1 ether);

        // `depositFor` is deliberately NOT guarded. Re-entering it mid-withdrawal
        // is expected to succeed; the claim under test is that solvency survives,
        // because balances are written before the external call.
        attacker.armDepositor();
        attacker.withdraw(0.5 ether);

        assertTrue(attacker.attempted(), "the callback actually fired");
        _assertSolvent("solvency across a nested deposit");
        assertEq(
            paymaster.userDeposits(address(attacker)),
            0.5 ether + 0.0001 ether,
            "both the debit and the nested credit landed"
        );
    }

    // ------------------------------------------------------------------- stake

    function test_addStakeDoesNotInflateFreeBalance() public {
        vm.prank(owner);
        paymaster.addStake{value: 1 ether}(1 days);

        assertEq(paymaster.freeBalance(), 0, "the stake is a separate pot from the deposit");
        assertEq(entryPoint.balanceOf(address(paymaster)), 0, "and is not the deposit");
    }

    function test_nonOwnerCannotManageStake() public {
        vm.prank(alice);
        vm.expectRevert();
        paymaster.addStake{value: 1 ether}(1 days);

        vm.prank(alice);
        vm.expectRevert();
        paymaster.unlockStake();

        vm.prank(alice);
        vm.expectRevert();
        paymaster.withdrawStake(payable(alice));
    }

    // -------------------------------------------------------------- constructor

    function test_constructorRejectsAnEoaEntryPoint() public {
        vm.expectRevert(abi.encodeWithSelector(Validation.NotAContract.selector, alice));
        new MonarchPaymaster(IEntryPoint(alice));
    }
}
