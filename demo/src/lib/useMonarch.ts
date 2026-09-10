import {useCallback, useEffect, useMemo, useState} from 'react'
import {createPublicClient, formatEther, http, type Address} from 'viem'
import {baseSepolia} from 'viem/chains'
import {createBundlerClient, type GetPaymasterDataParameters} from 'viem/account-abstraction'
import {toSimpleSmartAccount} from 'permissionless/accounts'

import {config} from './config'
import {loadBurner} from './burner'
import {guestbookAbi, paymasterAbi} from '../../shared/abi'

export type Entry = {author: Address; timestamp: bigint; message: string}

export type Phase =
  | {kind: 'idle'}
  | {kind: 'building'}
  | {kind: 'sponsoring'}
  | {kind: 'submitting'}
  | {kind: 'mining'; userOpHash: `0x${string}`}
  | {kind: 'done'; txHash: `0x${string}`; actualGasCost: bigint}
  | {kind: 'error'; message: string}

const publicClient = createPublicClient({chain: baseSepolia, transport: http(config.rpcUrl)})

/**
 * Asks our own backend for a sponsorship.
 *
 * viem calls `getPaymasterStubData` before gas estimation and
 * `getPaymasterData` after it. Only the second one can produce a real
 * signature, because the digest covers the final gas values — so the stub
 * returns correctly shaped bytes purely so the estimate accounts for the
 * paymaster's own validation and postOp cost.
 */
function makePaymasterActions(onSponsoring: () => void) {
  const gasLimits = {
    paymasterVerificationGasLimit: 80_000n,
    paymasterPostOpGasLimit: 60_000n,
  }
  return {
    async getPaymasterStubData() {
      const {STUB_SIGNATURE, encodeSponsoredData} = await import('../../shared/monarch')
      return {
        paymaster: config.paymaster,
        paymasterData: encodeSponsoredData({
          app: import.meta.env.VITE_APP_ADDRESS as Address,
          validUntil: Math.floor(Date.now() / 1000) + 120,
          validAfter: 0,
          signature: STUB_SIGNATURE,
        }),
        ...gasLimits,
      }
    },
    async getPaymasterData(params: GetPaymasterDataParameters) {
      onSponsoring()
      const res = await fetch('/api/sponsor', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({
          userOperation: {
            sender: params.sender,
            nonce: params.nonce?.toString() ?? '0',
            factory: params.factory,
            factoryData: params.factoryData,
            callData: params.callData,
            callGasLimit: params.callGasLimit?.toString(),
            verificationGasLimit: params.verificationGasLimit?.toString(),
            preVerificationGas: params.preVerificationGas?.toString(),
            maxFeePerGas: params.maxFeePerGas?.toString(),
            maxPriorityFeePerGas: params.maxPriorityFeePerGas?.toString(),
          },
        }),
      })
      if (!res.ok) {
        const body = (await res.json().catch(() => ({}))) as {error?: string}
        throw new Error(body.error ?? `sponsor api returned ${res.status}`)
      }
      const data = (await res.json()) as {
        paymaster: Address
        paymasterData: `0x${string}`
        paymasterVerificationGasLimit: string
        paymasterPostOpGasLimit: string
      }
      return {
        paymaster: data.paymaster,
        paymasterData: data.paymasterData,
        paymasterVerificationGasLimit: BigInt(data.paymasterVerificationGasLimit),
        paymasterPostOpGasLimit: BigInt(data.paymasterPostOpGasLimit),
      }
    },
  }
}

export function useMonarch() {
  const owner = useMemo(() => loadBurner(), [])
  const [smartAccount, setSmartAccount] = useState<Address>()
  const [ownerBalance, setOwnerBalance] = useState<bigint>()
  const [appBudget, setAppBudget] = useState<bigint>()
  const [entries, setEntries] = useState<Entry[]>([])
  const [phase, setPhase] = useState<Phase>({kind: 'idle'})

  const account = useMemo(
    () => toSimpleSmartAccount({client: publicClient, owner}),
    [owner],
  )

  const refresh = useCallback(async () => {
    const [addr, bal, latest] = await Promise.all([
      account.then((a) => a.address),
      publicClient.getBalance({address: owner.address}),
      publicClient.readContract({
        address: config.guestbook,
        abi: guestbookAbi,
        functionName: 'latest',
        args: [10n],
      }),
    ])
    setSmartAccount(addr)
    setOwnerBalance(bal)
    setEntries([...latest] as Entry[])

    const appAddress = import.meta.env.VITE_APP_ADDRESS as Address | undefined
    if (appAddress) {
      const [budget] = await publicClient.readContract({
        address: config.paymaster,
        abi: paymasterAbi,
        functionName: 'apps',
        args: [appAddress],
      })
      setAppBudget(budget)
    }
  }, [account, owner.address])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const sign = useCallback(
    async (message: string) => {
      try {
        setPhase({kind: 'building'})
        const acct = await account
        const bundlerClient = createBundlerClient({
          account: acct,
          client: publicClient,
          transport: http(config.bundlerUrl),
          paymaster: makePaymasterActions(() => setPhase({kind: 'sponsoring'})),
        })

        const userOpHash = await bundlerClient.sendUserOperation({
          calls: [
            {
              to: config.guestbook,
              abi: guestbookAbi,
              functionName: 'sign',
              args: [message],
            },
          ],
        })
        setPhase({kind: 'mining', userOpHash})

        const receipt = await bundlerClient.waitForUserOperationReceipt({hash: userOpHash})
        if (!receipt.success) throw new Error('the operation reverted on chain')

        setPhase({
          kind: 'done',
          txHash: receipt.receipt.transactionHash,
          actualGasCost: receipt.actualGasCost,
        })
        await refresh()
      } catch (err) {
        setPhase({kind: 'error', message: err instanceof Error ? err.message : String(err)})
      }
    },
    [account, refresh],
  )

  return {
    ownerAddress: owner.address,
    smartAccount,
    ownerBalance,
    ownerBalanceEth: ownerBalance === undefined ? undefined : formatEther(ownerBalance),
    appBudget,
    appBudgetEth: appBudget === undefined ? undefined : formatEther(appBudget),
    entries,
    phase,
    sign,
    refresh,
  }
}
