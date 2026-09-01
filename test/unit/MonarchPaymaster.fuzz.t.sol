// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";

/// @notice Properties of one call at a time, with Foundry picking the inputs.
/// @dev These cover what branch coverage cannot see: that a rule holds for every
///      input, not just the one I thought of.
contract MonarchPaymasterFuzzTest is Fixture {
    /// @notice Every length except the two legal ones is rejected.
    /// @dev The trailing-garbage case matters: tolerating a tail would let two
    ///      distinct byte strings authorise the same operation.
    function testFuzz_lengthOtherThanExact_reverts(uint16 rawLength) public {
        uint256 length = bound(rawLength, 0, 400);
        vm.assume(length != Constants.DEPOSIT_DATA_LENGTH);
        vm.assume(length != Constants.SPONSORED_DATA_LENGTH);

        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        bytes memory data = new bytes(length);
        // Mode 0 where the mode byte lives, so length is the only thing wrong.
        if (length > Constants.MODE_OFFSET) data[Constants.MODE_OFFSET] = 0x00;
        op.paymasterAndData = data;

        vm.prank(alice);
        paymaster.depositFor{value: 10 ether}(alice);

        vm.expectRevert();
        _validate(op, 1 ether);
    }

    /// @notice Every mode byte above 0x01 is rejected by name.
    function testFuzz_modeAboveOne_reverts(uint8 rawMode) public {
        uint8 mode = uint8(bound(rawMode, 2, type(uint8).max));

        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            UserOpBuilder.DEFAULT_PM_VERIFICATION_GAS,
            UserOpBuilder.DEFAULT_PM_POSTOP_GAS,
            mode
        );

        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.UnknownMode.selector, mode));
        _validate(op, 1 ether);
    }

    /// @notice The app decoded from the calldata is the app that was encoded.
    /// @dev An off-by-one in the offsets decodes a plausible-looking address
    ///      rather than reverting, which is why this is a property and not an
    ///      example.
    function testFuzz_appAddressRoundTrips(address candidate, uint48 until, uint48 aft) public {
        vm.assume(candidate != address(0));
        vm.assume(candidate != app);

        vm.prank(owner);
        paymaster.registerApp(candidate, appSigner);
        _fundApp(candidate, 5 ether);

        PackedUserOperation memory op = _sponsoredOp(alice, candidate, appSignerKey, until, aft);
        (bytes memory context,) = _validate(op, 1 ether);

        (,, address decoded) = abi.decode(context, (MonarchPaymaster.Mode, address, address));
        assertEq(decoded, candidate, "the app encoded is the app charged");
    }

    /// @notice A deposit round trip returns exactly what went in.
    function testFuzz_depositThenWithdraw_isLossless(uint96 rawAmount) public {
        uint256 amount = bound(rawAmount, Constants.MIN_DEPOSIT, 1_000 ether);
        vm.deal(alice, amount);

        vm.prank(alice);
        paymaster.depositFor{value: amount}(alice);
        assertEq(paymaster.userDeposits(alice), amount, "credited exactly");
        assertEq(paymaster.totalUserDeposits(), amount, "running total credited exactly");

        vm.prank(alice);
        paymaster.withdrawUserDeposit(payable(alice), amount);

        assertEq(paymaster.userDeposits(alice), 0, "debited exactly");
        assertEq(paymaster.totalUserDeposits(), 0, "running total debited exactly");
        assertEq(alice.balance, amount, "the user has their money back");
    }

    /// @notice `postOp` clamps rather than underflowing, for any charge.
    function testFuzz_postOpNeverUnderflows(uint96 rawBalance, uint256 rawCost, uint64 feePerGas)
        public
    {
        uint256 balance = bound(rawBalance, Constants.MIN_DEPOSIT, 1_000 ether);
        uint256 cost = bound(rawCost, 0, 2_000 ether);
        vm.deal(alice, balance);
        vm.prank(alice);
        paymaster.depositFor{value: balance}(alice);

        _postOp(abi.encode(MonarchPaymaster.Mode.Deposit, alice, address(0)), cost, feePerGas);

        uint256 charge = cost + paymaster.POSTOP_GAS_OVERHEAD() * uint256(feePerGas);
        uint256 expected = charge > balance ? 0 : balance - charge;
        assertEq(paymaster.userDeposits(alice), expected, "clamped, never negative");
        assertEq(paymaster.totalUserDeposits(), expected, "running total tracks the debit");
    }

    /// @notice `freeBalance()` never overstates what is actually there.
    function testFuzz_freeBalanceNeverOverstates(uint96 rawUser, uint96 rawApp, uint96 rawBuffer)
        public
    {
        uint256 userAmount = bound(rawUser, Constants.MIN_DEPOSIT, 100 ether);
        uint256 appAmount = bound(rawApp, 1, 100 ether);
        uint256 buffer = bound(rawBuffer, 0, 100 ether);

        vm.deal(alice, userAmount);
        vm.prank(alice);
        paymaster.depositFor{value: userAmount}(alice);
        _fundApp(app, appAmount);
        if (buffer > 0) {
            vm.deal(owner, buffer);
            vm.prank(owner);
            paymaster.deposit{value: buffer}();
        }

        uint256 free = paymaster.freeBalance();
        assertEq(free, buffer, "free is exactly the unclaimed buffer");
        assertLe(free, entryPoint.balanceOf(address(paymaster)), "free never exceeds the balance");

        // And it is genuinely withdrawable, which is the claim that matters.
        if (free > 0) {
            vm.prank(owner);
            paymaster.withdrawTo(payable(owner), free);
        }
        _assertSolvent("solvency after sweeping the whole free balance");
    }

    /// @notice The running app total equals the sum of budgets after any
    ///         sequence of top-ups.
    function testFuzz_fundApp_totalsAgree(uint96 rawA, uint96 rawB, uint96 rawC) public {
        address second = makeAddr("secondApp");
        vm.prank(owner);
        paymaster.registerApp(second, makeAddr("secondSigner"));

        uint256 a = bound(rawA, 1, 100 ether);
        uint256 b = bound(rawB, 1, 100 ether);
        uint256 c = bound(rawC, 1, 100 ether);

        _fundApp(app, a);
        _fundApp(second, b);
        _fundApp(app, c);

        (uint96 first,) = paymaster.apps(app);
        (uint96 other,) = paymaster.apps(second);
        assertEq(uint256(first), a + c, "top-ups accumulate");
        assertEq(uint256(other), b, "and do not leak between apps");
        assertEq(paymaster.totalAppBudgets(), a + b + c, "the running total is the sum");
        _assertSolvent("solvency after arbitrary funding");
    }

    /// @notice Any signer that is not the app's is rejected, never accepted.
    function testFuzz_onlyTheRegisteredSignerIsAccepted(uint256 rawKey) public {
        uint256 key = bound(rawKey, 1, type(uint128).max);
        vm.assume(vm.addr(key) != appSigner);
        _fundApp(app, 5 ether);

        PackedUserOperation memory op = _sponsoredOp(alice, app, key, 0, 0);
        (bytes memory context, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData & 1, 1, "rejected");
        assertEq(context.length, 0, "and no context handed to postOp");
    }

    /// @notice A correct signature is always accepted, for any time window.
    function testFuzz_theRegisteredSignerIsAlwaysAccepted(uint48 until, uint48 aft) public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, until, aft);
        (, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData & 1, 0, "accepted whatever the window says");
        assertEq(uint48(validationData >> 160), until, "validUntil returned verbatim");
        assertEq(uint48(validationData >> 208), aft, "validAfter returned verbatim");
    }
}
