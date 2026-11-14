// Pele's vitest configuration (vitest.config.ts at the pin), with Pele's src/index.js replaced by
// nimaki (index.mjs). tools/peletests.nim copies this file into its copy of Pele and sets
// NIMAKI_SHIM, NIMAKI_SETUP and NIMAKI_BRIDGE.
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';

const src = fileURLToPath(new URL('./src', import.meta.url));

export default defineConfig({
  resolve: {
    alias: [
      { find: /^(\.\.\/)+src\/index\.js$/, replacement: process.env.NIMAKI_SHIM },
      { find: /^PELE_SRC\//, replacement: src + '/' },
    ],
  },
  test: {
    globals: true,
    pool: 'threads',
    testTimeout: 60000,
    include: ['tests/**/*.{test,spec}.{ts,js}'],
    exclude: ['tests/website/**', '**/node_modules/**'],
    setupFiles: [process.env.NIMAKI_SETUP],
  },
});
