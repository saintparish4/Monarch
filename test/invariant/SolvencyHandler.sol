// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";

/// @title SolvencyHandler
/// @notice Bounded random actions against MonarchPaymaster for the invariant run.
/// @dev Why a handler at all: unbounded fuzzing of `withdrawUserDeposit` with a
///      random `amount` reverts on the balance check essentially every time, so
///      the run never explores a partially-drained paymaster — the only state
///      where solvency could plausibly break.
///
///      `postOp` is driven directly rather than through `handleOps` because the
///      property under test is the paymaster's accounting, not the EntryPoint's
///      bundling. The integration suite covers the real path.
///
///      Every action guards its own preconditions and returns early rather than
///      reverting, which is what lets the run use `fail_on_revert = true`. With
///      it off, a handler that reverted on every call would still report a
///      green run.
contract SolvencyHandler is CommonBase, StdCheats, StdUtils {
    MonarchPaymaster public immutable paymaster;
    EntryPoint public immutable entryPoint;

    address[] public actors;
    address[] public registeredApps;

    /// @notice Total value ever charged through postOp. Ghost variable — read
    ///         by the invariants, never by the contract under test.
    uint256 public ghost_totalCharged;
    /// @notice Total value ever paid in through `depositFor` and `fundApp`.
    uint256 public ghost_totalDeposited;
    /// @notice Total value ever taken back out by users and apps.
    uint256 public ghost_totalWithdrawn;
    /// @notice Smallest balance any actor or app held after an owner action,
    ///         used to prove the owner never reduces anyone else's balance.
    bool public ghost_ownerTouchedSomeoneElse;

    constructor(
        MonarchPaymaster _paymaster,
        EntryPoint _entryPoint,
        address[] memory _actors,
        address[] memory _apps
    ) {
        paymaster = _paymaster;
        entryPoint = _entryPoint;
        actors = _actors;
        registeredApps = _apps;
    }

    function depositFor(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 0.0001 ether, 10 ether);
        deal(address(this), address(this).balance + amount);
        paymaster.depositFor{value: amount}(actor);
        ghost_totalDeposited += amount;
    }

    function withdrawUserDeposit(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 balance = paymaster.userDeposits(actor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vm.prank(actor);
        paymaster.withdrawUserDeposit(payable(actor), amount);
        ghost_totalWithdrawn += amount;
    }

    function fundApp(uint256 appSeed, uint256 amount) external {
        address which = _app(appSeed);
        amount = bound(amount, 1, 10 ether);
        deal(address(this), address(this).balance + amount);
        paymaster.fundApp{value: amount}(which);
        ghost_totalDeposited += amount;
    }

    function withdrawAppBudget(uint256 appSeed, uint256 amount) external {
        address which = _app(appSeed);
        (uint96 budget,) = paymaster.apps(which);
        if (budget == 0) return;
        amount = bound(amount, 1, budget);
        vm.prank(which);
        paymaster.withdrawAppBudget(payable(which), amount);
        ghost_totalWithdrawn += amount;
    }

    function setAppSigner(uint256 appSeed, uint256 signerSeed) external {
        address which = _app(appSeed);
        address newSigner = address(uint160(bound(signerSeed, 1, type(uint160).max)));
        vm.prank(which);
        paymaster.setAppSigner(newSigner);
    }

    function chargeUser(uint256 actorSeed, uint256 gasCost) external {
        address actor = _actor(actorSeed);
        uint256 available = paymaster.userDeposits(actor);
        if (available == 0) return;
        // Validation already proved the payer covered `maxCost`, and the
        // EntryPoint never charges more than it prefunded. A handler that
        // charged beyond the balance would be modelling something the protocol
        // cannot do, and would break solvency by construction rather than by
        // finding a bug.
        gasCost = bound(gasCost, 0, available);
        _charge(abi.encode(MonarchPaymaster.Mode.Deposit, actor, address(0)), gasCost);
    }

    function chargeApp(uint256 appSeed, uint256 actorSeed, uint256 gasCost) external {
        address which = _app(appSeed);
        address actor = _actor(actorSeed);
        (uint96 budget,) = paymaster.apps(which);
        if (budget == 0) return;
        gasCost = bound(gasCost, 0, budget);
        _charge(abi.encode(MonarchPaymaster.Mode.Sponsored, actor, which), gasCost);
    }

    /// @notice Two charges against one pre-read budget, the shape a bundle has.
    /// @dev The sequential actions above cannot reach this state, which is
    ///      exactly why the limitation it models went unnoticed by reading.
    ///      Both charges are sized against the budget as it stood before either
    ///      ran, because that is what both validations saw. The second is only
    ///      attempted when the free buffer could have covered its prefund, which
    ///      is the condition the EntryPoint enforces before letting the bundle
    ///      run at all.
    function chargeAppTwice(uint256 appSeed, uint256 actorSeed, uint256 gasCost) external {
        address which = _app(appSeed);
        address actor = _actor(actorSeed);
        (uint96 budget,) = paymaster.apps(which);
        if (budget == 0) return;
        gasCost = bound(gasCost, 0, budget);

        bytes memory context = abi.encode(MonarchPaymaster.Mode.Sponsored, actor, which);
        _charge(context, gasCost);
        if (paymaster.freeBalance() < gasCost) return;
        _charge(context, gasCost);
    }

    /// @notice The owner sweeping the excess — the action most likely to break
    ///         solvency if `withdrawTo` had no check.
    function ownerWithdraw(uint256 amount) external {
        uint256 free = paymaster.freeBalance();
        if (free == 0) return;
        amount = bound(amount, 1, free);

        uint256[] memory userBefore = _userBalances();
        uint256[] memory appBefore = _appBudgets();

        // Cache the owner first. `vm.prank` applies to the next call, and
        // evaluating `paymaster.owner()` inside the argument list would consume
        // it — leaving the withdrawal to come from this handler, revert on
        // `onlyOwner`, and make the invariant below pass vacuously.
        address payable ownerAddr = payable(paymaster.owner());
        vm.prank(ownerAddr);
        paymaster.withdrawTo(ownerAddr, amount);

        if (_anyDecreased(userBefore, _userBalances()) || _anyDecreased(appBefore, _appBudgets())) {
            ghost_ownerTouchedSomeoneElse = true;
        }
    }

    /// @notice The owner topping up the buffer.
    function ownerDeposit(uint256 amount) external {
        amount = bound(amount, 1, 10 ether);
        deal(address(this), address(this).balance + amount);
        paymaster.deposit{value: amount}();
    }

    function addStake(uint256 amount) external {
        amount = bound(amount, 1, 5 ether);
        address ownerAddr = paymaster.owner();
        deal(ownerAddr, ownerAddr.balance + amount);
        vm.prank(ownerAddr);
        paymaster.addStake{value: amount}(1 days);
    }

    function _charge(bytes memory context, uint256 gasCost) internal {
        // Mirror what the EntryPoint does: it deducts the gas from the
        // paymaster's deposit and then calls postOp. Skipping the deduction
        // would make solvency trivially true.
        uint256 deposited = entryPoint.balanceOf(address(paymaster));
        if (gasCost > deposited) return;

        vm.prank(address(paymaster));
        entryPoint.withdrawTo(payable(address(this)), gasCost);

        uint256 reservedBefore = paymaster.totalUserDeposits() + paymaster.totalAppBudgets();
        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, gasCost, 0);
        // The ledger debit, not the gas cost. When the clamp fires these differ,
        // and conservation is a statement about the ledger.
        ghost_totalCharged += reservedBefore
            - (paymaster.totalUserDeposits() + paymaster.totalAppBudgets());
    }

    function _userBalances() internal view returns (uint256[] memory out) {
        out = new uint256[](actors.length);
        for (uint256 i = 0; i < actors.length; i++) {
            out[i] = paymaster.userDeposits(actors[i]);
        }
    }

    function _appBudgets() internal view returns (uint256[] memory out) {
        out = new uint256[](registeredApps.length);
        for (uint256 i = 0; i < registeredApps.length; i++) {
            (uint96 budget,) = paymaster.apps(registeredApps[i]);
            out[i] = budget;
        }
    }

    function _anyDecreased(uint256[] memory before, uint256[] memory next)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < before.length; i++) {
            if (next[i] < before[i]) return true;
        }
        return false;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _app(uint256 seed) internal view returns (address) {
        return registeredApps[bound(seed, 0, registeredApps.length - 1)];
    }

    receive() external payable {}
}
