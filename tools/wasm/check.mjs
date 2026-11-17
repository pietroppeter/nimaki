// Checks the WebAssembly build against Pele: every case of the corpus drawn by both in one Node,
// with the referee's fixed `now`, compared byte for byte (an error must be an error in both).
// It prints one ERROR line per difference and a summary last.
//
//   sh tools/wasm/build.sh && TZ=UTC node tools/wasm/check.mjs
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadWasm } from './load.mjs';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const pkg = resolve(process.env.PELE_PACKAGE ?? join(repo, 'reference/npm/package'));
const pele = await import(pathToFileURL(join(pkg, 'dist/pele.js')).href);
const wasm = await loadWasm(join(repo, 'build/wasm/nimaki.wasm'));
const now = 1_700_000_000_000;
const draw = (f) => { try { return f(); } catch { return null; } };
let same = 0, different = 0;
const cases = JSON.parse(readFileSync(join(repo, 'corpus/cases.json'), 'utf8')).cases;
for (const c of cases) {
  const a = draw(() => pele.render(c.source, { now }).svg);
  const b = draw(() => wasm(c.source, now).svg);
  if (a === b) { same++; continue; }
  different++;
  if (different <= 20) {
    let at = 0;
    while (a && b && at < Math.min(a.length, b.length) && a[at] === b[at]) at++;
    console.log(`ERROR ${c.id} (${c.type}): ${a === null ? 'Pele throws' : b === null ? 'wasm throws' : 'from character ' + at + ': ' + JSON.stringify(b.slice(at, at + 60)) + ' for ' + JSON.stringify(a.slice(at, at + 60))}`);
  }
}
console.log(`wasm check: ${cases.length} cases, ${same} identical to Pele, ${different} different`);
process.exitCode = different > 0 ? 1 : 0;
