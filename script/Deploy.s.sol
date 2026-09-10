// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

import {MonarchPaymaster} from "../contracts/MonarchPaymaster.sol";
import {Guestbook} from "./demo/Guestbook.sol";
import {Constants} from "../contracts/libraries/Constants.sol";

/// @title Deploy
/// @notice Brings a Monarch paymaster all the way to "a bundler will accept an
///         operation through it" in one transaction batch.
///
/// @dev A paymaster is not usable the moment it is deployed, and every step
///      below is load-bearing:
///
///        1. deploy
///        2. `addStake`  — sponsored mode reads `apps[app]`, which is keyed by
///           an address from calldata rather than by `userOp.sender`. That is
///           not sender-associated storage, so under ERC-7562 an *unstaked*
///           paymaster doing it is rejected by every bundler. Deploying without
///           staking produces a paymaster that passes its own tests and is then
///           silently dropped from every mempool.
///        3. `deposit`   — the EntryPoint pays the bundler out of this balance.
///           Stake and deposit are different pots; funding one is not funding
///           the other.
///        4. `registerApp` / `fundApp` — the app's budget, which is what
///           `postOp` actually charges.
///
///      Steps 2 and 3 are the two that are easy to skip and produce a deployment
///      that looks healthy on a block explorer and works for nobody.
contract Deploy is Script {
    /// @dev The EntryPoint's minimum for a paymaster to be treated as staked by
    ///      the reference bundler. Raising it does not buy more throughput.
    uint32 internal constant DEFAULT_UNSTAKE_DELAY = 1 days;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address app = vm.envAddress("APP_ADDRESS");
        address appSigner = vm.envAddress("APP_SIGNER_ADDRESS");

        uint256 stake = vm.envOr("STAKE_WEI", uint256(0.01 ether));
        uint256 depositAmount = vm.envOr("DEPOSIT_WEI", uint256(0.02 ether));
        uint256 budget = vm.envOr("APP_BUDGET_WEI", uint256(0.02 ether));
        uint32 unstakeDelay = uint32(vm.envOr("UNSTAKE_DELAY_SEC", uint256(DEFAULT_UNSTAKE_DELAY)));

        address deployer = vm.addr(deployerKey);
        uint256 required = stake + depositAmount + budget;
        if (deployer.balance < required) {
            console2.log("Deployer:        ", deployer);
            console2.log("Balance (wei):   ", deployer.balance);
            console2.log("Required (wei):  ", required);
            revert("deployer balance below stake + deposit + budget");
        }

        vm.startBroadcast(deployerKey);

        MonarchPaymaster paymaster = new MonarchPaymaster(IEntryPoint(Constants.ENTRY_POINT_V8));

        paymaster.addStake{value: stake}(unstakeDelay);
        paymaster.deposit{value: depositAmount}();
        paymaster.registerApp(app, appSigner);
        paymaster.fundApp{value: budget}(app);

        // The demo's target. Deployed here so one command produces a working
        // end-to-end demo rather than a paymaster with nothing to point at.
        Guestbook guestbook = new Guestbook();

        vm.stopBroadcast();

        // Read back rather than trusting the calls above: this is the same
        // solvency identity the invariant suite enforces, checked against the
        // chain we just wrote to.
        uint256 entryPointBalance = paymaster.getDeposit();
        uint256 owed = paymaster.totalUserDeposits() + paymaster.totalAppBudgets();

        console2.log("");
        console2.log("=== Monarch deployed ===");
        console2.log("Paymaster:            ", address(paymaster));
        console2.log("EntryPoint:           ", Constants.ENTRY_POINT_V8);
        console2.log("Owner:                ", deployer);
        console2.log("App:                  ", app);
        console2.log("App signer:           ", appSigner);
        console2.log("Stake (wei):          ", stake);
        console2.log("EntryPoint deposit:   ", entryPointBalance);
        console2.log("Owed to users + apps: ", owed);
        console2.log("Free balance:         ", paymaster.freeBalance());
        console2.log("");
        console2.log("Guestbook:            ", address(guestbook));
        console2.log("");
        console2.log("Copy these two lines into demo/.env:");
        console2.log("VITE_PAYMASTER_ADDRESS=", address(paymaster));
        console2.log("VITE_GUESTBOOK_ADDRESS=", address(guestbook));

        require(entryPointBalance >= owed, "solvency identity violated at deploy");
    }
}
