import type { Address } from "viem";

import deployment from "../../deployments/base-sepolia.json";

// Everything here is public — addresses and endpoints — and is safe in the
// browser bundle. The one secret, the app signer key, is read only inside the
// server route and never passes through this file.
//
// The NEXT_PUBLIC_ overrides exist to point the demo at a local fork for a
// rehearsal. Without them it talks to the deployment recorded in deployments/.
export const config = {
  chainId: Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? deployment.chainId),
  rpcUrl: process.env.NEXT_PUBLIC_RPC_URL ?? deployment.rpcUrl,
  bundlerUrl: process.env.NEXT_PUBLIC_BUNDLER_URL ?? deployment.bundlerUrl,
  explorerUrl: deployment.explorerUrl,
  entryPoint: deployment.entryPoint as Address,
  factory: deployment.simpleAccountFactory as Address,
  paymaster: (process.env.NEXT_PUBLIC_PAYMASTER ?? deployment.paymaster) as Address,
  app: (process.env.NEXT_PUBLIC_APP ?? deployment.app) as Address,
};
