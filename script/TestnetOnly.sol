// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Refuses to run on any chain but Base Sepolia and a local anvil.
/// @dev Monarch is unaudited. The likeliest way it ends up holding real money is
///      not a decision but a copy: someone forks the repo, points these scripts
///      at a mainnet RPC, and broadcasts. This makes that a code change, one
///      someone has to make on purpose, rather than a flag.
///
///      An allowlist, not a denylist. A list of mainnets to refuse is always one
///      chain short.
abstract contract TestnetOnly {
    uint256 internal constant BASE_SEPOLIA = 84_532;
    uint256 internal constant ANVIL = 31_337;

    error NotATestnet(uint256 chainId);

    modifier testnetOnly() {
        _requireTestnet();
        _;
    }

    function _requireTestnet() internal view {
        if (block.chainid != BASE_SEPOLIA && block.chainid != ANVIL) {
            revert NotATestnet(block.chainid);
        }
    }
}
