// Pele's src/zoom.ts, as nimaki ports it (src/nimaki/zoom.nim): tools/peletests.nim points the
// tests' `../src/zoom.js` here.
import { createRequire } from 'node:module';

const bridge = createRequire(import.meta.url)(process.env.NIMAKI_BRIDGE);

export function frame(natural, box, scale, x, y) {
  return bridge.nimakiFrame(natural, box, scale, x, y);
}
export function enableZoom(element, options = {}) {
  return bridge.nimakiEnableZoom(element, options);
}
export function zoomWith(element, options, observe) {
  return bridge.nimakiZoomWith(element, options, observe);
}
