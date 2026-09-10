import {concat, pad, toHex, type Address, type Hex} from 'viem'

/**
 * Monarch's `paymasterData` layout, which is everything after the 52 bytes the
 * ERC-4337 v0.7+ standard reserves at the front of `paymasterAndData`:
 *
 *     [0:20]   paymaster address                 <- standard
 *     [20:36]  paymasterVerificationGasLimit     <- standard
 *     [36:52]  paymasterPostOpGasLimit           <- standard
 *     [52]     mode                              <- ours, from here down
 *     [53:73]  app address
 *     [73:79]  validUntil  (uint48)
 *     [79:85]  validAfter  (uint48)
 *     [85:150] ECDSA signature (65 bytes)
 *
 * The contract checks the total length as an *equality*, not a minimum, so a
 * byte of slop here is a rejected operation rather than a silent mis-decode.
 * These constants exist because the implementation Monarch replaced read its
 * mode byte at index 20 — the v0.6 position, which under v0.7+ is the first
 * byte of a gas limit.
 */
export const PAYMASTER_DATA_OFFSET = 52
export const SIGNATURE_OFFSET = PAYMASTER_DATA_OFFSET + 33
export const SPONSORED_DATA_LENGTH = PAYMASTER_DATA_OFFSET + 98

export const Mode = {Deposit: 0x00, Sponsored: 0x01} as const

/**
 * A syntactically valid signature that will never recover to the app signer.
 * Used for gas estimation, where the bytes must be the right shape and the
 * right length but need not be genuine. `s` is deliberately in the low half of
 * the curve order so the malleability guard does not reject it for the wrong
 * reason and mask a real error.
 */
export const STUB_SIGNATURE: Hex = ('0x' +
  '1'.repeat(64) + // r — any value below the curve order; this one recovers to
  //      a junk address, which is fine: per ERC-4337, `eth_estimateUserOperationGas`
  //      does not enforce signature validity. What must be right is the LENGTH,
  //      because the contract checks `paymasterAndData.length` as an equality.
  '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0' + // s — exactly
  //      n/2, the largest value the malleability guard accepts. Anything above it
  //      is rejected as malleable, which would look like a signing bug rather than
  //      a deliberately fake signature.
  '1b') as Hex // v

/** The 98 bytes of `paymasterData` for sponsored mode. */
export function encodeSponsoredData(args: {
  app: Address
  validUntil: number
  validAfter: number
  signature: Hex
}): Hex {
  return concat([
    toHex(Mode.Sponsored, {size: 1}),
    args.app,
    pad(toHex(args.validUntil), {size: 6}),
    pad(toHex(args.validAfter), {size: 6}),
    args.signature,
  ])
}

/**
 * The full `paymasterAndData`, as the contract slices it.
 *
 * Only needed to reproduce the digest `getSponsorshipHash` computes — viem
 * assembles this itself from the fields a paymaster action returns, so the
 * browser never calls this. The server does, because the hash covers
 * `paymasterAndData[:85]`, which includes *both* paymaster gas limits. Signing
 * a hand-enumerated subset of fields instead is how those two limits end up
 * unsigned and malleable by the bundler.
 */
export function encodePaymasterAndData(args: {
  paymaster: Address
  paymasterVerificationGasLimit: bigint
  paymasterPostOpGasLimit: bigint
  paymasterData: Hex
}): Hex {
  return concat([
    args.paymaster,
    pad(toHex(args.paymasterVerificationGasLimit), {size: 16}),
    pad(toHex(args.paymasterPostOpGasLimit), {size: 16}),
    args.paymasterData,
  ])
}

/**
 * `accountGasLimits` and `gasFees` are each two uint128s in one word.
 *
 * The order is not symmetric between them and is easy to get backwards:
 * `accountGasLimits` is (verificationGasLimit << 128 | callGasLimit), while
 * `gasFees` is (maxPriorityFeePerGas << 128 | maxFeePerGas). Verified against
 * `UserOperationLib.unpackVerificationGasLimit` / `unpackMaxFeePerGas` in
 * eth-infinitism v0.8. Swapping either pair produces a digest that is wrong but
 * well-formed, so the failure appears as an unexplained AA34 rather than a
 * type error.
 */
export function packUints(high: bigint, low: bigint): Hex {
  return concat([pad(toHex(high), {size: 16}), pad(toHex(low), {size: 16})])
}

export function packAccountGasLimits(verificationGasLimit: bigint, callGasLimit: bigint): Hex {
  return packUints(verificationGasLimit, callGasLimit)
}

export function packGasFees(maxPriorityFeePerGas: bigint, maxFeePerGas: bigint): Hex {
  return packUints(maxPriorityFeePerGas, maxFeePerGas)
}

/** `initCode` is factory ++ factoryData, or empty once the account exists. */
export function encodeInitCode(factory?: Address, factoryData?: Hex): Hex {
  if (!factory || factory === '0x') return '0x'
  return concat([factory, factoryData ?? '0x'])
}
