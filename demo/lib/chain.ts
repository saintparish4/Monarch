import { defineChain } from "viem";
import { baseSepolia } from "viem/chains";

import { config } from "./config";

// A local fork keeps Base Sepolia's state but not its chain id. The id has to
// be the fork's, because EntryPoint v0.8 hashes it into every userOpHash and
// the account signs that hash.
export const chain =
  config.chainId === baseSepolia.id
    ? baseSepolia
    : defineChain({
        ...baseSepolia,
        id: config.chainId,
        name: "Base Sepolia (local fork)",
        rpcUrls: { default: { http: [config.rpcUrl] } },
      });
