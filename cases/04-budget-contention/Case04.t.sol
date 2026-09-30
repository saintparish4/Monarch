// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";

import {CaseTest} from "../shared/CaseTest.sol";
import {BudgetLedger} from "./BudgetLedger.sol";
import {CheckedBudgetPaymaster} from "./Broken.sol";
import {ReservingBudgetPaymaster} from "./Reserving.sol";
import {BoundedBudgetPaymaster} from "./Bounded.sol";

/// @notice Case 04: several outstanding sponsorships compete for one budget.
contract Case04Test is CaseTest {
    uint256 internal constant OPS = 6;
    uint256 internal constant BYSTANDER_BUDGET = 1 ether;

    CheckedBudgetPaymaster internal broken;
    ReservingBudgetPaymaster internal reserving;
    BoundedBudgetPaymaster internal bounded;

    address internal app = makeAddr("app");
    address internal bystander = makeAddr("bystanderApp");

    /// @dev The largest cost validation will let one operation run up. The
    ///      contended app's budget is exactly this: enough for any one of its
    ///      operations, not for all of them.
    uint256 internal maxCost;

    function setUp() public override {
        super.setUp();
        broken = new CheckedBudgetPaymaster(IEntryPoint(address(entryPoint)));
        reserving = new ReservingBudgetPaymaster(IEntryPoint(address(entryPoint)));
        bounded = new BoundedBudgetPaymaster(IEntryPoint(address(entryPoint)));

        (SimpleAccount probe,) = _newAccount("probe");
        maxCost = _maxCost(_opFor(probe, 0, address(broken)));

        BudgetLedger[3] memory all = [BudgetLedger(broken), reserving, bounded];
        for (uint256 i = 0; i < all.length; i++) {
            all[i].fund{value: maxCost}(app);
            all[i].fund{value: BYSTANDER_BUDGET}(bystander);
            all[i].addStake{value: 1 ether}(1 days);
        }
    }

    function _opFor(SimpleAccount account, uint256 ownerKey, address paymaster)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _op(account, "sponsored");
        op.paymasterAndData =
            _paymasterAndData(paymaster, PAYMASTER_POSTOP_GAS, abi.encodePacked(app));
        if (ownerKey != 0) op = _signAsAccount(op, ownerKey);
    }

    /// @dev `count` operations from different users, all paid for by `app`.
    function _crowd(address paymaster, uint256 count)
        internal
        returns (PackedUserOperation[] memory ops)
    {
        ops = new PackedUserOperation[](count);
        for (uint256 i = 0; i < count; i++) {
            (SimpleAccount account, uint256 key) =
                _newAccount(string.concat("user", vm.toString(i)));
            ops[i] = _opFor(account, key, paymaster);
        }
    }

    function _solvent(BudgetLedger pm) internal view returns (bool) {
        return _depositOf(address(pm)) >= pm.totalBudgets();
    }

    /// @notice The control. Uncontended, every version keeps its ledger
    ///         covered, so what breaks below is contention and nothing else.
    function test_oneOperationAloneLeavesEveryVersionSolvent() public {
        BudgetLedger[3] memory all = [BudgetLedger(broken), reserving, bounded];
        for (uint256 i = 0; i < all.length; i++) {
            _handle(_crowd(address(all[i]), 1));
            assertTrue(_solvent(all[i]), "one operation on its own is paid for in full");
        }
    }

    /// @notice The bundle goes through, the app stops paying partway, and the
    ///         deposit no longer covers the budgets it holds. The difference is
    ///         the bystander app's money.
    function test_brokenLetsTheOverdrawLandOnAnotherApp() public {
        PackedUserOperation[] memory ops = _crowd(address(broken), OPS);
        _handle(ops);

        assertGt(broken.budgets(app), 0, "the app still shows budget left over");
        assertEq(
            target.lastNote(ops[OPS - 1].sender),
            "",
            "yet its last user's operation was rolled back"
        );
        assertEq(
            broken.budgets(bystander), BYSTANDER_BUDGET, "the ledger says the bystander is whole"
        );
        assertFalse(_solvent(broken), "but the deposit no longer covers the ledger");
    }

    /// @notice The reservation passes every check a bundler makes one operation
    ///         at a time, and then fails the bundle built from them.
    function test_reservingPassesEachOperationAloneButFailsTheBundle() public {
        PackedUserOperation[] memory ops = _crowd(address(reserving), 2);

        for (uint256 i = 0; i < ops.length; i++) {
            uint256 snapshot = vm.snapshotState();
            PackedUserOperation[] memory alone = new PackedUserOperation[](1);
            alone[0] = ops[i];
            _handle(alone);
            vm.revertToState(snapshot);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                1,
                "AA33 reverted",
                abi.encodeWithSelector(BudgetLedger.InsufficientBudget.selector, app, maxCost, 0)
            )
        );
        _handle(ops);
    }

    /// @notice With the owner's buffer in the deposit, the overdraw is paid
    ///         from it, and the other app's budget stays fully backed.
    function test_boundedKeepsTheOverdrawInTheOwnersBuffer() public {
        bounded.deposit{value: 0.01 ether}();
        uint256 bufferBefore = bounded.freeBalance();

        _handle(_crowd(address(bounded), OPS));

        assertEq(bounded.budgets(app), 0, "the app paid everything it had");
        assertTrue(_solvent(bounded), "the bystander's budget is still backed");
        assertLt(bounded.freeBalance(), bufferBefore, "the buffer paid the difference");
    }

    /// @notice The limit, stated as a test. Without a buffer the clamp has
    ///         nowhere to put the overdraw but the rest of the deposit.
    function test_theBoundNeedsTheBuffer() public {
        _handle(_crowd(address(bounded), OPS));
        assertFalse(_solvent(bounded), "no buffer: the overdraw reaches the bystander");
    }

    /// @notice None of the three runs a forbidden opcode. The reservation's
    ///         storage write is allowed for a staked paymaster; what gets it
    ///         banned is behaviour across a bundle, which no opcode check sees.
    function test_noOpcodeCheckCatchesAnyOfThem() public {
        (SimpleAccount account, uint256 key) = _newAccount("traced");
        address[3] memory all = [address(broken), address(reserving), address(bounded)];
        for (uint256 i = 0; i < all.length; i++) {
            assertEq(
                _bannedOpcodeInValidation(IPaymaster(all[i]), _opFor(account, key, all[i]), true),
                0,
                "no forbidden opcode"
            );
        }
    }
}
