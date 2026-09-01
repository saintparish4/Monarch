// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {UserOpBuilder} from "../helpers/UserOpBuilder.sol";

/// @notice What the sponsorship signature does and does not commit to.
/// @dev This is the entire authorisation for sponsored mode, and which fields it
///      covers is a design claim that reading the code does not verify. Every
///      test here changes exactly one thing after signing and asserts the
///      signature stops matching.
contract MonarchPaymasterSignaturesTest is Fixture {
    /// @dev secp256k1 group order, for constructing the malleable counterpart of
    ///      a valid signature.
    uint256 internal constant N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function setUp() public override {
        super.setUp();
        _fundApp(app, 10 ether);
    }

    function test_malleableSignature_isRejected() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);

        // The original is accepted.
        (, uint256 ok) = _validate(op, 1 ether);
        assertEq(ok & 1, 0, "the honest signature works");

        // (r, N - s, v ^ 1) recovers the same key on a naive implementation.
        bytes memory sig = _tail(op.paymasterAndData);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        bytes memory malleable = abi.encodePacked(r, bytes32(N - uint256(s)), v == 27 ? 28 : 27);

        op.paymasterAndData = UserOpBuilder.withSignature(_prefix(op.paymasterAndData), malleable);
        (bytes memory context, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData & 1, 1, "the malleable twin is rejected");
        assertEq(context.length, 0, "and buys nothing");
    }

    function test_garbageSignature_recoversNoOneAndFails() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        // v = 0 is not a legal recovery id. `ecrecover` answers address(0),
        // which is also the "app not registered" sentinel — the pair of facts
        // that makes this the classic way a paymaster becomes universally
        // drainable. Registration is checked first, and `tryRecover` reports an
        // error rather than returning zero, so neither road leads anywhere.
        bytes memory garbage = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(1)), uint8(0));
        op.paymasterAndData = UserOpBuilder.withSignature(_prefix(op.paymasterAndData), garbage);

        (bytes memory context, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 1, "no recovery, no sponsorship");
        assertEq(context.length, 0, "and no context");
    }

    function test_signatureIsBoundToChainId() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        (, uint256 ok) = _validate(op, 1 ether);
        assertEq(ok & 1, 0, "valid on this chain");

        vm.chainId(block.chainid + 1);
        (, uint256 elsewhere) = _validate(op, 1 ether);
        assertEq(elsewhere & 1, 1, "and worthless on another");
    }

    function test_signatureIsBoundToThisPaymaster() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);

        vm.prank(owner);
        MonarchPaymaster second = new MonarchPaymaster(IEntryPoint(address(entryPoint)));
        vm.prank(owner);
        second.registerApp(app, appSigner);
        vm.deal(app, 10 ether);
        vm.prank(app);
        second.fundApp{value: 5 ether}(app);

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            second.validatePaymasterUserOp(op, bytes32(0), 1 ether);

        assertEq(validationData & 1, 1, "a sponsorship for one paymaster is not good at another");
        assertEq(context.length, 0, "and buys nothing there");
    }

    function test_signatureIsBoundToNonce() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        (, uint256 ok) = _validate(op, 1 ether);
        assertEq(ok & 1, 0, "valid at the nonce it was signed for");

        op.nonce = 1;
        (, uint256 replayed) = _validate(op, 1 ether);
        assertEq(replayed & 1, 1, "and cannot be replayed at the next one");
    }

    function test_signatureIsBoundToTheSender() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        op.sender = bob;
        (, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 1, "a sponsorship names one user, not any user");
    }

    function test_signatureCoversCallData() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        op.callData = hex"deadbeef";
        (, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 1, "a sponsorship authorises one operation, not one sender");
    }

    function test_signatureCoversTheAccountGasLimits() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        op.accountGasLimits = UserOpBuilder.packLimits(900_000, 900_000);
        (, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 1, "a bundler cannot inflate the gas after the app signed");
    }

    function test_signatureCoversBothPaymasterGasLimits() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        bytes memory data = op.paymasterAndData;

        // paymasterVerificationGasLimit lives at [20:36], postOp at [36:52].
        // Hashing the calldata prefix rather than enumerating fields is what
        // covers these two, and nothing else in the suite checks it.
        data[35] = bytes1(uint8(data[35]) ^ 0x01);
        op.paymasterAndData = data;
        (, uint256 verificationTampered) = _validate(op, 1 ether);
        assertEq(verificationTampered & 1, 1, "verification gas limit is signed");

        data[35] = bytes1(uint8(data[35]) ^ 0x01); // restore
        data[51] = bytes1(uint8(data[51]) ^ 0x01);
        op.paymasterAndData = data;
        (, uint256 postOpTampered) = _validate(op, 1 ether);
        assertEq(postOpTampered & 1, 1, "postOp gas limit is signed too");
    }

    function test_signatureCoversTheTimeWindow() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 1_000, 500);
        bytes memory data = op.paymasterAndData;
        data[Constants.VALID_UNTIL_OFFSET] =
            bytes1(uint8(data[Constants.VALID_UNTIL_OFFSET]) ^ 0xff);
        op.paymasterAndData = data;

        (, uint256 validationData) = _validate(op, 1 ether);
        assertEq(validationData & 1, 1, "the window cannot be widened after signing");
    }

    function test_signerOfOneAppCannotSignForAnother() public {
        address second = makeAddr("secondApp");
        address secondSigner;
        uint256 secondKey;
        (secondSigner, secondKey) = makeAddrAndKey("secondSigner");

        vm.prank(owner);
        paymaster.registerApp(second, secondSigner);
        _fundApp(second, 5 ether);

        // The first app's signer authorises spending from the second app.
        PackedUserOperation memory op = _sponsoredOp(alice, second, appSignerKey, 0, 0);
        (, uint256 validationData) = _validate(op, 1 ether);

        assertEq(validationData & 1, 1, "budgets are not fungible across apps");
        (uint96 budget,) = paymaster.apps(second);
        assertEq(budget, 5 ether, "and nothing was spent");
    }

    function test_rotatingTheSignerInvalidatesOutstandingSponsorships() public {
        PackedUserOperation memory op = _sponsoredOp(alice, app, appSignerKey, 0, 0);
        (, uint256 ok) = _validate(op, 1 ether);
        assertEq(ok & 1, 0, "valid under the old key");

        vm.prank(app);
        paymaster.setAppSigner(makeAddr("rotated"));

        (, uint256 afterRotation) = _validate(op, 1 ether);
        assertEq(afterRotation & 1, 1, "rotation is a revocation for anything not yet mined");
    }

    // --------------------------------------------------------------- helpers

    function _prefix(bytes memory data) internal pure returns (bytes memory out) {
        out = new bytes(Constants.SIGNATURE_OFFSET);
        for (uint256 i = 0; i < Constants.SIGNATURE_OFFSET; i++) {
            out[i] = data[i];
        }
    }

    function _tail(bytes memory data) internal pure returns (bytes memory out) {
        out = new bytes(Constants.SIGNATURE_LENGTH);
        for (uint256 i = 0; i < Constants.SIGNATURE_LENGTH; i++) {
            out[i] = data[Constants.SIGNATURE_OFFSET + i];
        }
    }
}
