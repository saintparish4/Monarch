// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title MeasuringPaymaster
/// @notice A test-only paymaster that accepts everything and records what the
///         EntryPoint told it an operation cost.
/// @dev Exists for measurements Monarch itself cannot take. Isolating the
///      EntryPoint's unused-gas penalty means a `postOp` whose own cost is
///      constant and known; Monarch's varies with what it writes. And showing
///      what a failed `postOp` costs means one that fails on demand, which
///      Monarch is built never to do.
///
///      This is not a mock of the EntryPoint or of anything else upstream. The
///      EntryPoint under test is the real one; this is a counterparty written
///      for the experiment, in the same spirit as the adversary contracts.
contract MeasuringPaymaster is IPaymaster {
    IEntryPoint public immutable entryPoint;

    /// @notice `actualGasCost` as handed to `postOp` — everything the EntryPoint
    ///         had accounted for at the moment it made the call.
    /// @dev An event rather than storage on purpose. Storing two words costs
    ///      44,200 gas cold and 5,800 warm, and the EntryPoint bills the
    ///      paymaster for whatever `postOp` spends — so a storing version
    ///      measures its own first-write penalty instead of the EntryPoint's
    ///      behaviour, and measures a different number the second time. A log
    ///      costs the same every call.
    event Measured(uint256 actualGasCost, uint256 feePerGas);

    /// @notice Make `postOp` fail, standing in for one that ran out of gas.
    /// @dev The EntryPoint cannot tell the two apart: both arrive as a failed
    ///      call, and both send it down the `postOpReverted` path.
    bool public failInPostOp;

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    function setFailInPostOp(bool value) external {
        failInPostOp = value;
    }

    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        pure
        override
        returns (bytes memory context, uint256 validationData)
    {
        // Any non-empty context: the EntryPoint skips `postOp` for an empty one.
        return (hex"01", 0);
    }

    function postOp(
        PostOpMode,
        bytes calldata,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external override {
        if (failInPostOp) revert("starved");
        emit Measured(actualGasCost, actualUserOpFeePerGas);
    }

    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }
}
