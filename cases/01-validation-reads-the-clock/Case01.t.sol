// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";

import {CaseTest} from "../shared/CaseTest.sol";
import {ClockCheckingPaymaster} from "./Broken.sol";
import {WindowReturningPaymaster} from "./Fixed.sol";

/// @notice Case 01: validation reads the clock.
contract Case01Test is CaseTest {
    uint8 internal constant TIMESTAMP = 0x42;

    ClockCheckingPaymaster internal broken;
    WindowReturningPaymaster internal fixed_;

    SimpleAccount internal account;
    uint256 internal ownerKey;

    uint48 internal validUntil;

    function setUp() public override {
        super.setUp();
        broken = new ClockCheckingPaymaster(IEntryPoint(address(entryPoint)));
        fixed_ = new WindowReturningPaymaster(IEntryPoint(address(entryPoint)));
        broken.deposit{value: 1 ether}();
        fixed_.deposit{value: 1 ether}();
        (account, ownerKey) = _newAccount("user");
        validUntil = uint48(block.timestamp + 1 hours);
    }

    function _sponsored(address paymaster, uint48 until)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _op(account, "sponsored");
        op.paymasterAndData =
            _paymasterAndData(paymaster, PAYMASTER_POSTOP_GAS, abi.encodePacked(until));
        op = _signAsAccount(op, ownerKey);
    }

    /// @notice The trap. On chain, nothing enforces ERC-7562, so the broken
    ///         version passes every test that goes through the EntryPoint.
    function test_bothVersionsPassTheEntryPoint() public {
        _handle(_sponsored(address(broken), validUntil));
        assertEq(target.lastNote(address(account)), "sponsored", "the broken version sponsored it");

        _handle(_sponsored(address(fixed_), validUntil));
        assertEq(target.lastNote(address(account)), "sponsored", "the fixed version sponsored it");
        assertEq(address(account).balance, 0, "the user paid nothing either time");
    }

    /// @notice What a bundler's tracer sees, and why it drops the operation.
    function test_theBrokenVersionRunsTimestampDuringValidation() public {
        assertEq(
            _bannedOpcodeInValidation(
                IPaymaster(address(broken)), _sponsored(address(broken), validUntil), false
            ),
            TIMESTAMP,
            "validation executed TIMESTAMP, which OP-011 forbids"
        );
    }

    function test_theFixedVersionRunsNoBannedOpcode() public {
        assertEq(
            _bannedOpcodeInValidation(
                IPaymaster(address(fixed_)), _sponsored(address(fixed_), validUntil), false
            ),
            0,
            "no forbidden opcode ran during validation"
        );
    }

    /// @notice Why the rule exists. The bundler simulates before the block
    ///         exists, so a validation that reads the clock can pass when it is
    ///         checked and fail when it runs. The bundler pays for that failure.
    function test_theBrokenVersionsAnswerDependsOnWhenItIsAsked() public {
        PackedUserOperation memory op = _sponsored(address(broken), validUntil);
        uint256 maxCost = _maxCost(op);

        vm.prank(address(entryPoint));
        (, uint256 whenSimulated) = broken.validatePaymasterUserOp(op, bytes32(0), maxCost);
        assertEq(whenSimulated, 0, "valid when the bundler simulated it");

        vm.warp(uint256(validUntil) + 1);
        vm.prank(address(entryPoint));
        (, uint256 whenIncluded) = broken.validatePaymasterUserOp(op, bytes32(0), maxCost);
        assertEq(whenIncluded, 1, "invalid by the time a block ran it");
    }

    /// @notice The fix loses nothing: the window is still enforced, by the
    ///         EntryPoint instead of the paymaster.
    function test_theFixedVersionStillEnforcesTheWindow() public {
        PackedUserOperation memory op = _sponsored(address(fixed_), validUntil);
        vm.warp(uint256(validUntil) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector, 0, "AA32 paymaster expired or not due"
            )
        );
        _handle(op);
    }
}
