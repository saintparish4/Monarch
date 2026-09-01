// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IStakeManager} from "account-abstraction/interfaces/IStakeManager.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {SolvencyHandler} from "./SolvencyHandler.sol";

/// @notice The properties that have to hold after any reachable sequence.
/// @dev The actor and app sets are deliberately tiny (3 and 2). A large set
///      spreads the run thin across accounts each touched once; a small one
///      drives repeated deposit/charge/withdraw sequences against the same
///      balances, which is where an accounting error shows.
contract SolvencyInvariantTest is Test {
    EntryPoint internal entryPoint;
    MonarchPaymaster internal paymaster;
    SolvencyHandler internal handler;

    address internal owner = makeAddr("owner");
    address[] internal actors;
    address[] internal apps;

    function setUp() public {
        entryPoint = new EntryPoint();

        vm.prank(owner);
        paymaster = new MonarchPaymaster(IEntryPoint(address(entryPoint)));

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));

        apps.push(makeAddr("appOne"));
        apps.push(makeAddr("appTwo"));
        for (uint256 i = 0; i < apps.length; i++) {
            vm.prank(owner);
            paymaster.registerApp(apps[i], makeAddr(string.concat("signer", vm.toString(i))));
        }

        handler = new SolvencyHandler(paymaster, entryPoint, actors, apps);
        targetContract(address(handler));
    }

    /// @notice P1. The property everything else exists to protect.
    function invariant_entryPointBalanceCoversAllClaims() public view {
        assertGe(
            entryPoint.balanceOf(address(paymaster)),
            paymaster.totalUserDeposits() + paymaster.totalAppBudgets(),
            "entryPoint balance must cover every deposit and budget"
        );
    }

    /// @notice P2 and P3. The running totals may not drift from what they sum.
    /// @dev Only checkable because the actor and app sets are bounded and known;
    ///      there is no way to enumerate a mapping on-chain, which is why the
    ///      contract keeps running totals in the first place.
    function invariant_runningTotalsMatchTheirParts() public view {
        uint256 userSum;
        for (uint256 i = 0; i < actors.length; i++) {
            userSum += paymaster.userDeposits(actors[i]);
        }
        assertEq(userSum, paymaster.totalUserDeposits(), "totalUserDeposits drifted");

        uint256 appSum;
        for (uint256 i = 0; i < apps.length; i++) {
            (uint96 budget,) = paymaster.apps(apps[i]);
            appSum += budget;
        }
        assertEq(appSum, paymaster.totalAppBudgets(), "totalAppBudgets drifted");
    }

    /// @notice P4. `freeBalance()` must never promise more than is actually free.
    function invariant_freeBalanceIsWithdrawable() public view {
        uint256 free = paymaster.freeBalance();
        uint256 balance = entryPoint.balanceOf(address(paymaster));
        uint256 reserved = paymaster.totalUserDeposits() + paymaster.totalAppBudgets();
        assertLe(free, balance, "free exceeds the actual balance");
        assertEq(free, balance > reserved ? balance - reserved : 0, "free is mis-stated");
    }

    /// @notice P5. No owner action reduces a user's balance or an app's budget.
    /// @dev Solvency is an inequality, so it would still hold if the owner
    ///      quietly took from a user and left a surplus. This says they cannot.
    function invariant_ownerCannotReduceAnyoneElsesBalance() public view {
        assertFalse(
            handler.ghost_ownerTouchedSomeoneElse(),
            "an owner action reduced a balance that was not theirs"
        );
    }

    /// @notice P6. Value is conserved: everything paid in is held, spent or free.
    /// @dev Stronger than solvency, which is only an inequality and is satisfied
    ///      forever by a paymaster that quietly overcharges into the excess.
    function invariant_valueIsConserved() public view {
        uint256 held = paymaster.totalUserDeposits() + paymaster.totalAppBudgets();
        assertEq(
            handler.ghost_totalDeposited(),
            held + handler.ghost_totalWithdrawn() + handler.ghost_totalCharged(),
            "value appeared or vanished"
        );
    }

    /// @notice The stake is a separate pot and never counts as free.
    function invariant_stakeIsNotSpendable() public view {
        IStakeManager.DepositInfo memory info = entryPoint.getDepositInfo(address(paymaster));
        assertLe(
            paymaster.freeBalance(),
            info.deposit,
            "free balance must come from the deposit, never the stake"
        );
    }
}
