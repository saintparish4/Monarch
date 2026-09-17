import { parseAbi } from "viem";

// The parts of MonarchPaymaster the demo reads. Written out rather than
// imported from forge's out/, which is a build artefact and not committed.
export const paymasterAbi = parseAbi([
  "struct PackedUserOperation { address sender; uint256 nonce; bytes initCode; bytes callData; bytes32 accountGasLimits; uint256 preVerificationGas; bytes32 gasFees; bytes paymasterAndData; bytes signature; }",
  "function getSponsorshipHash(PackedUserOperation userOp) view returns (bytes32)",
  "function apps(address app) view returns (uint96 budget, address signer)",
  "event SponsorshipCharged(address indexed app, address indexed user, uint256 amount)",
]);
