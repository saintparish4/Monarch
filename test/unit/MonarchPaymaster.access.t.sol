// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IStakeManager} from "account-abstraction/interfaces/IStakeManager.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Validation} from "../../contracts/libraries/Validation.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {Guestbook} from "../helpers/Adversary.sol";

/// @notice Who can do what to whom.
/// @dev One test per "cannot" in the trust model. Keeping them in one file makes
///      the completeness argument mechanical: the file should have as many tests
///      as the trust model has rows, and a row added without a test is a diff I
///      reject. The admin paths that carry no capability claim are here too,
///      because they are the same surface.
contract MonarchPaymasterAccessTest is Fixture {
    // ------------------------------------------------------------ the owner

    function test_ownerCannotSetAnAppSigner() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.AppNotRegistered.selector, owner));
        paymaster.setAppSigner(makeAddr("attacker"));
    }

    function test_ownerCannotWithdrawToTheZeroAddress() public {
        vm.prank(owner);
        paymaster.deposit{value: 1 ether}();
        vm.prank(owner);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.withdrawTo(payable(address(0)), 1 ether);
    }

    function test_nonOwnerCannotRegisterApps() public {
        vm.prank(alice);
        vm.expectRevert();
        paymaster.registerApp(makeAddr("x"), makeAddr("y"));
    }

    function test_nonOwnerCannotWithdrawTheFreeBalance() public {
        vm.prank(owner);
        paymaster.deposit{value: 1 ether}();
        vm.prank(alice);
        vm.expectRevert();
        paymaster.withdrawTo(payable(alice), 1 ether);
    }

    function test_registerApp_rejectsZeroAddresses() public {
        vm.prank(owner);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.registerApp(address(0), appSigner);

        vm.prank(owner);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.registerApp(makeAddr("newApp"), address(0));
    }

    // -------------------------------------------------------------- the app

    function test_appCannotSpendAnotherAppsBudget() public {
        address other = makeAddr("otherApp");
        vm.prank(owner);
        paymaster.registerApp(other, makeAddr("otherSigner"));
        _fundApp(other, 3 ether);

        vm.prank(app);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.InsufficientAppBudget.selector, app, 1 ether, 0)
        );
        paymaster.withdrawAppBudget(payable(app), 1 ether);

        (uint96 otherBudget,) = paymaster.apps(other);
        assertEq(otherBudget, 3 ether, "the other app is untouched");
    }

    function test_appCannotTouchUserDeposits() public {
        vm.prank(alice);
        paymaster.depositFor{value: 2 ether}(alice);

        // The only withdrawal an app can make is against its own budget.
        vm.prank(app);
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.InsufficientUserDeposit.selector, app, 1 ether, 0
            )
        );
        paymaster.withdrawUserDeposit(payable(app), 1 ether);

        assertEq(paymaster.userDeposits(alice), 2 ether, "alice is untouched");
    }

    function test_appCannotSelfRegister() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert();
        paymaster.registerApp(stranger, stranger);
    }

    function test_unregisteredAppCannotWithdraw() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(MonarchPaymaster.AppNotRegistered.selector, stranger)
        );
        paymaster.withdrawAppBudget(payable(stranger), 1);
    }

    function test_withdrawAppBudget_rejectsZeroAddress() public {
        _fundApp(app, 1 ether);
        vm.prank(app);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.withdrawAppBudget(payable(address(0)), 1);
    }

    function test_setAppSigner_rejectsZeroAddress() public {
        vm.prank(app);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.setAppSigner(address(0));
    }

    // ------------------------------------------------------------- the user

    function test_userCannotWithdrawAnotherUsersDeposit() public {
        vm.prank(alice);
        paymaster.depositFor{value: 2 ether}(alice);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                MonarchPaymaster.InsufficientUserDeposit.selector, bob, 1 ether, 0
            )
        );
        paymaster.withdrawUserDeposit(payable(bob), 1 ether);

        assertEq(paymaster.userDeposits(alice), 2 ether, "alice keeps her money");
    }

    function test_withdrawUserDeposit_rejectsZeroAddress() public {
        vm.prank(alice);
        paymaster.depositFor{value: 1 ether}(alice);
        vm.prank(alice);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.withdrawUserDeposit(payable(address(0)), 1);
    }

    // ------------------------------------------------------------- the stake

    function test_stakeLifecycle() public {
        vm.prank(owner);
        paymaster.addStake{value: 1 ether}(1 days);

        IStakeManager.DepositInfo memory staked = entryPoint.getDepositInfo(address(paymaster));
        assertEq(staked.stake, 1 ether, "staked");
        assertTrue(staked.staked, "and marked as such");
        assertEq(paymaster.freeBalance(), 0, "the stake is not the deposit");

        vm.prank(owner);
        paymaster.unlockStake();

        vm.warp(block.timestamp + 1 days + 1);
        uint256 before = owner.balance;
        vm.prank(owner);
        paymaster.withdrawStake(payable(owner));
        assertEq(owner.balance, before + 1 ether, "the stake came back after the delay");
        _assertSolvent("solvency across the stake lifecycle");
    }

    function test_withdrawStake_rejectsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Validation.ZeroAddress.selector);
        paymaster.withdrawStake(payable(address(0)));
    }

    // -------------------------------------------------------------- the rest

    function test_getDepositReportsTheWholePot() public {
        vm.prank(alice);
        paymaster.depositFor{value: 2 ether}(alice);
        _fundApp(app, 3 ether);
        vm.prank(owner);
        paymaster.deposit{value: 1 ether}();

        assertEq(paymaster.getDeposit(), 6 ether, "everything, claimed or not");
        assertEq(paymaster.freeBalance(), 1 ether, "of which only the buffer is free");
    }

    /// @dev The budget is a uint96 so it packs beside the signer in one slot.
    ///      Anything that would not fit has to be refused rather than truncated:
    ///      a silent wrap here would credit an app almost nothing and let it
    ///      spend against a total the running sum still believes.
    function test_fundApp_refusesABudgetThatWouldNotFit() public {
        uint256 max = type(uint96).max;
        vm.deal(alice, max + 1 ether);

        vm.prank(alice);
        paymaster.fundApp{value: max}(app);
        (uint96 budget,) = paymaster.apps(app);
        assertEq(budget, max, "exactly at the ceiling is fine");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MonarchPaymaster.BudgetOverflow.selector, max + 1));
        paymaster.fundApp{value: 1}(app);
    }

    /// @dev A contract that is not an EntryPoint passes the code-size guard and
    ///      has to be caught by the interface check instead.
    function test_constructorRejectsAContractThatIsNotAnEntryPoint() public {
        Guestbook notAnEntryPoint = new Guestbook();
        vm.expectRevert();
        new MonarchPaymaster(IEntryPoint(address(notAnEntryPoint)));
    }
}
