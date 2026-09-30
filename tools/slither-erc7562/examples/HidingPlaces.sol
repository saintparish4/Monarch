// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./UserOperation.sol";

// Where a banned opcode hides from someone reading `validatePaymasterUserOp`.
// Each contract below reads the clock somewhere other than the function body,
// and the bundler's tracer sees every one of them, because it sees every opcode
// executed under the validation frame. The fix is the one in `Clock.sol`.

/// REPORTED: TIMESTAMP via `block.timestamp`, in the modifier `whileOpen`.
contract ClockInModifier {
    uint256 public immutable closesAt;

    constructor(uint256 closesAt_) {
        closesAt = closesAt_;
    }

    modifier whileOpen() {
        require(block.timestamp < closesAt, "closed");
        _;
    }

    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        view
        whileOpen
        returns (bytes memory context, uint256 validationData)
    {
        return ("", 0);
    }
}

library Windows {
    function isOpen(uint256 closesAt) internal view returns (bool) {
        return block.timestamp < closesAt;
    }
}

/// REPORTED: TIMESTAMP via `block.timestamp`, in the library function `isOpen`.
contract ClockInLibrary {
    uint256 public immutable closesAt;

    constructor(uint256 closesAt_) {
        closesAt = closesAt_;
    }

    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        return ("", Windows.isOpen(closesAt) ? 0 : 1);
    }
}

/// REPORTED: TIMESTAMP via `timestamp()`, in inline assembly.
contract ClockInAssembly {
    uint256 public immutable closesAt;

    constructor(uint256 closesAt_) {
        closesAt = closesAt_;
    }

    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        view
        returns (bytes memory context, uint256 validationData)
    {
        uint256 closes = closesAt;
        assembly {
            validationData := iszero(lt(timestamp(), closes))
        }
        return ("", validationData);
    }
}
