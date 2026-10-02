// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";

import {CaseTest} from "../shared/CaseTest.sol";
import {CappedPostOpPaymaster} from "./Broken.sol";
import {FlooredPostOpPaymaster} from "./Fixed.sol";

/// @notice Case 02: a ceiling on the postOp gas limit makes the paymaster
///         impossible to gas-estimate.
contract Case02Test is CaseTest {
    /// @dev The `paymasterPostOpGasLimit` the bundler behind Monarch's demo
    ///      simulated with while estimating gas, read off the error it
    ///      returned: `AA33 reverted PostOpGasLimitOutOfRange(2000000, 20000, 40000)`.
    uint128 internal constant ESTIMATION_LIMIT = 2_000_000;

    CappedPostOpPaymaster internal broken;
    FlooredPostOpPaymaster internal fixed_;

    SimpleAccount internal account;
    uint256 internal ownerKey;

    function setUp() public override {
        super.setUp();
        broken = new CappedPostOpPaymaster(IEntryPoint(address(entryPoint)));
        fixed_ = new FlooredPostOpPaymaster(IEntryPoint(address(entryPoint)));
        broken.deposit{value: 1 ether}();
        fixed_.deposit{value: 1 ether}();
        (account, ownerKey) = _newAccount("user");
    }

    function _sponsored(address paymaster, uint128 postOpGasLimit)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _op(account, "sponsored");
        op.paymasterAndData = _paymasterAndData(paymaster, postOpGasLimit, "");
        op = _signAsAccount(op, ownerKey);
    }

    /// @notice The trap. Every test written with a sensible limit passes.
    function test_brokenAcceptsTheLimitItWasTestedWith() public {
        _handle(_sponsored(address(broken), PAYMASTER_POSTOP_GAS));
        assertEq(target.lastNote(address(account)), "sponsored", "the operation ran");
        assertGt(broken.spent(address(account)), 0, "postOp recorded the cost");
    }

    /// @notice What the bundler's estimate runs into. The operation never
    ///         reaches a bundle, because it cannot be priced.
    function test_brokenRejectsTheLimitABundlerEstimatesWith() public {
        PackedUserOperation memory op = _sponsored(address(broken), ESTIMATION_LIMIT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA33 reverted",
                abi.encodeWithSelector(
                    CappedPostOpPaymaster.PostOpGasLimitOutOfRange.selector,
                    ESTIMATION_LIMIT,
                    20_000,
                    40_000
                )
            )
        );
        _handle(op);
    }

    function test_fixedAcceptsTheLimitABundlerEstimatesWith() public {
        _handle(_sponsored(address(fixed_), ESTIMATION_LIMIT));
        assertEq(target.lastNote(address(account)), "sponsored", "the operation ran");
    }

    /// @notice The price of a large limit, and why it is a price rather than a
    ///         danger: the EntryPoint charges the paymaster a tenth of the
    ///         unused part. Bill it to the payer; don't refuse the operation.
    function test_anOversizedLimitCostsThePaymasterAPenalty() public {
        uint256 before = _depositOf(address(fixed_));
        _handle(_sponsored(address(fixed_), PAYMASTER_POSTOP_GAS));
        uint256 atRealLimit = before - _depositOf(address(fixed_));

        (SimpleAccount other, uint256 otherKey) = _newAccount("other");
        PackedUserOperation memory op = _op(other, "sponsored");
        op.paymasterAndData = _paymasterAndData(address(fixed_), ESTIMATION_LIMIT, "");
        op = _signAsAccount(op, otherKey);

        before = _depositOf(address(fixed_));
        _handle(op);
        uint256 atEstimationLimit = before - _depositOf(address(fixed_));

        // About (2,000,000 - 10,000 used) / 10 gas, at 1 gwei.
        assertGt(
            atEstimationLimit,
            atRealLimit + 190_000 * FEE,
            "the unused postOp gas was billed to the paymaster"
        );
    }

    /// @notice The floor is kept. Case 03 is why.
    function test_fixedStillRefusesAStarvingLimit() public {
        PackedUserOperation memory op = _sponsored(address(fixed_), 5_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA33 reverted",
                abi.encodeWithSelector(
                    FlooredPostOpPaymaster.PostOpGasLimitTooLow.selector, 5_000, 20_000
                )
            )
        );
        _handle(op);
    }

    /// @notice Nothing about the broken version is visible to an opcode check.
    ///         It is a design decision, and only a test with the right limit
    ///         finds it.
    function test_noOpcodeCheckCatchesTheBrokenVersion() public {
        assertEq(
            _bannedOpcodeInValidation(
                IPaymaster(address(broken)), _sponsored(address(broken), PAYMASTER_POSTOP_GAS), true
            ),
            0,
            "no forbidden opcode: the ceiling is legal, just wrong"
        );
    }

    /// @notice The static check says nothing about the fix either. This is
    ///         the trace that backs its silence up: an operation the fixed
    ///         version accepts, and no forbidden opcode on the way.
    function test_theFixedVersionRunsNoBannedOpcode() public {
        PackedUserOperation memory op = _sponsored(address(fixed_), PAYMASTER_POSTOP_GAS);
        assertEq(
            _bannedOpcodeInValidation(IPaymaster(address(fixed_)), op, true),
            0,
            "no forbidden opcode ran during validation"
        );
        _handle(op);
        assertEq(target.lastNote(address(account)), "sponsored", "and the traced operation ran");
    }
}
