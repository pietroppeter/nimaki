// Pele's vitest configuration (vitest.config.ts at the pin), with Pele's src/index.js replaced by
// nimaki (index.mjs), and src/mount.js, src/zoom.js and src/text/measurer.js by nimaki's ports.
// tools/peletests.nim copies this file into its copy of Pele and sets
// NIMAKI_SHIM, NIMAKI_SETUP and NIMAKI_BRIDGE.
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const src = fileURLToPath(new URL('./src', import.meta.url));
// The ports of Pele's browser side sit beside index.mjs: mount.mjs, zoom.mjs, measurer.mjs.
const shims = dirname(process.env.NIMAKI_SHIM ?? '.');

export default defineConfig({
  resolve: {
    alias: [
      { find: /^(\.\.\/)+src\/index\.js$/, replacement: process.env.NIMAKI_SHIM },
      // Only what a test imports itself: Pele's own files import these with paths of their own.
      { find: /^(\.\.\/)+src\/mount\.js$/, replacement: join(shims, 'mount.mjs') },
      { find: /^(\.\.\/)+src\/zoom\.js$/, replacement: join(shims, 'zoom.mjs') },
      { find: /^(\.\.\/)+src\/text\/measurer\.js$/, replacement: join(shims, 'measurer.mjs') },
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
