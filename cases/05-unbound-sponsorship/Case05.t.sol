// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {CaseTest, Target} from "../shared/CaseTest.sol";
import {CallBlindSponsorPaymaster} from "./Broken.sol";
import {CallBoundSponsorPaymaster} from "./Fixed.sol";

/// @dev Both versions expose the same hash function.
interface ISponsorHash {
    function getHash(PackedUserOperation calldata userOp) external view returns (bytes32);
}

/// @notice Case 05: a sponsorship digest that leaves out fields it should bind.
contract Case05Test is CaseTest {
    CallBlindSponsorPaymaster internal broken;
    CallBoundSponsorPaymaster internal fixed_;

    uint256 internal appSignerKey;
    SimpleAccount internal account;
    uint256 internal ownerKey;

    uint48 internal validUntil;

    function setUp() public override {
        super.setUp();
        address appSigner;
        (appSigner, appSignerKey) = makeAddrAndKey("appSigner");
        broken = new CallBlindSponsorPaymaster(IEntryPoint(address(entryPoint)), appSigner);
        fixed_ = new CallBoundSponsorPaymaster(IEntryPoint(address(entryPoint)), appSigner);
        broken.deposit{value: 1 ether}();
        fixed_.deposit{value: 1 ether}();
        (account, ownerKey) = _newAccount("user");
        validUntil = uint48(block.timestamp + 1 hours);
    }

    /// @dev The app's backend at work: it sees the operation, decides to pay
    ///      for it, and signs. The account's own signature is left for later.
    function _approvedByTheApp(address paymaster, string memory text)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op = _op(account, text);
        bytes memory prefix = abi.encodePacked(validUntil, uint48(0));
        op.paymasterAndData = _paymasterAndData(paymaster, PAYMASTER_POSTOP_GAS, prefix);
        bytes32 digest =
            MessageHashUtils.toEthSignedMessageHash(ISponsorHash(paymaster).getHash(op));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(appSignerKey, digest);
        op.paymasterAndData = bytes.concat(op.paymasterAndData, abi.encodePacked(r, s, v));
    }

    /// @dev The sender, after the app has signed, pointing the operation at a
    ///      different call.
    function _swapTheCall(PackedUserOperation memory op, string memory text)
        internal
        view
        returns (PackedUserOperation memory)
    {
        op.callData = abi.encodeCall(
            BaseAccount.execute, (address(target), 0, abi.encodeCall(Target.note, (text)))
        );
        return op;
    }

    /// @dev The sender, after the app has signed, raising the call gas limit
    ///      the app will be billed against.
    function _raiseTheGas(PackedUserOperation memory op)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        op.accountGasLimits = _pack(VERIFICATION_GAS, CALL_GAS * 10);
        return op;
    }

    function test_bothVersionsSponsorWhatTheAppApproved() public {
        _handle(_signAsAccount(_approvedByTheApp(address(broken), "approved"), ownerKey));
        assertEq(target.lastNote(address(account)), "approved", "the broken version sponsored it");
        _handle(_signAsAccount(_approvedByTheApp(address(fixed_), "approved"), ownerKey));
        assertEq(target.lastNote(address(account)), "approved", "the fixed version sponsored it");
    }

    function test_brokenSponsorsACallTheAppNeverApproved() public {
        PackedUserOperation memory op = _approvedByTheApp(address(broken), "approved");
        op = _signAsAccount(_swapTheCall(op, "never approved"), ownerKey);
        uint256 before = _depositOf(address(broken));

        _handle(op);

        assertEq(target.lastNote(address(account)), "never approved", "the swapped call ran");
        assertLt(_depositOf(address(broken)), before, "and the app paid for it");
    }

    function test_fixedRefusesACallTheAppNeverApproved() public {
        PackedUserOperation memory op = _approvedByTheApp(address(fixed_), "approved");
        op = _signAsAccount(_swapTheCall(op, "never approved"), ownerKey);

        vm.expectRevert(
            abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA34 signature error")
        );
        _handle(op);
    }

    /// @notice The gas limits are part of what the app agreed to pay. EntryPoint
    ///         v0.8 charges a tenth of unused call gas, so raising the limit
    ///         raises the bill even when the call uses no more.
    function test_brokenLetsTheSenderRaiseTheGasTheAppPaysFor() public {
        PackedUserOperation memory approved =
            _signAsAccount(_approvedByTheApp(address(broken), "approved"), ownerKey);
        PackedUserOperation memory raised =
            _signAsAccount(_raiseTheGas(_approvedByTheApp(address(broken), "approved")), ownerKey);
        uint256 before = _depositOf(address(broken));

        // Both from the same state, so the only difference is the gas limit.
        uint256 snapshot = vm.snapshotState();
        _handle(approved);
        uint256 asApproved = before - _depositOf(address(broken));
        vm.revertToState(snapshot);
        _handle(raised);
        uint256 asRaised = before - _depositOf(address(broken));

        // The limit went from 100,000 to 1,000,000; a tenth of the extra
        // 900,000 is 90,000 gas the app pays for nothing.
        assertGt(asRaised, asApproved + 80_000 * FEE, "the same call, a larger bill");
    }

    function test_fixedRefusesRaisedGasLimits() public {
        PackedUserOperation memory op = _approvedByTheApp(address(fixed_), "approved");
        op = _signAsAccount(_raiseTheGas(op), ownerKey);

        vm.expectRevert(
            abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA34 signature error")
        );
        _handle(op);
    }

    function test_noOpcodeCheckCatchesTheBrokenVersion() public {
        PackedUserOperation memory op = _approvedByTheApp(address(broken), "approved");
        assertEq(
            _bannedOpcodeInValidation(IPaymaster(address(broken)), op, false),
            0,
            "no forbidden opcode: the digest is valid, just incomplete"
        );
    }
}
