// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";

import {CaseTest} from "../shared/CaseTest.sol";
import {UnflooredDepositPaymaster} from "./Broken.sol";
import {FlooredDepositPaymaster} from "./Fixed.sol";

/// @notice Case 03: a starved `postOp` drains the deposit and charges nobody.
contract Case03Test is CaseTest {
    uint128 internal constant STARVING_LIMIT = 5_000;

    /// @dev The owner's own money in the pot, above what users deposited. It
    ///      absorbs the gas the EntryPoint spends on `postOp` itself, which
    ///      `actualGasCost` cannot include, so neither paymaster here bills it.
    ///      Pricing that is a different case; this one is about the buffer
    ///      being drained on purpose.
    uint256 internal constant BUFFER = 0.001 ether;

    UnflooredDepositPaymaster internal broken;
    FlooredDepositPaymaster internal fixed_;

    SimpleAccount internal account;
    uint256 internal ownerKey;
    address internal bystander = makeAddr("bystander");

    function setUp() public override {
        super.setUp();
        broken = new UnflooredDepositPaymaster(IEntryPoint(address(entryPoint)));
        fixed_ = new FlooredDepositPaymaster(IEntryPoint(address(entryPoint)));
        (account, ownerKey) = _newAccount("user");

        // The user holds enough to pass validation; someone else holds more.
        broken.depositFor{value: 0.01 ether}(address(account));
        broken.depositFor{value: 1 ether}(bystander);
        broken.deposit{value: BUFFER}();
        fixed_.depositFor{value: 0.01 ether}(address(account));
        fixed_.depositFor{value: 1 ether}(bystander);
        fixed_.deposit{value: BUFFER}();
    }

    function _paidFromDeposit(address paymaster, uint128 postOpGasLimit, string memory text)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _op(account, text);
        op.paymasterAndData = _paymasterAndData(paymaster, postOpGasLimit, "");
        op = _signAsAccount(op, ownerKey);
    }

    function _solvent(UnflooredDepositPaymaster pm) internal view returns (bool) {
        return _depositOf(address(pm)) >= pm.totalDeposits();
    }

    /// @notice One starved operation: the bundle succeeds, the paymaster pays,
    ///         and the user's balance does not move.
    function test_brokenChargesNobodyWhenPostOpIsStarved() public {
        uint256 userBefore = broken.deposits(address(account));
        uint256 potBefore = _depositOf(address(broken));

        _handle(_paidFromDeposit(address(broken), STARVING_LIMIT, "free"));

        assertEq(broken.deposits(address(account)), userBefore, "the user was charged nothing");
        assertLt(_depositOf(address(broken)), potBefore, "the paymaster's deposit paid");
        assertEq(target.lastNote(address(account)), "", "the operation itself was rolled back");
    }

    /// @notice Why that matters: the user's balance never falls, so validation
    ///         never stops them, and each round takes a little more of the pot.
    ///         The buffer goes first, then other people's deposits.
    function test_repeatingItDrainsSomeoneElsesDeposit() public {
        uint256 userBefore = broken.deposits(address(account));
        for (uint256 i = 0; i < 20; i++) {
            _handle(_paidFromDeposit(address(broken), STARVING_LIMIT, "free"));
        }

        assertEq(broken.deposits(address(account)), userBefore, "twenty rounds, still no charge");
        assertFalse(_solvent(broken), "the pot now holds less than it owes");
        emit log_named_uint("owed", broken.totalDeposits());
        emit log_named_uint("held", _depositOf(address(broken)));
    }

    function test_fixedRefusesTheStarvingLimit() public {
        PackedUserOperation memory op = _paidFromDeposit(address(fixed_), STARVING_LIMIT, "free");
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA33 reverted",
                abi.encodeWithSelector(
                    FlooredDepositPaymaster.PostOpGasLimitTooLow.selector,
                    STARVING_LIMIT,
                    fixed_.MIN_POSTOP_GAS_LIMIT()
                )
            )
        );
        _handle(op);
    }

    function test_atItsFloorTheFixedVersionCharges() public {
        uint128 floor = uint128(fixed_.MIN_POSTOP_GAS_LIMIT());
        uint256 userBefore = fixed_.deposits(address(account));

        _handle(_paidFromDeposit(address(fixed_), floor, "paid"));

        assertLt(fixed_.deposits(address(account)), userBefore, "the user was charged");
        assertEq(target.lastNote(address(account)), "paid", "the operation ran");
        assertGe(_depositOf(address(fixed_)), fixed_.totalDeposits(), "the pot still covers it");
    }

    /// @notice The floor is a measurement plus a margin, not a guess. This
    ///         finds the largest limit at which the broken version's `postOp`
    ///         still starves, and checks the fixed version's floor clears it.
    function test_theFloorLeavesRoomToSpare() public {
        uint256 highestStarved;
        for (uint128 limit = 20_000; limit >= 5_000; limit -= 1_000) {
            uint256 snapshot = vm.snapshotState();
            uint256 before = broken.deposits(address(account));
            _handle(_paidFromDeposit(address(broken), limit, "probe"));
            bool starved = broken.deposits(address(account)) == before;
            vm.revertToState(snapshot);
            if (starved) {
                highestStarved = limit;
                break;
            }
        }
        emit log_named_uint("highest limit that starves postOp", highestStarved);
        assertGt(highestStarved, 0, "the probe found the starvation point");
        assertGe(
            fixed_.MIN_POSTOP_GAS_LIMIT(),
            (highestStarved * 3) / 2,
            "the floor is at least half again above where postOp starves"
        );
    }

    /// @notice Nothing here is a forbidden opcode. The broken version's
    ///         validation is correct; what is missing is a check.
    function test_noOpcodeCheckCatchesTheBrokenVersion() public {
        assertEq(
            _bannedOpcodeInValidation(
                IPaymaster(address(broken)),
                _paidFromDeposit(address(broken), STARVING_LIMIT, "free"),
                true
            ),
            0,
            "no forbidden opcode"
        );
    }

    /// @notice The static check says nothing about the fix either. This is
    ///         the trace that backs its silence up, on a limit the fixed
    ///         version accepts: at the starving one its validation reverts on
    ///         the first check, and a trace of that would prove very little.
    function test_theFixedVersionRunsNoBannedOpcode() public {
        PackedUserOperation memory op =
            _paidFromDeposit(address(fixed_), PAYMASTER_POSTOP_GAS, "paid");
        assertEq(
            _bannedOpcodeInValidation(IPaymaster(address(fixed_)), op, true),
            0,
            "no forbidden opcode ran during validation"
        );
        _handle(op);
        assertEq(target.lastNote(address(account)), "paid", "and the traced operation ran");
    }
}
