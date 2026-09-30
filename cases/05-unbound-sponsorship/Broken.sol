// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {_packValidationData} from "account-abstraction/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title CallBlindSponsorPaymaster (case 05, broken)
/// @notice Sponsors an operation when the app's signer has signed for it.
/// @dev `paymasterData` is `validUntil (6) | validAfter (6) | signature (65)`.
contract CallBlindSponsorPaymaster is CasePaymaster {
    uint256 internal constant SIGNATURE_OFFSET = DATA_OFFSET + 12;

    address public immutable signer;

    constructor(IEntryPoint entryPoint_, address signer_) CasePaymaster(entryPoint_) {
        signer = signer_;
    }

    /// @notice What the app's signer signs to sponsor `userOp`.
    /// @dev THE BUG is what this leaves out. It binds who, which nonce, when,
    ///      which chain and which paymaster, and none of what the operation
    ///      does or how much gas it may burn. The sender can take a signature
    ///      for one call and attach it to another, or raise the gas limits the
    ///      app will be billed for, and the signature still recovers.
    function getHash(PackedUserOperation calldata userOp) public view returns (bytes32) {
        (uint48 validUntil, uint48 validAfter) = _window(userOp);
        return keccak256(
            abi.encode(
                userOp.sender, userOp.nonce, validUntil, validAfter, block.chainid, address(this)
            )
        );
    }

    function _validate(PackedUserOperation calldata userOp, bytes32, uint256)
        internal
        view
        override
        returns (bytes memory, uint256)
    {
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(getHash(userOp));
        // slither-disable-next-line unused-return
        (address recovered, ECDSA.RecoverError err,) =
            ECDSA.tryRecover(digest, userOp.paymasterAndData[SIGNATURE_OFFSET:]);
        bool failed = err != ECDSA.RecoverError.NoError || recovered != signer;

        (uint48 validUntil, uint48 validAfter) = _window(userOp);
        return ("", _packValidationData(failed, validUntil, validAfter));
    }

    function _window(PackedUserOperation calldata userOp)
        internal
        pure
        returns (uint48 validUntil, uint48 validAfter)
    {
        validUntil = uint48(bytes6(userOp.paymasterAndData[DATA_OFFSET:DATA_OFFSET + 6]));
        validAfter = uint48(bytes6(userOp.paymasterAndData[DATA_OFFSET + 6:SIGNATURE_OFFSET]));
    }
}
