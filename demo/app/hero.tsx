"use client";

import { useCallback, useEffect, useState } from "react";
import {
  createPublicClient,
  formatEther,
  http,
  isAddressEqual,
  parseEventLogs,
  type Address,
  type Hex,
} from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import {
  createBundlerClient,
  type GetPaymasterDataParameters,
  type GetPaymasterStubDataParameters,
  type SmartAccount,
} from "viem/account-abstraction";
import { toSimpleSmartAccount } from "permissionless/accounts";

import { paymasterAbi } from "@/lib/abi";
import { chain } from "@/lib/chain";
import { config } from "@/lib/config";

import { Alert, ArrowRight, Layers, Link } from "./icons";

// The owner key is generated here, in this browser, and has never held ETH.
// Starting from a funded wallet would prove nothing a block explorer does not.
const KEY_STORAGE = "monarch-demo:owner-key";

const publicClient = createPublicClient({ chain, transport: http(config.rpcUrl) });

type Wallet = {
  account: SmartAccount;
  owner: Address;
  ownerBalance: bigint;
  accountBalance: bigint;
  deployed: boolean;
};

type Status =
  | { kind: "idle" }
  | { kind: "working"; label: string; userOpHash?: Hex }
  | {
      kind: "done";
      userOpHash: Hex;
      txHash: Hex;
      success: boolean;
      charged: bigint;
    }
  | { kind: "error"; message: string };

/**
 * The top of the page, and the whole demo: the headline on one side, the live
 * wallet on the other. It is one client component because the button under the
 * headline and the card beside it are the same piece of state.
 */
export function Hero() {
  const [wallet, setWallet] = useState<Wallet>();
  const [budget, setBudget] = useState<bigint>();
  const [status, setStatus] = useState<Status>({ kind: "idle" });

  const load = useCallback(async () => {
    let key = localStorage.getItem(KEY_STORAGE) as Hex | null;
    if (!key) {
      key = generatePrivateKey();
      localStorage.setItem(KEY_STORAGE, key);
    }
    const owner = privateKeyToAccount(key);
    const account = await toSimpleSmartAccount({
      client: publicClient,
      owner,
      entryPoint: { address: config.entryPoint, version: "0.8" },
      factoryAddress: config.factory,
    });
    const [ownerBalance, accountBalance, code, app] = await Promise.all([
      publicClient.getBalance({ address: owner.address }),
      publicClient.getBalance({ address: account.address }),
      publicClient.getCode({ address: account.address }),
      readApp(),
    ]);
    setWallet({
      account,
      owner: owner.address,
      ownerBalance,
      accountBalance,
      deployed: !!code && code !== "0x",
    });
    setBudget(app);
  }, []);

  useEffect(() => {
    load().catch((error) => setStatus({ kind: "error", message: String(error) }));
  }, [load]);

  async function send() {
    if (!wallet) return;
    setStatus({ kind: "working", label: "Preparing the operation…" });
    try {
      const bundler = createBundlerClient({
        account: wallet.account,
        client: publicClient,
        chain,
        transport: http(config.bundlerUrl),
        paymaster: {
          getPaymasterStubData: (params) => sponsor("stub", params),
          getPaymasterData: (params) => sponsor("final", params),
        },
        userOperation: { estimateFeesPerGas: bundlerGasPrice },
      });

      setStatus({ kind: "working", label: "Asking the app to sponsor, then signing…" });
      // One call from the account to itself with no value. The first operation
      // also deploys the account, so its gas is the most a new user ever costs.
      const userOpHash = await bundler.sendUserOperation({
        calls: [{ to: wallet.account.address, value: 0n, data: "0x" }],
      });

      setStatus({ kind: "working", label: "Submitted. Waiting for the bundler to land it…", userOpHash });
      const receipt = await bundler.waitForUserOperationReceipt({ hash: userOpHash, timeout: 180_000 });

      // The charge comes from the paymaster's own event in this operation's
      // logs. Diffing two budget reads is wrong whenever the public RPC answers
      // from a node that has not seen the block yet: it reports 0.
      const charged = parseEventLogs({
        abi: paymasterAbi,
        eventName: "SponsorshipCharged",
        logs: receipt.logs,
      })
        .filter((log) => isAddressEqual(log.address, config.paymaster))
        .reduce((sum, log) => sum + log.args.amount, 0n);
      setStatus({
        kind: "done",
        userOpHash,
        txHash: receipt.receipt.transactionHash,
        success: receipt.success,
        charged,
      });
      await load();
    } catch (error) {
      // The bundler's exact words, unedited. When ERC-7562 rejects an
      // operation this string is the only record of why.
      setStatus({ kind: "error", message: (error as Error).message ?? String(error) });
    }
  }

  function reset() {
    localStorage.removeItem(KEY_STORAGE);
    setStatus({ kind: "idle" });
    setWallet(undefined);
    load().catch((error) => setStatus({ kind: "error", message: String(error) }));
  }

  const busy = status.kind === "working";

  return (
    <section className="hero" id="demo">
      <div className="container hero-grid">
        <div className="hero-copy">
          <span className="hero-rule" aria-hidden="true" />
          <h1>A wallet with zero ETH sends a transaction</h1>
          <p className="lede">
            A wallet created in this tab, holding <strong>zero ETH</strong>, sends a transaction on
            Base Sepolia. An app pays the gas through{" "}
            <a href={`${config.explorerUrl}/address/${config.paymaster}`}>MonarchPaymaster</a>, an
            ERC-4337 paymaster.
          </p>
          <ul className="chips">
            <li>
              <span className="chip-icon">
                <Layers />
              </span>
              EntryPoint v0.8
            </li>
            <li>
              <span className="chip-icon">
                <Link />
              </span>
              Base Sepolia
            </li>
            <li>
              <span className="chip-icon">
                <Alert />
              </span>
              Testnet only, unaudited
            </li>
          </ul>
          <div className="actions">
            <button className="button primary large" onClick={send} disabled={!wallet || busy}>
              {busy ? "Working…" : "Send a sponsored transaction"}
              <ArrowRight />
            </button>
            <button className="button outline large" onClick={reset} disabled={busy}>
              New wallet
            </button>
          </div>
        </div>

        <div className="hero-stage">
          {/* What is about to be sent, drawn behind the wallet that sends it. */}
          <div className="op-card" aria-label="The operation this wallet sends">
            <p className="op-title">
              <span>userOperation</span>
              <span>EntryPoint v0.8</span>
            </p>
            <p className="op-row">
              <span>sender</span>
              <code>{wallet ? short(wallet.account.address) : "…"}</code>
            </p>
            <p className="op-row">
              <span>callData</span>
              <code>execute(self, 0, 0x)</code>
            </p>
            <p className="op-row">
              <span>paymaster</span>
              <code>{short(config.paymaster)}</code>
            </p>
            <p className="op-row">
              <span>paymasterData</span>
              <code>mode · app · window · signature</code>
            </p>
          </div>

          <div className="wallet-card">
            <h2>
              Your wallet
              <span className={wallet ? "live" : "live pending"}>{wallet ? "On chain" : "Loading"}</span>
            </h2>
            {wallet ? (
              <dl>
                <dt>Owner key</dt>
                <dd>
                  <code>{wallet.owner}</code>
                  <span className="note">
                    generated in this browser, balance{" "}
                    <strong>{formatEther(wallet.ownerBalance)} ETH</strong>
                  </span>
                </dd>
                <dt>Smart account</dt>
                <dd>
                  <a href={`${config.explorerUrl}/address/${wallet.account.address}`}>
                    <code>{wallet.account.address}</code>
                  </a>
                  <span className="note">
                    {wallet.deployed ? "deployed" : "not deployed yet"}, balance{" "}
                    <strong>{formatEther(wallet.accountBalance)} ETH</strong>
                  </span>
                </dd>
                <dt>App budget</dt>
                <dd>
                  <strong>{budget === undefined ? "…" : `${formatEther(budget)} ETH`}</strong>
                  <span className="note">what the app has left to spend on its users</span>
                </dd>
              </dl>
            ) : (
              <p className="placeholder">Creating a wallet…</p>
            )}
          </div>

          <StatusPanel status={status} />
        </div>
      </div>
    </section>
  );
}

function StatusPanel({ status }: { status: Status }) {
  if (status.kind === "idle") return null;
  if (status.kind === "working") {
    return (
      <section className="status" aria-live="polite">
        <p className="working">
          <span className="spinner" aria-hidden="true" />
          {status.label}
        </p>
        {status.userOpHash && (
          <p className="note">
            UserOperation <code>{status.userOpHash}</code>
          </p>
        )}
      </section>
    );
  }
  if (status.kind === "error") {
    return (
      <section className="status error" aria-live="polite">
        <h2>Failed</h2>
        <pre>{status.message}</pre>
      </section>
    );
  }
  return (
    <section className={status.success ? "status ok" : "status error"} aria-live="polite">
      <h2>{status.success ? "Done — and you still hold 0 ETH" : "Included, but the call reverted"}</h2>
      <dl>
        <dt>Transaction</dt>
        <dd>
          <a href={`${config.explorerUrl}/tx/${status.txHash}`}>
            <code>{status.txHash}</code>
          </a>
        </dd>
        <dt>UserOperation</dt>
        <dd>
          <code>{status.userOpHash}</code>
        </dd>
        <dt>Charged to the app</dt>
        <dd>
          <strong>{formatEther(status.charged)} ETH</strong>
        </dd>
      </dl>
    </section>
  );
}

function short(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

async function readApp(): Promise<bigint> {
  const [budget] = await publicClient.readContract({
    address: config.paymaster,
    abi: paymasterAbi,
    functionName: "apps",
    args: [config.app],
  });
  return budget;
}

async function sponsor(
  phase: "stub" | "final",
  params: GetPaymasterStubDataParameters | GetPaymasterDataParameters,
) {
  const response = await fetch("/api/sponsor", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ phase, userOp: params }, (_key, value) =>
      typeof value === "bigint" ? value.toString() : value,
    ),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error ?? `sponsor endpoint returned ${response.status}`);
  return {
    paymaster: body.paymaster as Address,
    paymasterData: body.paymasterData as Hex,
    paymasterVerificationGasLimit: BigInt(body.paymasterVerificationGasLimit),
    paymasterPostOpGasLimit: BigInt(body.paymasterPostOpGasLimit),
  };
}

// The bundler rejects fees below its own quote, and a public RPC's estimate is
// not that quote, so ask the bundler.
async function bundlerGasPrice() {
  const response = await fetch(config.bundlerUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "pimlico_getUserOperationGasPrice",
      params: [],
    }),
  });
  const { result, error } = await response.json();
  if (error) throw new Error(`bundler gas price: ${error.message}`);
  return {
    maxFeePerGas: BigInt(result.fast.maxFeePerGas),
    maxPriorityFeePerGas: BigInt(result.fast.maxPriorityFeePerGas),
  };
}
