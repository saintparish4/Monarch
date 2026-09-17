// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

import {MonarchPaymaster} from "../contracts/MonarchPaymaster.sol";
import {Constants} from "../contracts/libraries/Constants.sol";

/// @notice Deploy the paymaster against the canonical EntryPoint v0.8, stake it,
///         and fund the owner buffer — in one broadcast.
/// @dev Staking is part of deployment rather than a follow-up step because an
///      unstaked Monarch is not a paymaster anyone can use: sponsored mode reads
///      storage that is not sender-associated, and bundlers reject that from an
///      unstaked entity. A deploy that stops before `addStake` leaves a contract
///      on-chain that looks finished and sponsors nothing.
///
///      Amounts come from the environment so a testnet deploy can start small
///      and top up. `addStake` is additive, so raising the stake later is one
///      call; the unstake delay can only ever be increased.
///
///      forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast
contract Deploy is Script {
    function run() external returns (MonarchPaymaster paymaster) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 stake = vm.envOr("STAKE_WEI", uint256(0.01 ether));
        uint32 unstakeDelay = uint32(vm.envOr("UNSTAKE_DELAY_SEC", uint256(1 days)));
        // The buffer absorbs the one case where `postOp` clamps a charge: a
        // bundle that overdraws an app across several operations. Owner money,
        // withdrawable at any time through `withdrawTo`.
        uint256 ownerBuffer = vm.envOr("OWNER_BUFFER_WEI", uint256(0.001 ether));

        vm.startBroadcast(deployerKey);
        paymaster = new MonarchPaymaster(IEntryPoint(Constants.ENTRY_POINT_V8));
        paymaster.addStake{value: stake}(unstakeDelay);
        paymaster.deposit{value: ownerBuffer}();
        vm.stopBroadcast();

        console.log("MonarchPaymaster", address(paymaster));
        console.log("owner", paymaster.owner());
        console.log("stake (wei)", stake);
        console.log("unstake delay (s)", uint256(unstakeDelay));
        console.log("free balance (wei)", paymaster.freeBalance());
    }
}
