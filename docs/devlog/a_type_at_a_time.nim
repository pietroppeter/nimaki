## devlog: 15 Nov 2026 R | A type at a time | nimaki.js shrinks from 1.4 MB to 0.7 MB compressed, and a page no longer loads it whole: one small file of the shared core, then the file of each diagram type it draws, as Pele's lazy loading does. A page of flowcharts now downloads less than Pele's whole bundle, and every file is checked against Pele as it ships.
## kind: tooling
import std/[json, strformat, strutils, math, algorithm]
import nimib
import tabelline, tabelline/nimib
import ../blocks
import nimaki/selection

nbInit
nb.usePost()

# ---------------------------------------------------------------------------------------------
# The data: tools/jssize.nim before (the research post) and after (this one, with --web).
let
  before = parseFile(docsDir / "devlog" / "data" / "why_nimaki_js_is_big" / "sizes.json")
  after = parseFile(docsDir / "devlog" / "data" / "a_type_at_a_time" / "sizes.json")
  pele = after["peleBundle"]
  four = after["diagrammari"]
  jsRuns = parseFile(docsDir / "data" / "js.json")["difftest"]

proc file(data: JsonNode, name: string): JsonNode =
  for f in data["files"]:
    if f["name"].getStr == name: return f
  raise newException(KeyError, name)
proc shipped(name: string): JsonNode =
  for f in after["shipped"]:
    if f["name"].getStr == name: return f
  raise newException(KeyError, name)
func kb(bytes: int): string = $int(round(bytes / 1000)) & " KB"
func mb(bytes: int): string = &"{bytes / 1_000_000:.1f} MB"
func size(bytes: int): string = (if bytes >= 1_000_000: mb(bytes) else: kb(bytes))
func times(a, b: int): string = &"{a / b:.1f}"

let
  start = before.file("danger")
  url = after.file("danger")
  full = shipped("nimaki.js")
  core = shipped("nimaki-core.js")
  flow = shipped("nimaki-flowchart.js")
  pie = shipped("nimaki-pie.js")
  cases = jsRuns["cases"].getInt + jsRuns["diagrammari"]["cases"].getInt
var typeFiles: seq[JsonNode]
for f in after["shipped"]:
  if f["name"].getStr notin ["nimaki.js", "nimaki-core.js"]: typeFiles.add f
typeFiles.sort(proc (a, b: JsonNode): int = cmp(a["gzip"].getInt, b["gzip"].getInt))

nbText: &"""
## The findings, first

- **The file with every type went from {kb(start["gzip"].getInt)} to {kb(full["gzip"].getInt)}
  compressed** ({mb(start["raw"].getInt)} to {mb(full["raw"].getInt)} before compression), in two
  steps: the browser's own URL parser instead of a copy of its tables, and Pele's minifier.
- **A page no longer needs that file.** The pages now load `nimaki-core.js`
  ({kb(core["gzip"].getInt)} compressed), the shared core with no diagram type, and then one file
  for each type they draw: from {kb(typeFiles[0]["gzip"].getInt)} ({typeFiles[0]["name"].getStr}) to
  {kb(typeFiles[^1]["gzip"].getInt)} ({typeFiles[^1]["name"].getStr}). This is what Pele's lazy
  loading does, with files instead of modules.
- **Each type's file also works alone**: a page of flowcharts can load `nimaki-flowchart.js`
  ({kb(flow["gzip"].getInt)}) and nothing else. Pele's whole bundle is {kb(pele["gzip"].getInt)}.
- **For diagrammari**, whose pages use four types (flowchart, sequence, pie, timeline), one build
  of those four is {kb(four["gzip"].getInt)} compressed, less than Pele's bundle, and
  {mb(four["raw"].getInt)} before compression, a little more than Pele's {kb(pele["raw"].getInt)}.
- **Every file is checked as it ships**: the referee now loads the minified files in Node, as a
  page does, and compares their drawings with Pele's: {cases} of {cases} identical, with
  `nimaki.js` alone and with the core and all 33 type files together on one page.
- In my reading the size is now good enough for the 0.2 release. What is left (below) is worth
  doing, but it does not change what diagrammari's client mode can do.
"""

nbText: """
## Three steps
"""

block:
  type Row = object
    step, raw, gzip, brotli: string
  var rows: seq[Row]
  proc add(step: string, f: JsonNode) =
    rows.add Row(step: step, raw: size(f["raw"].getInt), gzip: size(f["gzip"].getInt), brotli: size(f["brotli"].getInt))
  add("before: nimaki.js, -d:danger", start)
  add("1. the browser's URL parser", url)
  add("2. minified, in a function", full)
  add("3. a page of pie charts: core + pie", %*{"raw": core["raw"].getInt + pie["raw"].getInt,
      "gzip": core["gzip"].getInt + pie["gzip"].getInt, "brotli": core["brotli"].getInt + pie["brotli"].getInt})
  add("3. or the pie's file alone", pie)
  add("Pele's bundle, for comparison", pele)
  let t = tabella(rows, rownameCol = "step"):
    tabHeader "nimaki.js, step by step", &"""{after["nim"].getStr}; esbuild {after["esbuild"].getStr}; gzip -9, brotli 11"""
    optCssTheme()
  nbTable t

nbText: """
### Ask the browser

A link in a diagram goes through `new URL()` in Pele, which writes a web address the way the
browser does: `HTTP://Example.COM:80/a/../b` becomes `http://example.com/b`, and a host in
another script, `exampleΩ.com`, becomes `xn--example-...` (this is called IDNA). nimaki's C
build has no browser to ask, so the port carries its own copy of those rules, with the Unicode
tables they need. In the JavaScript build there is a browser, or Node, so `src/nimaki/util/url.nim`
now calls `new URL()` there, and the tables are left out. It is the same choice as for regular
expressions ([JavaScript's own regular expressions](../javascripts-own-regular-expressions/)):
in JavaScript, use the engine Pele itself runs on.

### Minify as Pele does

A *minifier* rewrites a JavaScript file into a shorter one that does the same: it drops the
spaces and line breaks, and gives every local name one or two letters. Pele minifies its bundle
with esbuild; nimaki now uses the same esbuild, the version in Pele's own lock file, with Pele's
settings. One more option matters for Nim's output: `--format=iife` wraps the file in a function
(an *immediately invoked function expression*). Outside a function, a name at the top of a file is
global, and a minifier must keep it, since another script could use it; inside, it can shorten it
too. Nim's names are long (`dump__modeljson_u4573`), so that was worth a megabyte.

### A file per type

The research post found that most of nimaki.js is the 33 diagram types, and that a page draws a
few. Pele solves this with *lazy loading*: its bundler cuts the code into a core and one piece
per type, and `load(type)` fetches a piece the first time a page needs it. Nim cannot cut a
program into pieces: it writes one JavaScript file per program. So nimaki builds the program once
per type instead, each time with only that type in it:
"""

nbCode:
  # -d:nimakiTypes chooses the types of a build (src/nimaki/selection.nim): Pele's names,
  # comma-separated; `all` by default, `none` for the core alone.
  echo "this build draws: ", nimakiTypes
  echo "flowchart? ", drawn("flowchart"), "   pie? ", drawn("pie")

nbText: """
`src/nimaki.nim` imports and registers a type only when `drawn(...)` says so, and so does the
code that writes models for `parse`. A build without a type still detects it, and refuses it with
Pele's own error for a type that is not loaded: `Diagram type "pie" is not supported yet.`

Then the files have to work together. Each file, when it runs, looks for `globalThis.nimaki`:
the first one makes it, and each later one *joins* it. `nimaki.render(text)` reads the text's
type and hands it to the file that draws that type; `parse` does the same and remembers which
file parsed each model; `mount` draws through them. And `nimaki.load(type)` is Pele's lazy loading:
for a type no file on the page draws, it adds the script `nimaki-<type>.js` from the same folder
as the first file, and resolves when that file has joined. So a page can start with only the core:
"""

nbText: """
```js
// a page that loaded assets/nimaki-core.js only: this fetches nimaki-sequence.js, then draws
await nimaki.mountAsync(box, "sequenceDiagram\n  Alice->>Bob: Hi");
```
"""

nbText: """
`tools/webbuild.nim` makes all 35 files (four `nim js` at a time, then esbuild on each), and the
pages use them: `live.js` loads the core, then the types of the live figures on the page, and the
[Playground](../../playground/) loads a type's file the first time something of that type is typed
in its box.
"""

nbFold "Every file, from the smallest":
  type Row = object
    file, raw, gzip, brotli: string
  var rows: seq[Row]
  for f in @[core] & typeFiles & @[full]:
    rows.add Row(file: f["name"].getStr, raw: size(f["raw"].getInt), gzip: size(f["gzip"].getInt), brotli: size(f["brotli"].getInt))
  let t = tabella(rows, rownameCol = "file"):
    tabHeader "The files the pages load", "minified; each type's file holds the shared core too"
    optCssTheme()
  nbTable t

nbNote &"""
`difftest --web` loads the files the pages ship in Node, one script after the other as a page
does (`tools/webrunner.mjs`), and compares each drawing with Pele's, byte for byte:

- `nimaki.js` alone: {cases} of {cases} identical;
- `nimaki-core.js` and the 33 type files together, each drawing going to its type's file:
  {cases} of {cases} identical.

CI runs both on every pull request that changes code. The fuzzers and Pele's own test suites also
run on the JavaScript build, now with -d:danger as the pages build it.
""", nkDone, "Checked"

nbText: &"""
## What diagrammari's client mode would load

Today a diagrammari page in client mode carries Pele's whole bundle inside it
({kb(pele["raw"].getInt)}, {kb(pele["gzip"].getInt)} compressed) and calls `pele.mount` for each
diagram (`src/mari/render_html.nim` in diagrammari). diagrammari knows the type of every diagram
of a page when it builds it, so with nimaki it could carry only those types:

| A page with, and its file | Raw | Compressed |
|---|---|---|
| pie charts: nimaki-pie.js | {kb(pie["raw"].getInt)} | {kb(pie["gzip"].getInt)} |
| flowcharts: nimaki-flowchart.js | {kb(flow["raw"].getInt)} | {kb(flow["gzip"].getInt)} |
| diagrammari's four types: one build of the four | {kb(four["raw"].getInt)} | {kb(four["gzip"].getInt)} |
| any type: nimaki.js | {kb(full["raw"].getInt)} | {kb(full["gzip"].getInt)} |
| any type, Pele: pele.global.js | {kb(pele["raw"].getInt)} | {kb(pele["gzip"].getInt)} |

(The build of the four is `-d:nimakiTypes=flowchart,sequence,pie,timeline`.) So a page of
diagrammari's four types downloads {times(four["gzip"].getInt, pele["gzip"].getInt)}
times what Pele's bundle costs, compressed; a page with every type would cost
{times(full["gzip"].getInt, pele["gzip"].getInt)} times. GitHub Pages, where diagrammari's pages
are served, compresses what it sends.

diagrammari can get these files in two ways. It can build them itself, since it is a Nim project
that depends on nimaki: `nim js -d:danger -d:nimakiTypes=... nimaki/web.nim` needs no Node, and
the result works unminified (about three times larger before compression, and nearly twice as
large compressed). Or nimaki's releases could carry the minified files, built by `tools/webbuild.nim`,
for diagrammari to vendor as it vendors Pele's bundle today. This is a proposal for diagrammari,
not a change to it.
"""

nbNote """
Should nimaki's releases carry the built files (`nimaki.js`, `nimaki-core.js` and the 33 type
files, minified) as assets of the GitHub release, so that diagrammari can vendor them as it
vendors Pele's bundle? The alternative is that diagrammari compiles them itself with
`-d:nimakiTypes`, unminified unless it adds esbuild. The proposal of this thread: carry them,
from 0.2.0 on.
""", nkQuestion, "For Pietro"

nbText: """
## What is left

Measured but not done, each smaller than the steps above:

- **The models of `parse`** are still the largest single module in `nimaki.js`: the walk that
  writes them is generic, and Nim writes a copy of it for every type of model.
- **The core** (`nimaki-core.js`) still holds a few kilobytes of other types' parsers, which the
  model code imports for their types, and the regular-expression translator of the C build.
- **Strings as lists of numbers** cannot be minified; they compress well.

## What this changes for the port

- The JavaScript build calls `new URL()`; the C build keeps the port of ada's IDNA.
- `-d:nimakiTypes` chooses the types of a build, in C too (`src/nimaki/selection.nim`), and a type
  left out raises Pele's error, code `unsupported-diagram`, where nimaki used to raise its own
  `unsupported`.
- The files of the pages are built by `tools/webbuild.nim`, checked by `difftest --web`, and
  measured by `tools/jssize.nim --web`. Decision 0022 records the choices.
- The roadmap step *A smaller JavaScript build* is done.

## Sources

- The sizes: `nim r tools/webbuild.nim`, then `nim r tools/jssize.nim --web`, run on 15 November
  2026, written to `docs/devlog/data/a_type_at_a_time/sizes.json`; the sizes before, from the
  post [Why nimaki.js is big](../why-nimaki-js-is-big/).
- Pele 1.13.0's `src/lazy.ts` (lazy loading) and `scripts/build.mjs` (the bundle and the pieces).
- diagrammari's `src/mari/render_html.nim` at the pinned commit: client mode.
"""

nbSave
