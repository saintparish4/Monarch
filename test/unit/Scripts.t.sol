// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {RegisterApp} from "../../script/RegisterApp.s.sol";
import {TestnetOnly} from "../../script/TestnetOnly.sol";

/// @notice The deploy scripts refuse every chain but Base Sepolia and anvil.
/// @dev The guard runs before the scripts read a single environment variable,
///      so the refusals need no key. The one positive case deploys for real, in
///      the test VM, to show the guard admits the chain it is meant to.
contract ScriptsTest is Test {
    uint256 internal constant BASE_MAINNET = 8453;
    uint256 internal constant ETHEREUM_MAINNET = 1;

    function test_deployScriptCannotRunOnBaseMainnet() public {
        vm.chainId(BASE_MAINNET);
        Deploy script = new Deploy();
        vm.expectRevert(abi.encodeWithSelector(TestnetOnly.NotATestnet.selector, BASE_MAINNET));
        script.run();
    }

    function test_deployScriptCannotRunOnEthereumMainnet() public {
        vm.chainId(ETHEREUM_MAINNET);
        Deploy script = new Deploy();
        vm.expectRevert(abi.encodeWithSelector(TestnetOnly.NotATestnet.selector, ETHEREUM_MAINNET));
        script.run();
    }

    function test_registerAppScriptCannotRunOnBaseMainnet() public {
        vm.chainId(BASE_MAINNET);
        RegisterApp script = new RegisterApp();
        vm.expectRevert(abi.encodeWithSelector(TestnetOnly.NotATestnet.selector, BASE_MAINNET));
        script.run();
    }

    function test_deployScriptRunsOnBaseSepolia() public {
        vm.chainId(84_532);
        vm.etch(Constants.ENTRY_POINT_V8, address(new EntryPoint()).code);
        (address deployer, uint256 key) = makeAddrAndKey("deployer");
        vm.deal(deployer, 1 ether);
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(bytes32(key)));

        MonarchPaymaster paymaster = new Deploy().run();

        assertEq(paymaster.owner(), deployer, "the deployer owns the paymaster");
        assertEq(paymaster.freeBalance(), 0.001 ether, "the owner buffer was funded");
    }
}
