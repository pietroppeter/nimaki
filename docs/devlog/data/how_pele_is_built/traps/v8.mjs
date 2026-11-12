// What V8 (Node) answers for the number operations Pele uses, for compare.nim to check against
// Nim. Writes one JSON file:
//   node v8.mjs out.json
// `cases`: a few exact values; `libm`: bit patterns of Math.* results on seeded random inputs.
import { writeFileSync } from 'node:fs';

let s = 12345 >>> 0; // the LCG of Pele's tests/support/corpus.ts
const rnd = () => (s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296;
const f64 = new Float64Array(1);
const u64 = new BigUint64Array(f64.buffer);
const bits = (x) => { f64[0] = x; return u64[0].toString(16).padStart(16, '0'); };

const cases = {
  toFixed0: [0.5, 1.5, 2.5, 12.5, -2.5, 0.125 * 100].map((x) => [x, x.toFixed(0)]),
  toFixed2: [1.005, 2.675, 0.125, 1e21].map((x) => [x, x.toFixed(2)]),
  round: [2.5, -2.5, -0.5, 0.49999999999999994, 1.4999999999999998].map((x) => [x, Math.round(x)]),
  string: [1, -0, 0.1 + 0.2, 1 / 3, 1e-7, 1e21, 123456789012345680000, 42.96, 5e-324].map((x) => [x, String(x)]),
  maxNaN: [[1, NaN, String(Math.max(1, NaN))], [NaN, 1, String(Math.max(NaN, 1))]],
  utf16: ['a', 'é', '中', '😀'].map((t) => [t, t.length]),
};

const N = 100000;
const libm = [];
for (let i = 0; i < N; i++) {
  const a = (rnd() - 0.5) * 20;
  const b = (rnd() - 0.5) * 2000;
  libm.push([a, b, Math.sin(a), Math.cos(a), Math.atan2(a, b), Math.hypot(a, b), Math.pow(Math.abs(b), a / 10),
    Math.log10(Math.abs(b) + 1), Math.sqrt(Math.abs(b))].map(bits).join(' '));
}
writeFileSync(process.argv[2], JSON.stringify({ node: process.version, cases, libm }));
