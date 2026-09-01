// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Validation
/// @notice Input guards shared by Monarch's contracts.
/// @dev Every function here reverts with a custom error rather than a string.
///      That is not a gas micro-optimisation: `require` strings are the reason
///      the library this replaces carried five `string public constant ERR_*`
///      constants, and a typed error is something a test can assert on by
///      selector instead of by substring.
///
///      Nothing here reads block state. These guards are called from
///      `validatePaymasterUserOp`, which runs under ERC-7562 validation rules
///      where `TIMESTAMP`, `NUMBER` and `BALANCE` are banned opcodes. A guard
///      that reads the clock would make every sponsored operation rejectable
///      by bundlers.
library Validation {
    error ZeroAddress();
    error NotAContract(address addr);

    /// @notice Reverts if `addr` is the zero address.
    /// @dev The single most common cause of an unrecoverable deploy: an owner
    ///      or EntryPoint accidentally set to `address(0)`.
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /// @notice Reverts unless `addr` has code.
    /// @dev Guards the constructor against being handed an EOA in place of the
    ///      EntryPoint. Deliberately NOT usable during validation: `EXTCODESIZE`
    ///      on an address that is not the sender is a banned storage access
    ///      under ERC-7562. Constructor and admin paths only.
    function validateContract(address addr) internal view {
        validateAddress(addr);
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(addr)
        }
        if (size == 0) revert NotAContract(addr);
    }
}
