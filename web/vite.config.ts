import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api/events': {
        target: 'http://localhost:8080',
        headers: { 'Connection': 'keep-alive' },
      },
      '/api': 'http://localhost:8080',
      '/rpc': 'http://localhost:8080',
    },
  },
})
