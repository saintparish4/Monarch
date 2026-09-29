// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

/// @notice The EntryPoint every other test runs against is the one deployed on
///         Base Sepolia, byte for byte.
/// @dev The no-mocks argument rests on this. `Fixture` deploys `new EntryPoint()`
///      compiled from `lib/`, and every claim the suite makes about EntryPoint
///      behaviour holds only if that is the contract bundlers actually call.
///
///      Run under the `fork` profile (`FOUNDRY_PROFILE=fork forge test`), which
///      compiles with the settings upstream shipped: via-IR, 1,000,000 optimizer
///      runs. Under this repo's own settings the bytecode is a different length
///      and the comparison is meaningless, so the default profile excludes this
///      directory.
///
///      Two parts of the bytecode legitimately differ, and both are removed
///      rather than masked by offset:
///        - Immutables: `SenderCreator`'s address and the EIP-712 domain cache
///          depend on where the constructor ran. The local copy is constructed
///          *at the canonical address*, from the canonical nonce, so they come
///          out identical.
///        - The CBOR metadata trailer: it hashes source paths, which differ
///          between upstream's Hardhat layout and `lib/`. It is not executed.
///      Everything that remains, every executed byte, must match.
contract EntryPointBytecodeTest is Test {
    address internal constant CANONICAL = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    function test_localEntryPointIsTheDeployedOne() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            // Green on a checkout with no RPC, but never silently green in CI,
            // which sets REQUIRE_FORK.
            assertFalse(vm.envOr("REQUIRE_FORK", false), "REQUIRE_FORK is set but no RPC is");
            return;
        }
        vm.createSelectFork(rpc);

        bytes memory deployed = CANONICAL.code;
        assertGt(deployed.length, 0, "no code at the canonical EntryPoint address");
        address senderCreator = address(EntryPoint(payable(CANONICAL)).senderCreator());

        // Clear the way for a second construction at the same address. The
        // constructor CREATEs its SenderCreator from nonce 1, which is where
        // the live one already sits.
        vm.etch(senderCreator, "");
        vm.resetNonce(senderCreator);
        vm.setNonceUnsafe(CANONICAL, 1);

        // Run the creation code as if it were being deployed at CANONICAL; what
        // it returns is the runtime code, immutables filled in.
        vm.etch(CANONICAL, type(EntryPoint).creationCode);
        (bool ok, bytes memory local) = CANONICAL.call("");
        assertTrue(ok, "constructing the local EntryPoint at the canonical address failed");

        assertEq(local.length, deployed.length, "runtime code length differs");
        assertEq(
            keccak256(_withoutMetadata(local)),
            keccak256(_withoutMetadata(deployed)),
            "executable bytecode differs from the deployed EntryPoint"
        );
        vm.etch(CANONICAL, local);
        assertEq(
            address(EntryPoint(payable(CANONICAL)).senderCreator()),
            senderCreator,
            "immutables were reconstructed, not approximated"
        );
    }

    /// @dev Solidity ends runtime code with CBOR metadata followed by its own
    ///      length as two big-endian bytes.
    function _withoutMetadata(bytes memory code) internal pure returns (bytes memory out) {
        uint256 n = code.length;
        uint256 metadata = (uint256(uint8(code[n - 2])) << 8) | uint8(code[n - 1]);
        out = new bytes(n - metadata - 2);
        for (uint256 i; i < out.length; ++i) {
            out[i] = code[i];
        }
    }
}
