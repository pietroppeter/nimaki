// Builds corpus/regexes.json: every regular expression literal of the pinned Pele's src/, where
// it is, and the `new RegExp(...)` calls (whose pattern is built at run time). tests/test_jsregex.nim
// runs each literal in Node and in src/nimaki/jsregex.nim on the same strings. Run it again only
// when the pin moves:
//
//   npm install --prefix build/ts typescript@5     (once: the TypeScript parser reads the source)
//   node tools/pele_regexes.mjs [reference/pele]
//
// Written in JavaScript, not Nim, because telling a regex literal from a division needs a
// TypeScript parser.
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ref = resolve(process.argv[2] ?? process.env.PELE_REF ?? join(repo, 'reference/pele'));
const require = createRequire(join(repo, 'build/ts/'));
let ts;
try { ts = require('typescript'); } catch {
  console.log('ERROR typescript not found: npm install --prefix build/ts typescript@5');
  process.exit(1);
}

const literals = new Map();   // "/body/flags" -> places
const dynamic = [];
function walk(dir) {
  for (const f of readdirSync(dir).sort()) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.ts')) scan(p);
  }
}
function scan(path) {
  const file = relative(ref, path);
  const src = ts.createSourceFile(path, readFileSync(path, 'utf8'), ts.ScriptTarget.Latest, true);
  const line = (n) => src.getLineAndCharacterOfPosition(n.getStart()).line + 1;
  const visit = (n) => {
    if (n.kind === ts.SyntaxKind.RegularExpressionLiteral) {
      const t = n.text;
      if (!literals.has(t)) literals.set(t, []);
      literals.get(t).push(`${file}:${line(n)}`);
    } else if (ts.isNewExpression(n) && n.expression.getText() === 'RegExp') {
      dynamic.push({ at: `${file}:${line(n)}`, code: n.getText() });
    }
    ts.forEachChild(n, visit);
  };
  visit(src);
}
walk(join(ref, 'src'));

const list = [...literals].map(([lit, at]) => {
  const close = lit.lastIndexOf('/');
  return { pattern: lit.slice(1, close), flags: lit.slice(close + 1), at };
}).sort((a, b) => (a.at[0] < b.at[0] ? -1 : 1));
const uses = list.reduce((n, r) => n + r.at.length, 0);
writeFileSync(join(repo, 'corpus/regexes.json'), JSON.stringify({
  about: 'Every regex literal of Pele\'s src/ (distinct pattern and flags, with where each is written) and every new RegExp call; built by tools/pele_regexes.mjs.',
  pin: readFileSync(join(repo, 'reference/PIN'), 'utf8').match(/^COMMIT=(.*)$/m)[1],
  literals: list,
  dynamic,
}, null, 1) + '\n');
console.log(`pele_regexes: ${uses} literals (${list.length} distinct) and ${dynamic.length} new RegExp in ${ref}`);
