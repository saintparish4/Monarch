import {generatePrivateKey, privateKeyToAccount, type PrivateKeyAccount} from 'viem/accounts'

const KEY = 'monarch.demo.burner'

/**
 * A throwaway owner key, kept in localStorage.
 *
 * This is the point of the demo, so it is worth being precise about it: this
 * key is generated in the browser and is funded with nothing, ever. It cannot
 * pay for gas because it has no ETH to pay with. Every transaction it sends is
 * paid for by the app's budget on the paymaster.
 *
 * localStorage is the correct amount of security for a key worth zero. Do not
 * copy this pattern for a key worth more than zero.
 */
export function loadBurner(): PrivateKeyAccount {
  let pk = localStorage.getItem(KEY)
  if (!pk) {
    pk = generatePrivateKey()
    localStorage.setItem(KEY, pk)
  }
  return privateKeyToAccount(pk as `0x${string}`)
}

export function resetBurner(): void {
  localStorage.removeItem(KEY)
}
