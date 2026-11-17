## The benchmark, docs/benchmark/index.html: how fast nimaki draws, in each of its builds, next to
## Pele, and how that is measured. Kept up to date: the numbers are the last run of
## tools/bench.nim (docs/data/bench.json); a change to the benchmark (tools/bench.nim,
## tools/bench.mjs, tools/bench_profile.mjs, tools/bench_cprofile.sh, tools/wasm/) changes this
## page in the same pull request, and a step that makes nimaki faster or slower reruns it.
import std/[json, strformat, strutils, math, sequtils, algorithm, times]
import nimib
import tabelline, tabelline/nimib
import blocks, pele

let run = parseFile(docsDir / "data" / "bench.json")

proc fastest(e, t: string): float =
  run["engines"][e]["types"][t]["rounds"].getElems.mapIt(it.getFloat).min
proc warm(e: string): float =
  for t, _ in run["engines"][e]["types"]: result += fastest(e, t)
proc cold(e: string): float = run["engines"][e]["cold"].getFloat
proc load(e: string): float = run["engines"][e]["load"].getFloat
func ms(x: float): string =
  if x >= 100: $int(round(x)) & " ms" else: formatFloat(x, ffDecimal, 1) & " ms"
func num(x: float): string =
  if x >= 100: $int(round(x)) else: formatFloat(x, ffDecimal, 1)
func times(x: float): string = formatFloat(x, ffDecimal, (if x < 2: 2 else: 1)) & "×"

const names = [("c", "nimaki, C"), ("js", "nimaki.js"), ("wasm", "nimaki, wasm"), ("pele", "Pele")]
let
  engines = names.filterIt(run["engines"].hasKey(it[0]))
  cases = run["cases"].getInt
  rounds = run["rounds"].getInt
  nodeStart = run["nodeStart"].getFloat
  hasWasm = run["engines"].hasKey("wasm")
var types: seq[string]
for t, _ in run["engines"]["pele"]["types"]: types.add t
types.sort

let runDay = parse(run["date"].getStr, "yyyy-MM-dd").format("d MMMM yyyy")

nbInit
nb.doc.filename = docsDir / "benchmark" / "index.html"
nb.usePage(section = "Benchmark", cadence = "kept up to date", title = "Benchmark · nimaki",
           homeHref = "../", description = "How fast nimaki draws in C, in JavaScript and in WebAssembly, next to Pele, and how it is measured.")

nbTitle "Benchmark · kept up to date", "How fast nimaki draws", &"""
How long nimaki takes to draw Mermaid diagrams, in each of its builds, next to Pele on the same
diagrams; how that is measured, how to measure it again, and how to find where the time goes.
The numbers below are the last run, of {runDay}.
"""

nbToc

nbText: &"""
## The last run

All {cases} diagrams of the corpus, drawn by each engine, on the same machine, in the same run.
*Warm* is the time once each engine has warmed up; *cold* is the first pass, in a program that
has just started; *load* is the time to load the engine's code before it draws anything. The
words are explained in [What is measured](#what-is-measured).
"""

block:
  type Row = object
    engine, warm, vsPele, cold, load: string
  var rows: seq[Row]
  for (e, name) in engines:
    rows.add Row(engine: name, warm: num(warm(e)), vsPele: times(warm(e) / warm("pele")),
      cold: num(cold(e)), load: (if e == "c": "—" else: num(load(e))))
  let t = tabella(rows, rownameCol = "engine"):
    tabHeader "The corpus (ms)", &"""{cases} cases of {run["types"].getInt} types; warm is the fastest of {rounds} rounds per type"""
    colsLabel {"warm": "warm", "vsPele": "× Pele", "cold": "cold", "load": "load"}
    optCssTheme()
  nbTable t

var chart = "xychart-beta\n  title \"The corpus, warm (ms)\"\n  x-axis [" &
  engines.mapIt("\"" & (if it[0] == "pele": "Pele" elif it[0] == "c": "C" elif it[0] == "js": "nimaki.js" else: "wasm") & "\"").join(", ") &
  "]\n  y-axis \"milliseconds\"\n"
chart.add "  bar [" & engines.mapIt(if it[0] == "pele": "0" else: $int(round(warm(it[0])))).join(", ") & "]\n"
chart.add "  bar [" & engines.mapIt(if it[0] == "pele": $int(round(warm("pele"))) else: "0").join(", ") & "]\n"
nbMermaid chart, "The engines on the same corpus, in the same run; Pele in its own colour."

nbText: &"""
The machine: {run["cpu"].getStr}, {run["cores"].getInt} cores; Nim {run["nim"].getStr}
({run["flags"].getStr}), Node {run["node"].getStr}; nimaki at commit `{run["commit"].getStr}`.
Node itself takes {ms(nodeStart)} to start and stop, before it runs any script.
"""

nbFold "Every type, warm (ms)":
  type TypeRow = object
    `type`, c, js, wasm, pele: string
  var rows: seq[TypeRow]
  for t in types:
    rows.add TypeRow(`type`: t, c: num(fastest("c", t)), js: num(fastest("js", t)),
      wasm: (if hasWasm: num(fastest("wasm", t)) else: "—"), pele: num(fastest("pele", t)))
  let t = tabella(rows, rownameCol = "type"):
    tabHeader "Each type, warm", &"fastest of {rounds} rounds, in milliseconds"
    colsLabel {"c": "C", "js": "js", "wasm": "wasm", "pele": "Pele"}
    optCssTheme()
  nbTable t

nbText: """
## What is measured

**The engines.** Up to four programs draw the same diagrams:

- **nimaki, C**: nimaki compiled to C, then to machine code, the way a Nim program uses it
  (`import nimaki`). The benchmark itself is a Nim program, so this build runs inside it.
- **nimaki.js**: nimaki compiled to JavaScript, `build/web/nimaki.js`, the file a web page loads
  (the post [nimaki in JavaScript](../devlog/nimaki-in-javascript/)). It runs in Node, the
  JavaScript engine of Chrome outside the browser.
- **nimaki, wasm**: the same C code compiled to WebAssembly (`build/wasm/nimaki.wasm`), the
  browser's second language, a compact machine code that the browser checks and compiles when it
  loads it. An experiment, not shipped (the post [Faster, three ways](../devlog/faster-three-ways/)).
- **Pele**: Pele's own npm package (`dist/pele.js`, the file the referee loads), in the same Node.

**The diagrams.** The corpus (`corpus/cases.json`): the Mermaid texts of Pele's own tests (the
examples of Mermaid's documentation, Pele's references, and the cases of the tests Pele ported
from Mermaid), the same that the referee checks byte by byte. All engines draw with the same fixed
date (`now`), so that a Gantt chart of "today" is the same drawing every time.

**Warm.** A program that draws many diagrams soon runs at full speed: the code is in the
processor's caches, and a JavaScript engine has compiled the busy functions to machine code (it
first runs them slowly, watches which are busy, then compiles those: the *warm-up*). To measure
that steady speed, the benchmark draws all the cases of one type, again and again (the
*rounds*), and keeps the **fastest** round. Not the average: on a shared machine something else
often runs at the same time and slows a round down, never speeds it up, so the fastest round is
the closest to the engine's own speed. The corpus time is the sum of the types.

**Cold.** A program that starts, draws a few diagrams and stops (a command line tool, a build
step) never warms up. So, for each engine, the benchmark also starts a fresh program and times
its first pass over the corpus. For JavaScript and WebAssembly, *load* is the time to read and
prepare the engine's file before the first drawing, and Node's own start is measured apart.

**Multiples of Pele.** Times on one machine move from run to run, by ten percent or more, and
from one machine to another by much more. Pele runs in every run, so each engine is also given as
a multiple of Pele's time in the same run, which moves less. Compare those across runs, not the
milliseconds.

**A check.** Each engine counts the characters of the SVG it drew (as JavaScript counts them), and
the benchmark fails if two engines drew different amounts. It is only a guard: that the drawings
are the same, byte for byte, is the referee's job (`tools/difftest.nim`).

**Not measured.** Memory; a real browser (Node runs the same JavaScript engine as Chrome, but not
Firefox's or Safari's); the size of the files a page loads (the post
[A type at a time](../devlog/a-type-at-a-time/) measures that); a machine other than the one of
the run.
"""

nbText: """
## How the benchmark works

Two programs, so that each engine runs where it lives:

- `tools/bench.nim` is the one to run. It reads the corpus, groups the cases by type, and times
  the C build in its own process: one cold pass over every type, then the rounds of each type.
  Then it runs `tools/bench.mjs` in Node, once per engine for the cold pass (a fresh Node each
  time) and once with all the Node engines for the rounds. It times `node -e 0` (best of five)
  for Node's start, prints a line per type and a summary, and writes every number as JSON.
- `tools/bench.mjs` loads the engines in one Node: Pele with `import`, nimaki.js the way a browser
  reads a script, the WebAssembly build through `tools/wasm/load.mjs`. Its rounds alternate the
  engines (Pele, nimaki.js, wasm, Pele, ...), so that a slow moment of the machine falls on all
  of them.

Each round is timed with the clock of the program (`getMonoTime` in Nim, `performance.now` in
Node), around the drawing only: reading the corpus and counting characters are outside it.
"""

nbText: """
## Running it

From the root of nimaki, after `sh tools/setup.sh`. Build it with `-d:release`: a debug build is
many times slower, and the benchmark says so in an `ERROR` line.

```sh
nim c -d:release -o:build/bench/bench tools/bench.nim
build/bench/bench                              # C, nimaki.js and Pele, 5 rounds
build/bench/bench pie flowchart                # only these types
build/bench/bench --rounds:10 --engines:c,js,wasm,pele --out:docs/data/bench.json
```

- `--rounds:N`: rounds per type (default 5). The last run used 10.
- `--engines:...`: any of `c`, `js`, `wasm`, `pele` (default `c,js,pele`).
- `--out:FILE`: write every number as JSON. `docs/data/bench.json` is the file this page reads.
- `--package:PATH`: Pele's package (default `$PELE_PACKAGE` or `reference/npm/package`).

`build/web/nimaki.js` is built when it is missing, but not rebuilt when `src/` changes: after a
change, rebuild it with `nim r tools/webbuild.nim --only:all`. The same goes for the WebAssembly
build, `sh tools/wasm/build.sh`, which needs clang with the wasm32 target and WASI's C library
(on Debian and Ubuntu: `apt install clang lld wasi-libc libclang-rt-18-dev-wasm32`).
`node tools/wasm/check.mjs` checks that it draws every case as Pele does.

A whole run with 10 rounds takes a few minutes; nimaki.js takes most of it.
"""

nbText: """
## Finding where the time goes

A benchmark says *how long*; a profiler says *where*. Two are used here, one per build:

- **nimaki.js**: `tools/bench_profile.mjs` runs the corpus eight times under Node's CPU profiler,
  which looks a thousand times a second at which function is running (*sampling*). It sums the
  samples by function, and finds who called Nim's copy functions (`nimCopy`), the usual cost of
  Nim compiled to JavaScript (the [porting guide](../porting/) lists the traps). It needs a
  build that is not minified, so that functions keep their Nim names:

```sh
nim r tools/webbuild.nim --only:all --no-minify --out:build/bench/raw
node tools/bench_profile.mjs build/bench/raw/nimaki.js     # writes build/bench/profile.json
```

- **nimaki, C**: `tools/bench_cprofile.sh` draws the corpus once under valgrind's callgrind, which
  counts the machine instructions of each function: slow (a minute or two), but exact and
  without noise. It writes the top functions by their own instructions (`c-self.txt`) and with
  everything they call (`c-inclusive.txt`), in `build/bench/`:

```sh
sh tools/bench_cprofile.sh
```

Both are the tools that found the speed-ups of
[Faster, three ways](../devlog/faster-three-ways/).
"""

nbText: """
## The history

The benchmark and what changed because of it, in order:

- [How fast nimaki draws](../devlog/how-fast-nimaki-draws/) (17 November 2026): the first run,
  and the profiles of both builds. C was a little faster than Pele, nimaki.js ten times slower.
- [Faster, three ways](../devlog/faster-three-ways/) (17 November 2026): fewer copies in
  nimaki.js, three hot spots fixed in C, and the WebAssembly build as a fourth engine. This is
  the run shown above.

A later step that changes nimaki's speed adds its post here and reruns the benchmark.
"""

nbNote """
This page follows the benchmark. A pull request that changes `tools/bench.nim`, `tools/bench.mjs`,
the profilers or `tools/wasm/` changes this page too; one that makes nimaki faster or slower
reruns the benchmark with `--rounds:10 --engines:c,js,wasm,pele --out:docs/data/bench.json`
([For coding agents](../agents/)).
""", nkInfo, "Keeping it up to date"

nbSave
