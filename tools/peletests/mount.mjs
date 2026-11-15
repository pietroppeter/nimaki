// Pele's src/mount.ts, as nimaki ports it (src/nimaki/mount.nim): tools/peletests.nim points the
// tests' `../src/mount.js` here, so that mount.test.ts checks the port with the engine it gives.
import { createRequire } from 'node:module';

const bridge = createRequire(import.meta.url)(process.env.NIMAKI_BRIDGE);

export function mountWith(engine, element, text, options = {}) {
  return bridge.nimakiMountWith(engine, element, text, options);
}
