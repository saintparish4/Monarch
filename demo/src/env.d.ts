/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_PAYMASTER_ADDRESS: string
  readonly VITE_GUESTBOOK_ADDRESS: string
  readonly VITE_APP_ADDRESS: string
  readonly VITE_RPC_URL?: string
  readonly VITE_BUNDLER_URL: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
