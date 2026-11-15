// Pele's src/text/measurer.ts for the tests: Pele's own module, with the canvas half nimaki ports
// (src/nimaki/text/measurer.nim) in place of Pele's. tools/peletests.nim points the tests'
// `../src/text/measurer.js` here; Pele's own files still import Pele's.
import { createRequire } from 'node:module';

const bridge = createRequire(import.meta.url)(process.env.NIMAKI_BRIDGE);

// `Style` is a const enum in Pele's TypeScript, which vitest keeps as an object that tests read.
export { metricsMeasurer, Style } from 'PELE_SRC/text/measurer.js';

export function canvasMeasurer(fontFamily, monoFamily = 'monospace') {
  const m = bridge.nimakiCanvasMeasurer(fontFamily, monoFamily);
  if (m === null) return null;
  return { width: (text, size, style) => bridge.nimakiCanvasWidth(m, text, size, style) };
}
export function forgetTextWidths() {
  bridge.nimakiForgetTextWidths();
}
