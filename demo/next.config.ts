import type { NextConfig } from "next";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { parseEnv } from "node:util";

const repoRoot = path.resolve(process.cwd(), "..");

// The app signer key lives in the repository's git-ignored .env, beside the
// deployer key that registered it, rather than in a second copy under demo/.
// Only that one variable is taken: the same file holds the deployer key, and
// the demo server has no business holding the key that owns the paymaster.
const rootEnv = path.join(repoRoot, ".env");
if (!process.env.APP_SIGNER_PRIVATE_KEY && existsSync(rootEnv)) {
  const parsed = parseEnv(readFileSync(rootEnv, "utf8"));
  if (parsed.APP_SIGNER_PRIVATE_KEY) {
    process.env.APP_SIGNER_PRIVATE_KEY = parsed.APP_SIGNER_PRIVATE_KEY;
  }
}

const nextConfig: NextConfig = {
  // The deployed addresses are read from deployments/, outside this directory.
  turbopack: { root: repoRoot },
  // `next dev` otherwise writes editor-assistant instruction files into the
  // project on every run.
  agentRules: false,
};

export default nextConfig;
