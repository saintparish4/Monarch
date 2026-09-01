// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MonarchPaymaster} from "../../contracts/MonarchPaymaster.sol";

/// @notice A withdrawal recipient that tries to re-enter on the way in.
/// @dev Not a mock. This models something outside the trust boundary — an
///      address the paymaster is told to send ETH to, which is attacker code by
///      construction. Mocking a dependency I misunderstood proves nothing;
///      modelling an attacker proves something.
contract ReentrantReceiver {
    MonarchPaymaster public immutable paymaster;
    bool public reenterAsUser;
    bool public reenterAsApp;
    bool public reenterAsDepositor;
    bool public attempted;

    constructor(MonarchPaymaster _paymaster) {
        paymaster = _paymaster;
    }

    function armUser() external {
        reenterAsUser = true;
    }

    function armApp() external {
        reenterAsApp = true;
    }

    function armDepositor() external {
        reenterAsDepositor = true;
    }

    function depositTo(uint256 amount) external payable {
        paymaster.depositFor{value: amount}(address(this));
    }

    function withdraw(uint256 amount) external {
        paymaster.withdrawUserDeposit(payable(address(this)), amount);
    }

    function withdrawBudget(uint256 amount) external {
        paymaster.withdrawAppBudget(payable(address(this)), amount);
    }

    receive() external payable {
        if (reenterAsUser) {
            attempted = true;
            paymaster.withdrawUserDeposit(payable(address(this)), 1);
        } else if (reenterAsApp) {
            attempted = true;
            paymaster.withdrawAppBudget(payable(address(this)), 1);
        } else if (reenterAsDepositor) {
            // The unguarded path. This is expected to SUCCEED — the point is
            // that solvency survives it, not that it is blocked.
            attempted = true;
            paymaster.depositFor{value: 0.0001 ether}(address(this));
        }
    }
}

/// @notice A call target that always reverts, for proving a failed operation is
///         still charged.
contract RevertingTarget {
    error Nope();

    function boom() external pure {
        revert Nope();
    }
}

/// @notice A trivial target so a sponsored call has something to prove it ran.
contract Guestbook {
    mapping(address => string) public entries;

    function sign(string calldata message) external {
        entries[msg.sender] = message;
    }
}
