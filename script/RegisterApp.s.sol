// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {MonarchPaymaster} from "../contracts/MonarchPaymaster.sol";

/// @notice Register an app on a deployed paymaster and fund its budget.
/// @dev Two parties with two keys. The owner registers, because registration is
///      owner-gated. The app's *signer* is a separate hot key held by the app's
///      backend, and only its address is needed here — the script never needs
///      the signer's private key, so it never reads it.
///
///      For the demo the app address is the deployer's own, which keeps the
///      app's withdraw and signer-rotation rights with a key I already hold.
///
///      PAYMASTER=0x... APP_SIGNER=0x... \
///        forge script script/RegisterApp.s.sol --rpc-url base_sepolia --broadcast
contract RegisterApp is Script {
    function run() external {
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        MonarchPaymaster paymaster = MonarchPaymaster(vm.envAddress("PAYMASTER"));
        address app = vm.envOr("APP", vm.addr(ownerKey));
        address signer = vm.envAddress("APP_SIGNER");
        uint256 budget = vm.envOr("APP_BUDGET_WEI", uint256(0.005 ether));

        vm.startBroadcast(ownerKey);
        paymaster.registerApp(app, signer);
        paymaster.fundApp{value: budget}(app);
        vm.stopBroadcast();

        (uint96 appBudget, address appSigner) = paymaster.apps(app);
        console.log("app", app);
        console.log("signer", appSigner);
        console.log("budget (wei)", uint256(appBudget));
    }
}
