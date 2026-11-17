## devlog: 17 Nov 2026 B | Faster, three ways | After the benchmark, the speed work Pietro asked for: fewer copies in nimaki.js, a faster C build, and a first WebAssembly build of nimaki, which draws every case identical to Pele, in one and a half times Pele's time.
## kind: port
import std/[json, strformat, strutils, math, sequtils]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../pele

nbInit
nb.usePost()

# ---------------------------------------------------------------------------------------------
# The data: the benchmark before (post How fast nimaki draws) and after (this post), both from
# tools/bench.nim; the JavaScript profiles before and after; the sizes of the WebAssembly build
# (tools/wasm/sizes.sh) and of the JavaScript files (post A type at a time).
const
  here = docsDir / "devlog" / "data" / "faster_three_ways"
  earlier = docsDir / "devlog" / "data" / "how_fast_nimaki_draws"
let
  before = parseFile(earlier / "bench.json")
  after = parseFile(here / "bench.json")
  profBefore = parseFile(earlier / "profile.json")
  profAfter = parseFile(here / "profile.json")
  jsSizes = parseFile(docsDir / "devlog" / "data" / "a_type_at_a_time" / "sizes.json")
var wasmSizes: seq[JsonNode]
for line in lines(here / "wasm-sizes.jsonl"):
  if line.strip.len > 0: wasmSizes.add parseJson(line)

proc warm(run: JsonNode, e: string): float =
  for t, entry in run["engines"][e]["types"]:
    result += entry["rounds"].getElems.mapIt(it.getFloat).min
proc cold(run: JsonNode, e: string): float = run["engines"][e]["cold"].getFloat
proc load(run: JsonNode, e: string): float = run["engines"][e]["load"].getFloat
func ms(x: float): string =
  if x >= 100: $int(round(x)) & " ms" else: formatFloat(x, ffDecimal, 1) & " ms"
func times(x: float): string = formatFloat(x, ffDecimal, (if x < 2: 2 else: 1)) & "×"
func pct(part, whole: float): string = $int(round(100 * part / whole)) & "%"
func kb(bytes: int): string = $int(round(bytes / 1000)) & " KB"
proc shipped(name: string): JsonNode =
  for f in jsSizes["shipped"]:
    if f["name"].getStr == name: return f
  raiseAssert name
proc wasmOf(types: string): JsonNode =
  for w in wasmSizes:
    if w["types"].getStr == types: return w
  raiseAssert types

let
  cases = after["cases"].getInt
  jsRatioBefore = warm(before, "js") / warm(before, "pele")
  jsRatioAfter = warm(after, "js") / warm(after, "pele")
  cRatioBefore = warm(before, "c") / warm(before, "pele")
  cRatioAfter = warm(after, "c") / warm(after, "pele")
  wasmRatio = warm(after, "wasm") / warm(after, "pele")
  copiesBefore = profBefore["helpers"]["copies"]["ms"].getFloat / profBefore["totalMs"].getFloat
  copiesAfter = profAfter["helpers"]["copies"]["ms"].getFloat / profAfter["totalMs"].getFloat
  skipBefore = profBefore["helpers"]["skipTable"]["ms"].getFloat
  skipAfter = profAfter["helpers"]["skipTable"]["ms"].getFloat
  wasmAll = wasmOf("all")
  wasmFour = wasmOf("flowchart,sequence,pie,timeline")
  jsFour = jsSizes["diagrammari"]
  peleBundle = jsSizes["peleBundle"]

doAssert jsRatioAfter < jsRatioBefore and cRatioAfter < cRatioBefore, "the findings say both got faster"
doAssert wasmRatio < 2 and warm(after, "wasm") < warm(after, "js") / 3, "the findings compare wasm with Pele and nimaki.js"

nbText: &"""
## The findings, first

- **nimaki.js got faster, but is still far from Pele.** Before this step it took
  {times(jsRatioBefore)} Pele's time to draw the corpus; now it takes {times(jsRatioAfter)}.
  Copies made by Nim went from {pct(copiesBefore, 1)} to {pct(copiesAfter, 1)} of its time.
  What is left is spread over many places, each worth a percent or two.
- **The C build got faster.** It went from {times(cRatioBefore)} to {times(cRatioAfter)} Pele's
  time: {ms(warm(after, "c"))} for the {cases} cases. The three changes: finding the diagram type
  without running the regular expression engine, building each lexer's tables once instead of
  for every diagram, and finding plain words without the engine.
- **nimaki now builds to WebAssembly.** The same C code, compiled for the browser's other
  language, draws all {cases} cases identical to Pele, byte for byte. It takes
  {ms(warm(after, "wasm"))} where Pele takes {ms(warm(after, "pele"))} ({times(wasmRatio)}), and
  {times(warm(after, "js") / warm(after, "wasm"))} less time than nimaki.js.
- **But the WebAssembly file is big:** {kb(wasmAll["gzip"].getInt)} compressed for every type,
  against {kb(shipped("nimaki.js")["gzip"].getInt)} for nimaki.js and
  {kb(peleBundle["gzip"].getInt)} for Pele's bundle.
- **Every drawing is still identical to Pele's**, in C, in nimaki.js, in the files the pages
  ship, and now in WebAssembly too.
"""

nbText: &"""
## The numbers, before and after

The benchmark is the one of the post [How fast nimaki draws](../how-fast-nimaki-draws/)
(`tools/bench.nim`), which now times a fourth engine. Times on one machine move from run to run:
Pele itself took {ms(warm(before, "pele"))} in the first run and {ms(warm(after, "pele"))} in this
one. So the table also gives each engine's time as a multiple of Pele's in the same run, which
moves less.
"""

block:
  type Row = object
    engine, warmBefore, warmAfter, vsPeleBefore, vsPeleAfter: string
  var rows: seq[Row]
  for (e, name) in [("c", "nimaki, C"), ("js", "nimaki.js"), ("wasm", "nimaki, wasm"), ("pele", "Pele")]:
    let had = before["engines"].hasKey(e)
    rows.add Row(engine: name,
      warmBefore: (if had: ms(warm(before, e)) else: "—"),
      warmAfter: ms(warm(after, e)),
      vsPeleBefore: (if had: times(warm(before, e) / warm(before, "pele")) else: "—"),
      vsPeleAfter: times(warm(after, e) / warm(after, "pele")))
  let t = tabella(rows, rownameCol = "engine"):
    tabHeader "The corpus, warm", &"""{cases} cases, fastest of {after["rounds"].getInt} rounds per type"""
    colsLabel {"warmBefore": "before", "warmAfter": "after", "vsPeleBefore": "× Pele before", "vsPeleAfter": "× Pele after"}
    optCssTheme()
  nbTable t

let chart = &"""xychart-beta
  title "The corpus, warm, after (ms)"
  x-axis ["C", "nimaki.js", "wasm", "Pele"]
  y-axis "milliseconds"
  bar [{int(round(warm(after, "c")))}, {int(round(warm(after, "js")))}, {int(round(warm(after, "wasm")))}, {int(round(warm(after, "pele")))}]
"""
nbMermaid chart, "The four engines on the same corpus, in the same run."

nbText: &"""
A program that starts, draws the corpus once and stops (the *cold* numbers) tells the same
story: C takes {ms(cold(after, "c"))}; the WebAssembly build {ms(load(after, "wasm") + cold(after, "wasm"))}
to load and draw, Pele {ms(load(after, "pele") + cold(after, "pele"))}. WebAssembly code is
compiled once when it loads, so it does not need the warm-up that JavaScript needs: cold, it
is as fast as Pele.
"""

nbText: &"""
## nimaki.js: fewer copies

The previous post found that a third of nimaki.js's time went to copies. Nim copies a value when
it is assigned (changing the copy must not change the original); the C build can often *move*
the value instead, but the JavaScript build copies it, unless the code is written so that there
is nothing to copy. The profile pointed at a few places, and each one had a simple fix:

- **Type detection** walked a constant list of 37 detectors with `for (name, type, re) in
  DETECTORS`. Unpacking each entry into three variables copied its regular expression, a large
  object. Now the loop goes by index, `DETECTORS[i][2].test(text)`, and copies nothing.
- **Icons and math** kept the host's answers in a table, saved and restored around every
  drawing. In nim js, saving a table copies the whole table. Now the table is a `ref`, a pointer:
  saving it copies the pointer. And when the host gives no icons (most of the time), no table is
  made at all.
- **Searching for a word in a text** (`strutils.find`, and `in` on strings) builds a table of 256
  entries for every search in nim js; the C build uses the C library's `memmem` instead. The
  port searches for short words many times per drawing (`%%`, `$$`, `var(--_`), so a small
  `findText` in `src/nimaki/js.nim` now compares byte by byte in the JavaScript build. The time
  spent building those tables went from {ms(skipBefore)} to {ms(skipAfter)} in the profile.
- **Labels** returned their result as `return layoutMarkup(...)`, which nim js copies once more
  on the way out; `handOver` (post [Copies on the way out](../copies-on-the-way-out/)) passes it
  up without a copy.
"""

nbNote &"""
Why not more? The profile after these changes has no big target left. The copies that remain,
{pct(copiesAfter, 1)} of the time, come from a hundred places that each cost a percent or less:
a closure that captures a list (it copies the list), a function that returns an object, the
`..` of a slice, which nim js copies as a small object every time. And {ms(profAfter["helpers"]["toJSStr"]["ms"].getFloat)}
go to turning the finished SVG from Nim's bytes into a JavaScript string, which every drawing
needs once. Closing the gap with Pele in JavaScript would take a different way of writing the
port, not more of these fixes. WebAssembly is that different way.
""", nkNim, "What is left in JavaScript"

nbText: """
## The C build: three hot spots

The C profile of the previous post (valgrind's callgrind, which counts the instructions of every
function) pointed at three things:

- **Finding the diagram type** cost 9% of the time. nimaki, as Pele, tries each type's pattern on
  the text: `^\s*flowchart`, `^\s*sequenceDiagram`, and so on. The patterns start with `^`, so
  they can only match at the start, but asking the regular expression engine still cost a few
  thousand instructions each, up to 37 times per diagram. Now, for a pattern of that shape,
  the wrapper skips the white space itself and compares the word (`spaced` in
  `src/nimaki/jsregex.nim`); the engine runs only when the word is there. A character outside
  ASCII where the white space ends still goes to the engine, because JavaScript's `\s` includes
  a few such spaces.
- **Each lexer's tables**: before reading a text, a lexer prepares, for each of the 128 ASCII
  characters, the list of token types that can start with it. It did that for every diagram;
  now it does it once per lexer and keeps the result (`preparedFor` in
  `src/nimaki/diagrams/common/tokens.nim`).
- **Plain words**: a pattern such as `/edge-thickness-normal|edge-pattern-solid|flowchart-link/g`
  is only a choice between words. The wrapper now finds such words by comparing, in the order
  the pattern lists them, as JavaScript does, instead of running the engine.

These are the kind of change the referee makes safe: each one is a shortcut that must give the
same answer as the engine, and the {cases} cases of the corpus (and the diagrammari cases, and
Pele's own test suites in CI) check that it does.
"""

nbText: &"""
## WebAssembly

**WebAssembly** (*wasm*) is a second language that browsers run, next to JavaScript. It is not
written by hand: a compiler produces it, from C, Rust or other languages. A browser (or Node)
compiles it to machine code when it loads, so it runs at close to the speed of a native program,
without JavaScript's warm-up.

Nim compiles to C, so nimaki can reach WebAssembly through a C compiler that targets it. The
sandbox already had clang, which can produce WebAssembly; it only needed WASI's C library
(`wasi-libc`, one package), the small standard library that WebAssembly programs use outside a
browser. `tools/wasm/build.sh` compiles nimaki for `wasm32-wasi`, with three choices:

- `--exceptions:goto`: Nim reports errors (a diagram Pele refuses) without `setjmp`, which plain
  WebAssembly does not have;
- `-d:useMalloc`: Nim's own memory allocator asks the system for memory pages, which WASI does not
  offer, so the C library's `malloc` is used;
- a small entry point, `tools/wasm/nimaki_wasm.nim`, which exports `nimakiRender` and a few
  helpers: the page writes the Mermaid text into the module's memory as UTF-8, calls
  `nimakiRender`, and reads the SVG back (`tools/wasm/load.mjs` does it in Node).

Then `tools/wasm/check.mjs` draws the whole corpus with the WebAssembly build and with Pele in the
same Node, and compares the bytes: all {cases} are identical. That was not a given. The port
computes with floating point numbers, and a different C library could round a sine or a power
in its last digit differently; nimaki's own copy of V8's math functions (see the
[porting guide](../../porting/)) is what keeps them the same.
"""

block:
  type Row = object
    build, wasm, js: string
  let rows = @[
    Row(build: "every type", wasm: kb(wasmAll["gzip"].getInt), js: kb(shipped("nimaki.js")["gzip"].getInt)),
    Row(build: "the core, no type", wasm: kb(wasmOf("none")["gzip"].getInt), js: kb(shipped("nimaki-core.js")["gzip"].getInt)),
    Row(build: "core and flowchart", wasm: kb(wasmOf("flowchart")["gzip"].getInt), js: kb(shipped("nimaki-flowchart.js")["gzip"].getInt)),
    Row(build: "diagrammari's four types", wasm: kb(wasmFour["gzip"].getInt), js: kb(jsFour["gzip"].getInt))]
  let t = tabella(rows, rownameCol = "build"):
    tabHeader "Download size, gzipped", &"""WebAssembly with -d:danger --opt:size; Pele's whole bundle: {kb(peleBundle["gzip"].getInt)}"""
    colsLabel {"wasm": "wasm", "js": "nimaki.js"}
    optCssTheme()
  nbTable t

nbText: &"""
The size is the cost. The WebAssembly file is about twice the size of the JavaScript files, and
{times(wasmAll["gzip"].getInt / peleBundle["gzip"].getInt)} Pele's bundle for every type. Most of
it is code (the machine instructions of every function Nim generated), and a page that draws
only flowcharts still loads {kb(wasmOf("flowchart")["gzip"].getInt)}. The same selection of types
as the JavaScript files (`-d:nimakiTypes`) works here too, and is already in these numbers.
"""

nbNote """
Should nimaki ship a WebAssembly build next to nimaki.js? It is about five times faster than
nimaki.js and as fast as Pele from a cold start, but about twice the download. For diagrammari,
which draws at build time, the C build is already the fastest. For a web page, WebAssembly
would matter for a page with many diagrams, or with large ones. Making it a real build would mean
a `nimaki.load` that picks WebAssembly when the browser has it, the icon and math callbacks
across the boundary (not done in this experiment), and a check in CI.
""", nkQuestion, "For Pietro"

nbText: """
## What this changes for the port

- nimaki.js has fewer copies and no search tables. The next gains in JavaScript would need a
  different way of writing the port; the profile shows no single big target left.
- The C build is faster, from three shortcuts the referee checks.
- `tools/bench.nim --engines:c,js,wasm,pele` now times four engines.
- `tools/wasm/` holds a working WebAssembly build: `build.sh` makes it, `check.mjs` compares it
  with Pele on the corpus, `sizes.sh` measures it. It is an experiment, not shipped, and not in
  CI.

## Sources

- The benchmark: `build/bench/bench --engines:c,js,wasm,pele --rounds:10`, run on 17 November
  2026, in `docs/devlog/data/faster_three_ways/bench.json`; the numbers before are those of the
  post *How fast nimaki draws*.
- The JavaScript profile after: `profile.mjs` in the same folder, written to `profile.json`.
- The WebAssembly sizes: `sh tools/wasm/sizes.sh`, in `wasm-sizes.jsonl`; the JavaScript sizes
  are those of the post *A type at a time*.
- [WebAssembly](https://webassembly.org/), [WASI](https://wasi.dev/), and
  [wasi-libc](https://github.com/WebAssembly/wasi-libc); Node's [WASI module](https://nodejs.org/api/wasi.html).
- clang 18 and wasi-libc from Ubuntu 24.04's packages.
"""

nbSave
