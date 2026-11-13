// The oracle: Pele's pinned npm package, run in Node. Reads one JSON case per line on stdin,
// `{"id": ..., "source": ..., "options": {...}}`, and writes one JSON result per line on stdout:
// `{"id", "ok": true, "type", "svg", "width", "height"}` or
// `{"id", "ok": false, "type", "code", "message"}` when Pele throws.
//
//   node tools/oracle.mjs [reference/npm/package] < cases.jsonl > results.jsonl
//
// tools/difftest.nim runs it with TZ=UTC and a fixed `now` (gantt reads both). Nothing else is
// set: the measurer is Pele's default, metricsMeasurer, since Node has no canvas.
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createInterface } from 'node:readline';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pkg = resolve(process.argv[2] ?? join(repo, 'reference/npm/package'));
const { render, detectType } = await import(pathToFileURL(join(pkg, 'dist/pele.js')).href);

// A host's icons and typesetter, made up, the same as tools/answers.nim's: they only need to be
// deterministic and to cover each case Pele handles (an icon or none; SVG, HTML, none, a bad size).
function testIcons(name) {
  return name.includes('none') ? null : `<path d="M0 0L${name.length} 24"/>`;
}
function testMath(tex, size) {
  if (tex.includes('bad')) return null;
  const width = tex.length * size * 0.55;
  const height = size * (tex.includes('frac') ? 2.25 : 1.2);
  if (tex.includes('nan')) return { svg: '<g/>', width: NaN, height };
  if (tex.includes('html')) return { html: `<span class="m">${tex.length}</span>`, width, height };
  return { svg: `<svg viewBox="0 0 ${tex.length} 1"><rect width="${tex.length}" height="1"/></svg>`, width, height };
}

const out = [];
const flush = () => { if (out.length) { process.stdout.write(out.join('')); out.length = 0; } };
for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  if (!line.trim()) continue;
  const c = JSON.parse(line);
  // `icons: "test"` and `math: "test"` stand for the test resolvers below (functions do not travel in JSON).
  if (c.options?.icons === 'test') c.options.icons = testIcons;
  if (c.options?.math === 'test') c.options.math = testMath;
  let r;
  try {
    const res = render(c.source, c.options ?? {});
    r = { id: c.id, ok: true, type: res.type, svg: res.svg, width: res.width, height: res.height };
  } catch (e) {
    r = { id: c.id, ok: false, type: e?.type ?? detectType(c.source), code: e?.code ?? 'internal', message: String(e?.message ?? e) };
  }
  out.push(JSON.stringify(r) + '\n');
  if (out.length >= 64) flush();
}
flush();
