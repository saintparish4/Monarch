// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";

/// @notice One test per bug that was true of this repository before the rewrite.
/// @dev Nine were recorded. Two of them — the wrong `postOp` arity and the wrong
///      validation return shape — are now compile errors rather than runtime
///      bugs, because the contract implements the canonical `IPaymaster` instead
///      of restating it. A guarantee the compiler enforces is stronger than one
///      a test enforces, so those two have no test here on purpose. A ninth was
///      an unused counter, and the field no longer exists.
contract MonarchPaymasterDefectsTest is Fixture {
    /// @notice Defect 1: `postOp` read `PostOpMode` as a sponsorship mode, so an
    ///         op that succeeded was billed to a different scheme than one that
    ///         reverted.
    function test_defect1_postOpModeDoesNotSelectPayer() public {
        _fundApp(app, 5 ether);
        vm.prank(alice);
        paymaster.depositFor{value: 5 ether}(alice);

        bytes memory context = abi.encode(MonarchPaymaster.Mode.Sponsored, alice, app);

        (uint96 budgetStart,) = paymaster.apps(app);
        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 0.1 ether, 0);
        (uint96 afterSuccess,) = paymaster.apps(app);

        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opReverted, context, 0.1 ether, 0);
        (uint96 afterRevert,) = paymaster.apps(app);

        assertEq(budgetStart - afterSuccess, 0.1 ether, "success charges the app");
        assertEq(afterSuccess - afterRevert, 0.1 ether, "and a revert charges it identically");
        assertEq(paymaster.userDeposits(alice), 5 ether, "the user was never involved");
    }

    /// @notice Defect 4: the paymaster was never funded on the EntryPoint, so
    ///         every sponsored operation failed for lack of a deposit.
    function test_defect4_fundsReachTheEntryPoint() public {
        _fundApp(app, 3 ether);
        vm.prank(alice);
        paymaster.depositFor{value: 2 ether}(alice);

        assertEq(entryPoint.balanceOf(address(paymaster)), 5 ether, "the EntryPoint holds it");
        assertEq(address(paymaster).balance, 0, "nothing idles on the contract");
    }

    /// @notice Defect 5: withdrawal debited the named user and paid `msg.sender`,
    ///         so any admin could drain any user into their own pocket.
    function test_defect5_withdrawDebitsTheCallerOnly() public {
        vm.prank(alice);
        paymaster.depositFor{value: 4 ether}(alice);

        // There is no argument that names a victim. The only account this can
        // debit is the caller's, which is the whole point of the signature.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.InsufficientUserDeposit.selector, bob, 1 ether, 0
            )
        );
        paymaster.withdrawUserDeposit(payable(bob), 1 ether);

        assertEq(paymaster.userDeposits(alice), 4 ether, "alice is untouched");
    }

    /// @notice Defect 6: an admin could withdraw against the raw balance, which
    ///         is the same pot backing every user deposit and app budget.
    function test_defect6_withdrawToRespectsSolvency() public {
        vm.prank(alice);
        paymaster.depositFor{value: 3 ether}(alice);
        _fundApp(app, 2 ether);

        assertEq(entryPoint.balanceOf(address(paymaster)), 5 ether, "five ether is present");
        assertEq(paymaster.freeBalance(), 0, "and none of it is the owner's");

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.WouldBreakSolvency.selector, 5 ether, 0)
        );
        paymaster.withdrawTo(payable(owner), 5 ether);
    }

    /// @notice Defect 7: the mode byte was read at offset 20, the v0.6 position.
    ///         Under v0.7+ offset 20 is the first byte of the paymaster
    ///         verification gas limit.
    /// @dev Constructed so the two readings disagree: byte 20 says Sponsored,
    ///      byte 52 says Deposit. Reading the old offset would send this down the
    ///      sponsored path and revert on an unregistered app.
    function test_defect7_modeByteIsReadAtOffset52NotOffset20() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);

        // A verification gas limit whose top byte is 0x01, so paymasterAndData[20]
        // reads as the Sponsored mode byte under the old layout.
        uint128 pmVerificationGas = uint128(0x01) << 120;
        PackedUserOperation memory op = UserOpBuilder.base(alice, 0, "");
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            pmVerificationGas,
            UserOpBuilder.DEFAULT_PM_POSTOP_GAS,
            uint8(0) // the real mode byte, at offset 52
        );

        assertEq(uint8(op.paymasterAndData[20]), 1, "byte 20 says Sponsored");
        assertEq(uint8(op.paymasterAndData[Constants.MODE_OFFSET]), 0, "byte 52 says Deposit");

        (bytes memory context, uint256 validationData) = _validate(op, 0.5 ether);

        assertEq(validationData, SIG_VALIDATION_SUCCESS, "accepted as a deposit");
        (MonarchPaymaster.Mode payer,,) =
            abi.decode(context, (MonarchPaymaster.Mode, address, address));
        assertEq(uint8(payer), uint8(MonarchPaymaster.Mode.Deposit), "byte 52 is what counts");
    }

    /// @notice Defect 8: validation read `block.timestamp`, which is a banned
    ///         opcode under ERC-7562 and gets every operation rejected.
    /// @dev No on-chain test can watch for an opcode. What it can watch is the
    ///      consequence: a function that reads no clock returns the same answer
    ///      whatever the clock says. This is a proxy, not a proof — only a real
    ///      bundler's tracer settles it.
    function test_defect8_validationIsIndependentOfTimestamp() public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 1_000, 500);

        vm.warp(1);
        (bytes memory earlyContext, uint256 earlyData) = _validate(op, 1 ether);

        vm.warp(2 ** 40);
        (bytes memory lateContext, uint256 lateData) = _validate(op, 1 ether);

        assertEq(earlyData, lateData, "validationData does not depend on the clock");
        assertEq(keccak256(earlyContext), keccak256(lateContext), "nor does the context");
    }

    /// @notice The same, for the block number.
    function test_defect8_validationIsIndependentOfBlockNumber() public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 1_000, 500);

        vm.roll(1);
        (bytes memory lowContext, uint256 lowData) = _validate(op, 1 ether);

        vm.roll(10_000_000);
        (bytes memory highContext, uint256 highData) = _validate(op, 1 ether);

        assertEq(lowData, highData, "validationData does not depend on the block number");
        assertEq(keccak256(lowContext), keccak256(highContext), "nor does the context");
    }

    /// @notice Validation records nothing.
    /// @dev `view` already guarantees this; the test states why it is `view`,
    ///      which the modifier does not. A validation that cannot write cannot
    ///      leave partial state behind when a bundle is dropped.
    function test_validationWritesNoStorage() public {
        _fundApp(app, 5 ether);
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);

        vm.startStateDiffRecording();
        _validate(op, 1 ether);
        VmSafe.AccountAccess[] memory records = vm.stopAndReturnStateDiff();

        uint256 writes;
        for (uint256 i = 0; i < records.length; i++) {
            for (uint256 j = 0; j < records[i].storageAccesses.length; j++) {
                if (
                    records[i].storageAccesses[j].isWrite
                        && records[i].storageAccesses[j].account == address(paymaster)
                ) {
                    writes++;
                }
            }
        }
        assertEq(writes, 0, "validation decides, it never records");
    }
}
