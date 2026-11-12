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

const out = [];
const flush = () => { if (out.length) { process.stdout.write(out.join('')); out.length = 0; } };
for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  if (!line.trim()) continue;
  const c = JSON.parse(line);
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
