// Pele's public API (src/index.ts at the pin), drawn by nimaki: tools/peletests.nim points Pele's
// test suites here instead of Pele's own src/index.js. `render`, `detectType` and `supports`
// call nimaki's JavaScript build (bridge.nim); the text measurer stays Pele's, as in difftest.
// What nimaki does not provide (parse, mount, zoom) throws, and the tests that use it are
// counted apart.
import { createRequire } from 'node:module';
import { PeleError } from 'PELE_SRC/errors.js';
export { PeleError };

const require = createRequire(import.meta.url);
const bridge = require(process.env.NIMAKI_BRIDGE);

// PeleError is Pele's own class, so that a PeleError from nimaki and one from a part of Pele a test calls
// directly (a parser, say) are the same thing to `instanceof`.

export class NotInNimaki extends Error {
  constructor(what) {
    super(`nimaki does not provide ${what}`);
    this.name = 'NotInNimaki';
    // read by setup.mjs: the test used an API nimaki does not have, whatever it caught
    globalThis.__nimakiMissing = what;
  }
}

export function render(source, options = {}) {
  if (typeof source !== 'string') throw new TypeError('render() takes diagram text or a model that parse() returned.');
  try {
    return bridge.nimakiRender(source, options);
  } catch (e) {
    if (e && e.peleError) throw new PeleError(e.message, e.code, e);
    throw e;
  }
}

export function detectType(text) {
  return bridge.nimakiDetectType(text);
}

export function supports(text) {
  return bridge.nimakiSupports(text);
}

export function parse() { throw new NotInNimaki('parse()'); }
export function mount() { throw new NotInNimaki('mount()'); }
export function enableZoom() { throw new NotInNimaki('enableZoom()'); }
export function register() { throw new NotInNimaki('register()'); }
export function registered() { throw new NotInNimaki('registered()'); }
export { forgetTextWidths } from 'PELE_SRC/text/measurer.js';
