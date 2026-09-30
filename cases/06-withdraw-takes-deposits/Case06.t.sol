// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";

import {CaseTest} from "../shared/CaseTest.sol";
import {PooledDepositPaymaster} from "./Broken.sol";
import {SolventDepositPaymaster} from "./Fixed.sol";

/// @notice Case 06: withdrawing against the raw EntryPoint balance takes users'
///         deposits.
contract Case06Test is CaseTest {
    uint256 internal constant USER_DEPOSIT = 1 ether;
    uint256 internal constant OWNERS_OWN = 0.1 ether;

    PooledDepositPaymaster internal broken;
    SolventDepositPaymaster internal fixed_;

    address payable internal owner = payable(makeAddr("owner"));
    address payable internal user = payable(makeAddr("user"));

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        broken = new PooledDepositPaymaster(IEntryPoint(address(entryPoint)));
        fixed_ = new SolventDepositPaymaster(IEntryPoint(address(entryPoint)));
        vm.stopPrank();

        vm.deal(user, 10 ether);
        vm.deal(owner, 10 ether);
        vm.prank(user);
        broken.depositFor{value: USER_DEPOSIT}(user);
        vm.prank(user);
        fixed_.depositFor{value: USER_DEPOSIT}(user);
        vm.prank(owner);
        broken.deposit{value: OWNERS_OWN}();
        vm.prank(owner);
        fixed_.deposit{value: OWNERS_OWN}();
    }

    /// @notice The owner asks for the whole pot, and gets it.
    function test_brokenOwnerCanWithdrawTheUsersDeposit() public {
        vm.prank(owner);
        broken.withdrawTo(owner, USER_DEPOSIT + OWNERS_OWN);

        assertEq(_depositOf(address(broken)), 0, "the pot is empty");
        assertEq(broken.deposits(user), USER_DEPOSIT, "the ledger still says the user has 1 ETH");

        vm.expectRevert("Withdraw amount too large");
        vm.prank(user);
        broken.withdrawDeposit(user, USER_DEPOSIT);
    }

    function test_fixedOwnerCannotWithdrawTheUsersDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SolventDepositPaymaster.WouldBreakSolvency.selector,
                USER_DEPOSIT + OWNERS_OWN,
                OWNERS_OWN
            )
        );
        vm.prank(owner);
        fixed_.withdrawTo(owner, USER_DEPOSIT + OWNERS_OWN);
    }

    function test_fixedOwnerCanStillWithdrawTheirOwn() public {
        vm.prank(owner);
        fixed_.withdrawTo(owner, OWNERS_OWN);

        vm.prank(user);
        fixed_.withdrawDeposit(user, USER_DEPOSIT);
        assertEq(_depositOf(address(fixed_)), 0, "both withdrew exactly what was theirs");
    }

    /// @notice Validation is not where this bug lives, so nothing that
    ///         inspects validation can find it.
    function test_noOpcodeCheckCatchesTheBrokenVersion() public {
        (SimpleAccount account, uint256 key) = _newAccount("sender");
        broken.depositFor{value: USER_DEPOSIT}(address(account));
        PackedUserOperation memory op = _op(account, "paid");
        op.paymasterAndData = _paymasterAndData(address(broken), PAYMASTER_POSTOP_GAS, "");
        op = _signAsAccount(op, key);

        assertEq(
            _bannedOpcodeInValidation(IPaymaster(address(broken)), op, true),
            0,
            "no forbidden opcode"
        );
        _handle(op);
        assertEq(target.lastNote(address(account)), "paid", "and it works as a paymaster");
    }
}
