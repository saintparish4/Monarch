import type {Address} from 'viem'

function env(name: string): string {
  const v = import.meta.env[name as keyof ImportMetaEnv] as string | undefined
  if (!v) throw new Error(`missing ${name} — copy .env.example to .env and fill it in`)
  return v
}

export const config = {
  paymaster: env('VITE_PAYMASTER_ADDRESS') as Address,
  guestbook: env('VITE_GUESTBOOK_ADDRESS') as Address,
  rpcUrl: import.meta.env.VITE_RPC_URL ?? 'https://sepolia.base.org',
  bundlerUrl: env('VITE_BUNDLER_URL'),
}
