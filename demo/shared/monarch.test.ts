import {strict as assert} from 'node:assert'
import {test} from 'node:test'
import {readFileSync} from 'node:fs'
import {fileURLToPath} from 'node:url'
import {size} from 'viem'

import {
  PAYMASTER_DATA_OFFSET,
  SIGNATURE_OFFSET,
  SPONSORED_DATA_LENGTH,
  STUB_SIGNATURE,
  encodePaymasterAndData,
  encodeSponsoredData,
  packAccountGasLimits,
  packGasFees,
} from './monarch.js'

/**
 * These tests exist because the TypeScript encoder and `Constants.sol` are two
 * copies of one byte layout, and nothing in either language makes them agree.
 *
 * A drift between them does not produce a type error or a crash. It produces a
 * `MalformedPaymasterData` at best, and at worst an operation that decodes a
 * plausible-but-wrong app address. So the constants are read out of the Solidity
 * source at test time rather than duplicated here.
 */
const constantsSol = readFileSync(
  fileURLToPath(new URL('../../contracts/libraries/Constants.sol', import.meta.url)),
  'utf8',
)

function solConstant(name: string): number {
  const m = constantsSol.match(
    new RegExp(`uint256 internal constant ${name} = ([^;]+);`),
  )
  assert.ok(m, `${name} not found in Constants.sol`)
  // The file writes these as expressions (`PAYMASTER_DATA_OFFSET + 21`), so
  // resolve them against the values already parsed rather than eval'ing blind.
  const expr = m[1].trim()
  const resolved = expr
    .replace(/PAYMASTER_DATA_OFFSET/g, String(solConstantRaw('PAYMASTER_DATA_OFFSET')))
    .replace(/_/g, '')
  assert.match(resolved, /^[\d+\s*]+$/, `unexpected expression for ${name}: ${expr}`)
  return Number(new Function(`return (${resolved})`)())
}

function solConstantRaw(name: string): number {
  const m = constantsSol.match(new RegExp(`uint256 internal constant ${name} = (\\d+);`))
  assert.ok(m, `${name} not found as a literal in Constants.sol`)
  return Number(m[1])
}

test('offsets match Constants.sol', () => {
  assert.equal(PAYMASTER_DATA_OFFSET, solConstant('PAYMASTER_DATA_OFFSET'))
  assert.equal(SIGNATURE_OFFSET, solConstant('SIGNATURE_OFFSET'))
  assert.equal(SPONSORED_DATA_LENGTH, solConstant('SPONSORED_DATA_LENGTH'))
})

test('the stub signature is exactly 65 bytes', () => {
  // The contract checks total length as an equality. A stub of the wrong length
  // makes gas estimation fail with a malformed-data revert that reads like a
  // bundler problem.
  assert.equal(size(STUB_SIGNATURE), 65)
})

test('sponsored paymasterAndData is exactly SPONSORED_DATA_LENGTH bytes', () => {
  const paymasterData = encodeSponsoredData({
    app: '0x1111111111111111111111111111111111111111',
    validUntil: 1_800_000_000,
    validAfter: 0,
    signature: STUB_SIGNATURE,
  })
  assert.equal(size(paymasterData), 98)

  const full = encodePaymasterAndData({
    paymaster: '0x2222222222222222222222222222222222222222',
    paymasterVerificationGasLimit: 80_000n,
    paymasterPostOpGasLimit: 60_000n,
    paymasterData,
  })
  assert.equal(size(full), SPONSORED_DATA_LENGTH)
})

test('the app address lands at APP_OFFSET, not one byte either side', () => {
  const app = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa'
  const full = encodePaymasterAndData({
    paymaster: '0x2222222222222222222222222222222222222222',
    paymasterVerificationGasLimit: 80_000n,
    paymasterPostOpGasLimit: 60_000n,
    paymasterData: encodeSponsoredData({
      app,
      validUntil: 1_800_000_000,
      validAfter: 0,
      signature: STUB_SIGNATURE,
    }),
  })
  const appOffset = solConstant('APP_OFFSET')
  const slice = '0x' + full.slice(2 + appOffset * 2, 2 + (appOffset + 20) * 2)
  assert.equal(slice.toLowerCase(), app.toLowerCase())

  // The mode byte sits immediately before it.
  const modeOffset = solConstant('MODE_OFFSET')
  assert.equal(full.slice(2 + modeOffset * 2, 2 + (modeOffset + 1) * 2), '01')
})

test('accountGasLimits and gasFees pack in the orders EntryPoint v0.8 unpacks', () => {
  // accountGasLimits: high 128 = verificationGasLimit, low = callGasLimit.
  // gasFees:          high 128 = maxPriorityFeePerGas, low = maxFeePerGas.
  // The two are NOT the same shape, and swapping either pair yields a digest
  // that is wrong but well-formed.
  const agl = packAccountGasLimits(0xaaan, 0xbbbn)
  assert.equal(agl, '0x' + '0'.repeat(29) + 'aaa' + '0'.repeat(29) + 'bbb')

  const fees = packGasFees(0x111n, 0x222n)
  assert.equal(fees, '0x' + '0'.repeat(29) + '111' + '0'.repeat(29) + '222')
})
