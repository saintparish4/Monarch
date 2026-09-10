import 'dotenv/config'
import express from 'express'
import cors from 'cors'
import {createPublicClient, http, isAddress, type Address, type Hex} from 'viem'
import {privateKeyToAccount} from 'viem/accounts'
import {baseSepolia} from 'viem/chains'

import {paymasterAbi} from '../shared/abi.js'
import {
  encodeInitCode,
  encodePaymasterAndData,
  encodeSponsoredData,
  packAccountGasLimits,
  packGasFees,
  STUB_SIGNATURE,
} from '../shared/monarch.js'

/**
 * The sponsor backend.
 *
 * This is the piece an app actually operates: it decides *whether* to pay for a
 * given user's operation, and it holds the only key that can authorise that.
 * The decision function here is `shouldSponsor`, and it is deliberately the
 * dumbest possible version — see the comment on it.
 *
 * The key never leaves this process. That is the entire reason the demo is two
 * processes instead of one: a browser that could sign sponsorships would be a
 * browser that could drain the app's budget.
 */

function required(name: string): string {
  const v = process.env[name]
  if (!v) throw new Error(`missing required env var ${name} (copy .env.example to .env)`)
  return v
}

const PAYMASTER = required('PAYMASTER_ADDRESS') as Address
const APP = required('APP_ADDRESS') as Address
const TTL = Number(process.env.SPONSORSHIP_TTL_SEC ?? 120)
const PORT = Number(process.env.PORT ?? 8787)

const signer = privateKeyToAccount(required('APP_SIGNER_PRIVATE_KEY') as Hex)
const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(process.env.RPC_URL ?? 'https://sepolia.base.org'),
})

/** Gas the paymaster's own two phases need. Measured, from the gas table in
 *  the root README: sponsored validation 11,997 and postOp 11,524. The headroom
 *  covers a cold `apps[app]` read on a chain where the slot has not been
 *  touched this block. */
const PAYMASTER_VERIFICATION_GAS_LIMIT = 80_000n
const PAYMASTER_POSTOP_GAS_LIMIT = 60_000n

type UserOpParams = {
  sender: Address
  nonce: string
  factory?: Address
  factoryData?: Hex
  callData: Hex
  callGasLimit?: string
  verificationGasLimit?: string
  preVerificationGas?: string
  maxFeePerGas?: string
  maxPriorityFeePerGas?: string
}

/**
 * The policy hook.
 *
 * A real app puts its business rules here: is this a signed-in user, are they
 * inside their daily allowance, is the call one we are willing to pay for. The
 * demo sponsors any call to the guestbook and nothing else, because "sponsor
 * everything" is how an app wakes up to an empty budget.
 *
 * Note what this does NOT do: it does not check the user's balance, identity,
 * or history. Sponsorship is the app spending its own money on a stranger, and
 * the only real defence is that this function said yes.
 */
const GUESTBOOK = (process.env.GUESTBOOK_ADDRESS ?? '').toLowerCase()
function shouldSponsor(op: UserOpParams): {ok: true} | {ok: false; reason: string} {
  if (!isAddress(op.sender)) return {ok: false, reason: 'sender is not an address'}
  if (GUESTBOOK && !op.callData.toLowerCase().includes(GUESTBOOK.slice(2))) {
    return {ok: false, reason: 'this app only sponsors calls to the guestbook'}
  }
  return {ok: true}
}

const app = express()
app.use(cors())
app.use(express.json({limit: '128kb'}))

app.get('/api/health', (_req, res) => {
  res.json({ok: true, paymaster: PAYMASTER, app: APP, signer: signer.address})
})

/**
 * Returns the 98 bytes of `paymasterData` for a sponsored operation.
 *
 * Ordering matters and is not obvious: the digest covers the *final* gas
 * values, so this can only run after the bundler has estimated them, but it
 * must run before the account owner signs the operation — `getSponsorshipHash`
 * does not cover `userOp.signature`, while the account's own signature covers
 * `paymasterAndData`. Sponsor first, then sign. Reversing it produces an AA24
 * from the account.
 */
app.post('/api/sponsor', async (req, res) => {
  try {
    const op = req.body?.userOperation as UserOpParams | undefined
    if (!op) return res.status(400).json({error: 'missing userOperation'})

    const verdict = shouldSponsor(op)
    if (!verdict.ok) return res.status(403).json({error: verdict.reason})

    const now = Math.floor(Date.now() / 1000)
    // `validAfter` is 0 rather than `now`: a signer clock a few seconds ahead
    // of the chain would otherwise reject its own fresh sponsorship.
    const validAfter = 0
    const validUntil = now + TTL

    // Build the exact bytes the contract will hash: paymasterData with a stub
    // signature in place. The contract hashes paymasterAndData[:85], which
    // stops before the signature, so the stub's contents cannot affect the
    // digest — only its length matters, and that is fixed at 65.
    const stubData = encodeSponsoredData({
      app: APP,
      validUntil,
      validAfter,
      signature: STUB_SIGNATURE,
    })

    const packed = {
      sender: op.sender,
      nonce: BigInt(op.nonce),
      initCode: encodeInitCode(op.factory, op.factoryData),
      callData: op.callData,
      accountGasLimits: packAccountGasLimits(
        BigInt(op.verificationGasLimit ?? 0),
        BigInt(op.callGasLimit ?? 0),
      ),
      preVerificationGas: BigInt(op.preVerificationGas ?? 0),
      gasFees: packGasFees(
        BigInt(op.maxPriorityFeePerGas ?? 0),
        BigInt(op.maxFeePerGas ?? 0),
      ),
      paymasterAndData: encodePaymasterAndData({
        paymaster: PAYMASTER,
        paymasterVerificationGasLimit: PAYMASTER_VERIFICATION_GAS_LIMIT,
        paymasterPostOpGasLimit: PAYMASTER_POSTOP_GAS_LIMIT,
        paymasterData: stubData,
      }),
      signature: '0x' as Hex,
    }

    // Ask the contract for the digest rather than reimplementing the packing.
    // The packing includes both paymaster gas limits and the chain id; getting
    // it subtly wrong off-chain is the failure mode `getSponsorshipHash` is
    // public to prevent.
    const digest = await publicClient.readContract({
      address: PAYMASTER,
      abi: paymasterAbi,
      functionName: 'getSponsorshipHash',
      args: [packed],
    })

    // `signMessage({raw})` applies the EIP-191 prefix, which is what
    // `MessageHashUtils.toEthSignedMessageHash` expects on the other side.
    const signature = await signer.signMessage({message: {raw: digest}})

    res.json({
      paymaster: PAYMASTER,
      paymasterData: encodeSponsoredData({app: APP, validUntil, validAfter, signature}),
      paymasterVerificationGasLimit: PAYMASTER_VERIFICATION_GAS_LIMIT.toString(),
      paymasterPostOpGasLimit: PAYMASTER_POSTOP_GAS_LIMIT.toString(),
      validUntil,
      validAfter,
    })
  } catch (err) {
    console.error('[sponsor] failed:', err)
    res.status(500).json({error: err instanceof Error ? err.message : 'unknown error'})
  }
})

app.listen(PORT, () => {
  console.log(`sponsor api  http://localhost:${PORT}`)
  console.log(`  paymaster  ${PAYMASTER}`)
  console.log(`  app        ${APP}`)
  console.log(`  signer     ${signer.address}  (must match apps[app].signer on-chain)`)
})
