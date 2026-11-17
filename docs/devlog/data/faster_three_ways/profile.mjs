// Where nimaki's JavaScript build spends its time: the post *Faster, three ways* runs this
// once and reads profile.json. It draws the whole corpus eight times with nimaki.js as `nim js`
// writes it (not minified, so the functions keep their Nim names) under Node's CPU profiler,
// then sums the profile's samples by function (self time: the time spent in the function's own
// code, not in what it calls), and the time of Nim's copy functions by the Nim proc that asked
// for the copy (and the same for two other helpers of Nim's that show up high: the skip table
// that `strutils.find` builds for each search, and the turning of a Nim string into a JavaScript
// one).
//
//   nim r tools/webbuild.nim --only:all --no-minify --out:build/bench/raw
//   node docs/devlog/data/faster_three_ways/profile.mjs build/bench/raw/nimaki.js
import { readFileSync, writeFileSync, readdirSync, rmSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { runInThisContext } from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../../../..');
const [script, profileDir] = process.argv.slice(2);

if (profileDir) {
  // The child: draw, while the profiler listens.
  runInThisContext(readFileSync(script, 'utf8'), { filename: script });
  const cases = JSON.parse(readFileSync(join(repo, 'corpus/cases.json'), 'utf8')).cases;
  for (let r = 0; r < 8; r++)
    for (const c of cases) { try { globalThis.nimaki.render(c.source, { now: 1.7e12 }); } catch {} }
  process.exit(0);
}

const dir = join(repo, 'build/bench/profile');
rmSync(dir, { recursive: true, force: true });
execFileSync('node', ['--cpu-prof', `--cpu-prof-dir=${dir}`, fileURLToPath(import.meta.url), resolve(script), dir],
  { env: { ...process.env, TZ: 'UTC' }, stdio: 'inherit' });
const p = JSON.parse(readFileSync(join(dir, readdirSync(dir)[0]), 'utf8'));

const node = new Map(p.nodes.map((n) => [n.id, n]));
const parent = new Map();
for (const n of p.nodes) for (const c of n.children ?? []) parent.set(c, n.id);
const self = new Map();
for (let i = 0; i < p.samples.length; i++) self.set(p.samples[i], (self.get(p.samples[i]) ?? 0) + p.timeDeltas[i]);

// A Nim name in nim js is `proc__module_uNNN`: keep `module.proc`, readable.
const nimName = (f) => {
  const m = /^(.*?)__(.*)_u\d+$/.exec(f);
  if (!m) return f || '(anonymous)';
  const mod = m[2].replace(/Z/g, '/').replace(/^(diagrams|std|pure|private)\//, '').replace(/^(pure|private)\//, '');
  return `${mod}.${m[1].replace(/HEX([0-9A-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))}`;
};
const helpers = { copies: ['nimCopy', 'nimCopyAux'], skipTable: ['nsuInitNewSkipTable'], toJSStr: ['toJSStr'] };
const passThrough = new Set([...Object.values(helpers).flat(), '(garbage collector)']);
let total = 0;
const byFunction = new Map();
const helperMs = {}, helperBy = {};
for (const h in helpers) { helperMs[h] = 0; helperBy[h] = new Map(); }
for (const [id, us] of self) {
  total += us;
  const f = node.get(id).callFrame.functionName;
  byFunction.set(nimName(f), (byFunction.get(nimName(f)) ?? 0) + us);
  for (const h in helpers) {
    if (!helpers[h].includes(f)) continue;
    helperMs[h] += us;
    let q = parent.get(id);
    while (q && passThrough.has(node.get(q).callFrame.functionName)) q = parent.get(q);
    const by = q ? nimName(node.get(q).callFrame.functionName) : '?';
    helperBy[h].set(by, (helperBy[h].get(by) ?? 0) + us);
  }
}
const top = (m, n) => [...m].sort((a, b) => b[1] - a[1]).slice(0, n).map(([name, us]) => ({ name, ms: us / 1000 }));
const result = { node: process.version, rounds: 8, totalMs: total / 1000, functions: top(byFunction, 15), helpers: {} };
for (const h in helpers) result.helpers[h] = { functions: helpers[h], ms: helperMs[h] / 1000, by: top(helperBy[h], 8) };
writeFileSync(join(here, 'profile.json'), JSON.stringify(result, null, 1) + '\n');
const copyTotal = helperMs.copies;
console.log(`profile: ${(total / 1000).toFixed(0)} ms sampled, ${(100 * copyTotal / total).toFixed(1)}% in Nim's copies`);
