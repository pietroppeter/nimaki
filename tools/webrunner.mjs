// webrunner: the files a page loads (tools/webbuild.nim), run in Node, for `--web` in
// tools/difftest.nim: the referee on the files as the pages ship them, minified and one per type.
//
//   TZ=UTC node tools/webrunner.mjs cases.jsonl answers.jsonl build/web/nimaki.js
//   TZ=UTC node tools/webrunner.mjs cases.jsonl answers.jsonl build/web/nimaki-core.js build/web/nimaki-pie.js ...
//
// Loads each file as a page would (one script after the other: the first makes globalThis.nimaki,
// the others join it), then draws each case (one JSON object per line: id, source, options) with
// nimaki.render and writes one answer per line, in the oracle's format.
import { readFileSync, writeFileSync } from 'node:fs';
import { runInThisContext } from 'node:vm';

const [input, output, ...files] = process.argv.slice(2);
for (const file of files) runInThisContext(readFileSync(file, 'utf8'), { filename: file });
const nimaki = globalThis.nimaki;
// A lone surrogate written as a JSON escape: writing the string as UTF-8 would make it U+FFFD.
const escapeLone = (s) => s.replace(/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g,
  (u) => '\\u' + u.charCodeAt(0).toString(16));
let out = '';
for (const line of readFileSync(input, 'utf8').split('\n')) {
  if (line.trim() === '') continue;
  const c = JSON.parse(line);
  let answer;
  try {
    answer = { id: c.id, ok: true, svg: nimaki.render(c.source, c.options ?? {}).svg };
  } catch (e) {
    answer = e instanceof nimaki.PeleError
      ? { id: c.id, ok: false, code: e.code, message: e.message }
      : { id: c.id, ok: false, code: 'js-error', message: String(e && e.message) };
  }
  out += JSON.stringify(answer) + '\n';
}
writeFileSync(output, escapeLone(out), 'utf8');
