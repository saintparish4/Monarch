// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {_packValidationData} from "account-abstraction/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {CasePaymaster} from "../shared/CasePaymaster.sol";

/// @title CallBoundSponsorPaymaster (case 05, fixed)
/// @notice `CallBlindSponsorPaymaster` with a digest that covers the operation.
contract CallBoundSponsorPaymaster is CasePaymaster {
    uint256 internal constant SIGNATURE_OFFSET = DATA_OFFSET + 12;

    address public immutable signer;

    constructor(IEntryPoint entryPoint_, address signer_) CasePaymaster(entryPoint_) {
        signer = signer_;
    }

    /// @notice What the app's signer signs to sponsor `userOp`.
    /// @dev THE FIX. Every field of the operation except the account's own
    ///      signature, which cannot be known yet. `paymasterAndData` is hashed up
    ///      to the sponsorship signature, which covers this paymaster's address,
    ///      both paymaster gas limits and the time window in one slice. Listing
    ///      those fields by hand instead is how the gas limits get left out.
    ///
    ///      Serve this from the contract (an `eth_call` from the app's backend)
    ///      rather than re-deriving the packing off-chain: two implementations
    ///      of one hash drift.
    function getHash(PackedUserOperation calldata userOp) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                keccak256(userOp.paymasterAndData[:SIGNATURE_OFFSET]),
                block.chainid,
                address(this)
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

        uint48 validUntil = uint48(bytes6(userOp.paymasterAndData[DATA_OFFSET:DATA_OFFSET + 6]));
        uint48 validAfter =
            uint48(bytes6(userOp.paymasterAndData[DATA_OFFSET + 6:SIGNATURE_OFFSET]));
        return ("", _packValidationData(failed, validUntil, validAfter));
    }
}
