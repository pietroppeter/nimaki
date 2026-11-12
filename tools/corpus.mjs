// Builds corpus/cases.json, the inputs the referee (tools/difftest.nim) runs on both sides, from
// the pinned Pele checkout. Run it again only when the pin moves:
//
//   node tools/corpus.mjs [reference/pele] [reference/npm/package]
//
// Two sources, as in Pele's own tests (tests/support/corpus.ts, loadCorpus):
// - every case of tests/corpus/*.json (Mermaid's documentation examples and Pele's references);
// - every string literal of the compat specs (tests/compat/<type>/*.spec.ts, ported by Pele from
//   Mermaid) that Pele detects as a diagram, evaluated as loadCorpus does.
// Each case has an id (stable while the pin does not move), the type Pele detects, and its source.
// Written in JavaScript, not Nim, because the literals are JavaScript and must be read as such.
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ref = resolve(process.argv[2] ?? join(repo, 'reference/pele'));
const pkg = resolve(process.argv[3] ?? join(repo, 'reference/npm/package'));
const { detectType } = await import(pathToFileURL(join(pkg, 'dist/pele.js')).href);

const cases = [];
const seen = new Set();
function add(id, from, source) {
  if (seen.has(source)) return;
  const type = detectType(source);
  if (!type) return;
  seen.add(source);
  cases.push({ id, type, from, source });
}

for (const file of readdirSync(join(ref, 'tests/corpus')).filter((f) => f.endsWith('.json')).sort()) {
  const list = JSON.parse(readFileSync(join(ref, 'tests/corpus', file), 'utf8'));
  // a case is the text, or (agentflow-reference.json) an object whose `src` is the text
  list.forEach((c, i) => add(`corpus/${file.replace(/\.json$/, '')}/${i}`, `tests/corpus/${file}`, typeof c === 'string' ? c : c.src));
}

const compat = join(ref, 'tests/compat');
for (const dir of readdirSync(compat).sort()) {
  let files;
  try { files = readdirSync(join(compat, dir)); } catch { continue; }
  for (const file of files.filter((f) => /\.spec\.[jt]s$/.test(f)).sort()) {
    const src = readFileSync(join(compat, dir, file), 'utf8');
    let i = 0;
    for (const m of src.matchAll(/`((?:[^`\\]|\\.)*)`|'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"/g)) {
      const raw = m[1] ?? m[2] ?? m[3];
      let source;
      try {
        source = new Function('return `' + raw.replace(/`/g, '\\`').replace(/\$\{/g, '\\${') + '`')();
      } catch {
        continue;
      }
      add(`compat/${dir}/${file.replace(/\.spec\.[jt]s$/, '')}/${i++}`, `tests/compat/${dir}/${file}`, source);
    }
  }
}

const pin = JSON.parse(readFileSync(join(pkg, 'package.json'), 'utf8')).version;
mkdirSync(join(repo, 'corpus'), { recursive: true });
const byType = {};
for (const c of cases) byType[c.type] = (byType[c.type] ?? 0) + 1;
writeFileSync(join(repo, 'corpus/cases.json'),
  JSON.stringify({ about: 'The inputs of tools/difftest.nim, built by tools/corpus.mjs from Pele at the pin. Do not edit by hand.',
                   pin, count: cases.length, byType, cases }, null, 1) + '\n');
console.log(`corpus: pele ${pin}, ${cases.length} cases of ${Object.keys(byType).length} types`);
console.log('wrote corpus/cases.json');
