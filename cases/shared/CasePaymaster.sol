// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title CasePaymaster
/// @notice The plumbing every paymaster in `cases/` shares, so that each case's
///         own files hold only the lesson.
/// @dev These contracts exist to be read and tested, never deployed. There is no
///      owner and no access control beyond "only the EntryPoint may call the
///      `IPaymaster` functions", because every case is about something else.
///      Case 06 is the exception: it is about ownership, so it brings its own.
abstract contract CasePaymaster is IPaymaster {
    /// @dev Where `paymasterData` starts inside `paymasterAndData`, after the
    ///      paymaster address and its two gas limits. Offset 52 in v0.7 and
    ///      v0.8; offset 20 in v0.6, which is its own bug.
    uint256 internal constant DATA_OFFSET = 52;

    IEntryPoint public immutable entryPoint;

    error NotEntryPoint(address caller);

    constructor(IEntryPoint entryPoint_) {
        entryPoint = entryPoint_;
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        _onlyEntryPoint();
        return _validate(userOp, userOpHash, maxCost);
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external {
        _onlyEntryPoint();
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }

    /// @notice Fund this paymaster's deposit on the EntryPoint.
    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Stake on the EntryPoint. Open to anyone here, because adding
    ///         stake only ever costs the caller.
    function addStake(uint32 unstakeDelaySec) external payable {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    function _validate(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        virtual
        returns (bytes memory context, uint256 validationData);

    /// @dev Only reached when `_validate` returned a non-empty context.
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual {}

    function _onlyEntryPoint() internal view {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint(msg.sender);
    }
}
