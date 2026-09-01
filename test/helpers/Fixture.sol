// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {UserOpBuilder} from "./UserOpBuilder.sol";

/// @notice Shared setup: a real EntryPoint, a paymaster, one registered app.
/// @dev The EntryPoint is the genuine v0.8 contract deployed into the test VM,
///      not a mock. A mock would agree with whatever I believe about the
///      interface, and being wrong about that interface is the bug class this
///      contract was rewritten to remove.
abstract contract Fixture is Test {
    EntryPoint internal entryPoint;
    MonarchPaymaster internal paymaster;

    address internal owner = makeAddr("owner");
    address internal app = makeAddr("app");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    address internal appSigner;
    uint256 internal appSignerKey;

    function setUp() public virtual {
        (appSigner, appSignerKey) = makeAddrAndKey("appSigner");

        entryPoint = new EntryPoint();

        vm.prank(owner);
        paymaster = new MonarchPaymaster(IEntryPoint(address(entryPoint)));

        vm.prank(owner);
        paymaster.registerApp(app, appSigner);

        vm.deal(owner, 100 ether);
        vm.deal(app, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    /// @dev Fund an app's budget from the app's own pocket.
    function _fundApp(address which, uint256 amount) internal {
        vm.deal(which, which.balance + amount);
        vm.prank(which);
        paymaster.fundApp{value: amount}(which);
    }

    /// @dev A Deposit-mode op for `sender`.
    function _depositOp(address sender) internal view returns (PackedUserOperation memory op) {
        op = UserOpBuilder.base(sender, 0, "");
        op.paymasterAndData = UserOpBuilder.depositData(address(paymaster));
    }

    /// @dev A Sponsored-mode op, signed by `key` on behalf of `sponsorApp`.
    function _sponsoredOp(
        address sender,
        address sponsorApp,
        uint256 key,
        uint48 validUntil,
        uint48 validAfter
    ) internal view returns (PackedUserOperation memory op) {
        op = UserOpBuilder.base(sender, 0, "");
        bytes memory prefix =
            UserOpBuilder.sponsoredPrefix(address(paymaster), sponsorApp, validUntil, validAfter);
        op.paymasterAndData = prefix;
        op.paymasterAndData = UserOpBuilder.withSignature(prefix, _signSponsorship(op, key));
    }

    function _signSponsorship(PackedUserOperation memory op, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(paymaster.getSponsorshipHash(op));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Call validation the way the EntryPoint does.
    function _validate(PackedUserOperation memory op, uint256 maxCost)
        internal
        returns (bytes memory context, uint256 validationData)
    {
        vm.prank(address(entryPoint));
        return paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    /// @dev Call postOp the way the EntryPoint does.
    function _postOp(bytes memory context, uint256 actualGasCost, uint256 feePerGas) internal {
        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost, feePerGas);
    }

    function _reserved() internal view returns (uint256) {
        return paymaster.totalUserDeposits() + paymaster.totalAppBudgets();
    }

    function _assertSolvent(string memory what) internal view {
        assertGe(entryPoint.balanceOf(address(paymaster)), _reserved(), what);
    }
}
