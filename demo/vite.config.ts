import {defineConfig} from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // The sponsor signer must never reach the browser, so the signing endpoint
    // is a separate process and the dev server proxies to it. In production
    // this is your backend; the only thing that changes is the origin.
    proxy: {'/api': {target: 'http://localhost:8787', changeOrigin: true}},
  },
})
