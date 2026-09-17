import { NextResponse } from "next/server";
import {
  concat,
  createPublicClient,
  encodePacked,
  http,
  isAddress,
  isAddressEqual,
  isHex,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { toPackedUserOperation, type UserOperation } from "viem/account-abstraction";

import { paymasterAbi } from "@/lib/abi";
import { chain } from "@/lib/chain";
import { config } from "@/lib/config";

// The app's backend: decides whether to sponsor an operation and, if so, signs
// Monarch's Sponsored-mode `paymasterData`:
//
//   mode (1) | app (20) | validUntil (6) | validAfter (6) | signature (65)
//
// This is the only code that holds the app signer key. Anything under
// NEXT_PUBLIC_ ships to every visitor, and a signer key there hands the app's
// whole budget to the first person who reads the bundle.
//
// The endpoint is unauthenticated. On a testnet the worst case is that someone
// drains a testnet budget; for anything real, authenticating the caller is the
// first thing to build, before this route is reachable at all.

const MODE_SPONSORED = 1;

// Both paymaster gas limits sit inside the signed digest, so they are fixed
// here rather than taken from the request: the client cannot raise them, and
// with them the most an operation can charge the app. Measured on-chain cost
// is about 12k gas for validation and 11.5k for postOp.
const PAYMASTER_VERIFICATION_GAS = 60_000n;
const PAYMASTER_POSTOP_GAS = 40_000n;

// A sponsorship is good for ten minutes. The paymaster never reads the clock —
// it returns this window and the EntryPoint enforces it.
const SPONSORSHIP_TTL_SEC = 10 * 60;

// The ceiling on what one operation may cost the app, in wei. Without it a
// caller can name any gas limits and fee they like, and the app pays the
// bundler for all of it. Defaults to 0.0001 ETH; SPONSOR_MAX_COST_WEI moves it
// if fees do.
const MAX_COST_WEI = BigInt(process.env.SPONSOR_MAX_COST_WEI ?? 10n ** 14n);

// Shaped like a real signature (low s, v = 27) so gas estimation runs the same
// ecrecover the real one will. It recovers to an address that is not the
// signer, which the paymaster reports as a signature failure rather than a
// revert, so simulation still completes.
const STUB_SIGNATURE = `0x${"11".repeat(32)}${"22".repeat(32)}1b` as Hex;

const publicClient = createPublicClient({ chain, transport: http(config.rpcUrl) });

type Body = { phase?: unknown; userOp?: Record<string, unknown> };

export async function POST(request: Request) {
  let body: Body;
  try {
    body = (await request.json()) as Body;
  } catch {
    return fail(400, "request body is not JSON");
  }

  const op = body.userOp ?? {};
  if (Number(op.chainId) !== config.chainId) return fail(400, `wrong chain: ${op.chainId}`);
  if (typeof op.entryPointAddress !== "string" || !isAddress(op.entryPointAddress)) {
    return fail(400, "missing entryPointAddress");
  }
  if (!isAddressEqual(op.entryPointAddress, config.entryPoint)) {
    return fail(400, `unsupported EntryPoint: ${op.entryPointAddress}`);
  }

  const validUntil = Math.floor(Date.now() / 1000) + SPONSORSHIP_TTL_SEC;
  const prefix = encodePacked(
    ["uint8", "address", "uint48", "uint48"],
    [MODE_SPONSORED, config.app, validUntil, 0],
  );

  if (body.phase === "stub") {
    // Before gas estimation. Nothing is signed and nothing is promised; the
    // bundler only needs bytes of the right length and shape.
    return paymasterFields(concat([prefix, STUB_SIGNATURE]));
  }
  if (body.phase !== "final") return fail(400, "phase must be 'stub' or 'final'");

  const signerKey = process.env.APP_SIGNER_PRIVATE_KEY;
  if (!signerKey || !isHex(signerKey)) return fail(500, "server has no APP_SIGNER_PRIVATE_KEY");
  const signer = privateKeyToAccount(signerKey);

  let userOperation: UserOperation<"0.8">;
  try {
    userOperation = parseUserOperation(op);
  } catch (error) {
    return fail(400, `malformed userOp: ${(error as Error).message}`);
  }

  const maxCost =
    (userOperation.callGasLimit +
      userOperation.verificationGasLimit +
      userOperation.preVerificationGas +
      PAYMASTER_VERIFICATION_GAS +
      PAYMASTER_POSTOP_GAS) *
    userOperation.maxFeePerGas;
  if (maxCost > MAX_COST_WEI) {
    return fail(403, `declined: max cost ${maxCost} wei exceeds the ${MAX_COST_WEI} wei ceiling`);
  }

  // Fail here, with a message a person can act on, rather than at the bundler
  // as a bare signature or budget error.
  const [budget, registeredSigner] = await publicClient.readContract({
    address: config.paymaster,
    abi: paymasterAbi,
    functionName: "apps",
    args: [config.app],
  });
  if (!isAddressEqual(registeredSigner, signer.address)) {
    return fail(500, `this server signs as ${signer.address}, but the app's signer is ${registeredSigner}`);
  }
  if (budget < maxCost) return fail(503, `app budget ${budget} wei cannot cover ${maxCost} wei`);

  // The digest is computed by the paymaster itself over eth_call, not
  // re-derived here. Re-implementing the packing is the easiest way to sign
  // something subtly different from what the contract checks. It covers
  // `paymasterAndData` only up to the signature, so hashing the unsigned
  // prefix gives the same digest as hashing the finished bytes.
  const hash = await publicClient.readContract({
    address: config.paymaster,
    abi: paymasterAbi,
    functionName: "getSponsorshipHash",
    args: [
      toPackedUserOperation({
        ...userOperation,
        paymaster: config.paymaster,
        paymasterVerificationGasLimit: PAYMASTER_VERIFICATION_GAS,
        paymasterPostOpGasLimit: PAYMASTER_POSTOP_GAS,
        paymasterData: prefix,
      }),
    ],
  });
  // `signMessage` applies the EIP-191 prefix, matching the paymaster's
  // `toEthSignedMessageHash`.
  const signature = await signer.signMessage({ message: { raw: hash } });

  return paymasterFields(concat([prefix, signature]));
}

function paymasterFields(paymasterData: Hex) {
  return NextResponse.json({
    paymaster: config.paymaster,
    paymasterData,
    paymasterVerificationGasLimit: PAYMASTER_VERIFICATION_GAS.toString(),
    paymasterPostOpGasLimit: PAYMASTER_POSTOP_GAS.toString(),
  });
}

function parseUserOperation(op: Record<string, unknown>): UserOperation<"0.8"> {
  const address = (key: string): Address => {
    const value = op[key];
    if (typeof value !== "string" || !isAddress(value)) throw new Error(`${key} is not an address`);
    return value;
  };
  const hex = (key: string): Hex => {
    const value = op[key];
    if (typeof value !== "string" || !isHex(value)) throw new Error(`${key} is not hex`);
    return value;
  };
  const uint = (key: string): bigint => {
    const value = op[key];
    if (typeof value !== "string" || !/^\d+$/.test(value)) throw new Error(`${key} is not a uint`);
    return BigInt(value);
  };

  return {
    sender: address("sender"),
    nonce: uint("nonce"),
    ...(op.factory ? { factory: address("factory"), factoryData: hex("factoryData") } : {}),
    callData: hex("callData"),
    callGasLimit: uint("callGasLimit"),
    verificationGasLimit: uint("verificationGasLimit"),
    preVerificationGas: uint("preVerificationGas"),
    maxFeePerGas: uint("maxFeePerGas"),
    maxPriorityFeePerGas: uint("maxPriorityFeePerGas"),
    signature: "0x",
  };
}

function fail(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}
