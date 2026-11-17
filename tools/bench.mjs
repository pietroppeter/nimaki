// The JavaScript side of tools/bench.nim: how long Pele's npm package and nimaki's JavaScript
// build take to draw the corpus, in the same Node process, on the same cases.
//
//   TZ=UTC node tools/bench.mjs CASES.json RESULT.json [--rounds:N] [--engines:pele,nimaki,wasm]
//                                [--pele:DIR] [--nimaki:FILE] [--wasm:FILE] [type...]
//
// CASES.json is the corpus (`{"cases": [{"type", "source"}...]}`); RESULT.json gets, for each
// engine, the time to load it, the time of its first pass over the whole corpus (cold: the
// JavaScript engine has not yet compiled the hot code), and for each diagram type the time of
// every round (warm), in milliseconds. Pele is `dist/pele.js` of its package, the file the
// oracle loads; nimaki is the file a page loads (`build/web/nimaki.js`, tools/webbuild.nim),
// read the way a browser reads a script; wasm is nimaki's C build compiled to WebAssembly
// (`build/wasm/nimaki.wasm`, tools/wasm/build.sh), loaded by tools/wasm/load.mjs. All draw with a fixed `now`, as the referee does.
//
// The rounds alternate the engines (Pele, nimaki, wasm, Pele...), so that a slow moment of the
// machine falls on both. Each SVG's length is summed, as a check that both drew the same thing.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { runInThisContext } from 'node:vm';
import { performance } from 'node:perf_hooks';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const files = args.filter((a) => !a.startsWith('--'));
const opt = (name, fallback) => {
  const a = args.find((x) => x.startsWith(`--${name}:`));
  return a ? a.slice(name.length + 3) : fallback;
};
const [casesPath, resultPath, ...only] = files;
const rounds = Number(opt('rounds', '5'));
const engines = opt('engines', 'pele,nimaki').split(',');
const pelePkg = resolve(opt('pele', process.env.PELE_PACKAGE ?? join(repo, 'reference/npm/package')));
const nimakiFile = resolve(opt('nimaki', join(repo, 'build/web/nimaki.js')));
const wasmFile = resolve(opt('wasm', join(repo, 'build/wasm/nimaki.wasm')));
const now = 1_700_000_000_000;

const byType = new Map();
for (const c of JSON.parse(readFileSync(casesPath, 'utf8')).cases) {
  if (only.length > 0 && !only.includes(c.type)) continue;
  if (!byType.has(c.type)) byType.set(c.type, []);
  byType.get(c.type).push(c.source);
}
const types = [...byType.keys()].sort();

async function load(engine) {
  const start = performance.now();
  let render;
  if (engine === 'pele') {
    const pele = await import(pathToFileURL(join(pelePkg, 'dist/pele.js')).href);
    render = (s) => pele.render(s, { now });
  } else if (engine === 'wasm') {
    const { loadWasm } = await import(pathToFileURL(join(repo, 'tools/wasm/load.mjs')).href);
    const draw = await loadWasm(wasmFile);
    render = (s) => draw(s, now);
  } else {
    runInThisContext(readFileSync(nimakiFile, 'utf8'), { filename: nimakiFile });
    const nimaki = globalThis.nimaki;
    render = (s) => nimaki.render(s, { now });
  }
  return { render, load: performance.now() - start };
}

// One pass over the cases of one type: the time, the SVG bytes drawn, the cases that threw.
function pass(render, sources) {
  let chars = 0, errors = 0;
  const start = performance.now();
  for (const s of sources) {
    try { chars += render(s).svg.length; } catch { errors += 1; }
  }
  return { ms: performance.now() - start, chars, errors };
}

const result = { node: process.version, rounds, engines: {} };
const loaded = {};
for (const e of engines) {
  loaded[e] = await load(e);
  // The cold pass: every type once, in a fresh engine.
  const start = performance.now();
  for (const t of types) pass(loaded[e].render, byType.get(t));
  result.engines[e] = { load: loaded[e].load, cold: performance.now() - start, types: {} };
}
for (const t of types) {
  for (const e of engines) result.engines[e].types[t] = { cases: byType.get(t).length, rounds: [] };
  for (let r = 0; r < rounds; r++) {
    for (const e of engines) {
      const p = pass(loaded[e].render, byType.get(t));
      const entry = result.engines[e].types[t];
      entry.rounds.push(p.ms);
      entry.chars = p.chars;
      entry.errors = p.errors;
    }
  }
}
writeFileSync(resultPath, JSON.stringify(result, null, 1));
