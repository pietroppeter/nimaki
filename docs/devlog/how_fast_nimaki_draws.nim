## devlog: 17 Nov 2026 A | How fast nimaki draws | nimaki's C build draws the corpus a little faster than Pele in Node, and much faster when a program starts fresh; its JavaScript build is about ten times slower than Pele. How the three were timed, per diagram type, and where the time of each build goes.
## kind: research
import std/[json, strformat, strutils, algorithm, math, sequtils]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../pele

nbInit
nb.usePost()

# ---------------------------------------------------------------------------------------------
# The data: tools/bench.nim (bench.json, and before.json for the run before the fix of this
# post), the JavaScript profile (profile.json, profile.mjs) and the C profile (c-self.txt,
# c-inclusive.txt, cprofile.sh), all in docs/devlog/data/how_fast_nimaki_draws/.
const here = docsDir / "devlog" / "data" / "how_fast_nimaki_draws"
let
  bench = parseFile(here / "bench.json")
  before = parseFile(here / "before.json")
  profile = parseFile(here / "profile.json")
  engines = bench["engines"]
  types = toSeq(engines["c"]["types"].keys)

proc fastest(run: JsonNode, e, t: string): float =
  run["engines"][e]["types"][t]["rounds"].getElems.mapIt(it.getFloat).min
proc median(run: JsonNode, e, t: string): float =
  var xs = run["engines"][e]["types"][t]["rounds"].getElems.mapIt(it.getFloat)
  xs.sort
  xs[xs.len div 2]
proc warm(run: JsonNode, e: string): float =
  for t in types: result += fastest(run, e, t)
proc warmMedian(run: JsonNode, e: string): float =
  for t in types: result += median(run, e, t)
func ms(x: float): string =
  if x >= 100: $int(round(x)) & " ms" else: formatFloat(x, ffDecimal, 1) & " ms"
func num(x: float): string =
  ## A time in milliseconds without its unit, for a table that names it once.
  if x >= 100: $int(round(x)) else: formatFloat(x, ffDecimal, 1)
func times(x: float): string = formatFloat(x, ffDecimal, 1) & "×"
func pct(part, whole: float): string = $int(round(100 * part / whole)) & "%"

let
  cases = bench["cases"].getInt
  cWarm = warm(bench, "c")
  jsWarm = warm(bench, "js")
  peleWarm = warm(bench, "pele")
  nodeStart = bench["nodeStart"].getFloat
  cFresh = engines["c"]["cold"].getFloat
  jsFresh = nodeStart + engines["js"]["load"].getFloat + engines["js"]["cold"].getFloat
  peleFresh = nodeStart + engines["pele"]["load"].getFloat + engines["pele"]["cold"].getFloat
  cBefore = warm(before, "c")
  cSlower = types.filterIt(fastest(bench, "c", it) > 1.1 * fastest(bench, "pele", it))
  cAnySlower = types.filterIt(fastest(bench, "c", it) > fastest(bench, "pele", it))
  jsRatios = types.mapIt(fastest(bench, "js", it) / fastest(bench, "pele", it))
  rounds = bench["rounds"].getInt

# The JavaScript profile.
let
  jsTotal = profile["totalMs"].getFloat
  helpers = profile["helpers"]
  copyMs = helpers["copies"]["ms"].getFloat
  skipMs = helpers["skipTable"]["ms"].getFloat
  strMs = helpers["toJSStr"]["ms"].getFloat
var gcMs = 0.0
for f in profile["functions"]:
  if f["name"].getStr == "(garbage collector)": gcMs = f["ms"].getFloat
let runtimeMs = copyMs + skipMs + strMs + gcMs
proc copiedBy(name: string): float =
  for b in helpers["copies"]["by"]:
    if b["name"].getStr == name: return b["ms"].getFloat
  raiseAssert "the profile has no copies by " & name
let
  coreCopies = copiedBy("detect.detectDiagram") + copiedBy("core.withIcons") + copiedBy("core.withMath")

# The C profile: lines `instructions (percent%) file:function`.
proc profileLines(file: string): seq[(float, string)] =
  for line in lines(here / file):
    let open = line.find('(')
    let close = line.find("%)")
    if open < 0 or close < 0 or "PROGRAM TOTALS" in line: continue
    result.add (parseFloat(line[open + 1 ..< close].strip), line[close + 2 .. ^1].strip)
let
  cSelf = profileLines("c-self.txt")
  cIncl = profileLines("c-inclusive.txt")
proc inclusive(fn: string): float =
  for (p, name) in cIncl:
    if fn in name: return p
  raiseAssert "the C profile has no " & fn
proc inclusiveAll(fn: string): float =
  ## The C compiler made two copies of some functions: their lines add up.
  for (p, name) in cIncl:
    if fn in name: result += p
proc selfOf(files: openArray[string]): float =
  for (p, name) in cSelf:
    if name.split(':')[0] in files: result += p
let
  cAlloc = selfOf(["alloc.nim"])
  cRegex = selfOf(["nfamatch2.nim", "nfafindall2.nim", "nfatype.nim", "nodematch.nim", "regex.nim",
                   "nfa.nim", "litopt.nim"])
  cParse = inclusive("core::parseSource(")
  cDraw = inclusive("core::renderParsed(")
  cDetect = inclusive("detect::detectDiagram(")
  cMatchEnd = inclusiveAll("jsregex::matchEnd(")

doAssert cWarm < peleWarm and jsWarm > 5 * peleWarm, "the findings below say who is faster: check them"
doAssert cFresh < peleFresh / 2, "the findings say that C starts much faster: check them"

nbText: &"""
## The findings, first

- **nimaki's C build draws the corpus a little faster than Pele.** The corpus has {cases}
  diagrams of {types.len} types. Once each engine has warmed up, nimaki compiled to C draws all of
  them in {ms(cWarm)}. Pele, in Node, takes {ms(peleWarm)}. So C is {times(peleWarm / cWarm)} as
  fast.
- **C is not faster everywhere.** Pele is faster on {cAnySlower.len} of the {types.len} types,
  and faster by more than 10% on {cSlower.len}: {cSlower.mapIt("*" & it & "*").join(", ")}.
- **In a fresh program, C wins easily.** A program that starts, draws the corpus once and stops
  takes {ms(cFresh)} in C. With Pele it takes {ms(peleFresh)}: Node must start, load Pele, and
  compile Pele's code while it runs. This is how diagrammari draws today, in a Node process at
  build time.
- **nimaki's JavaScript build is about ten times slower than Pele.** It takes {ms(jsWarm)} for
  the corpus, {times(jsWarm / peleWarm)} Pele's time. Depending on the type, it is between
  {times(jsRatios.min)} and {times(jsRatios.max)} slower.
- **In JavaScript, much of the time is spent on Nim's own bookkeeping.** {pct(copyMs, jsTotal)}
  of it goes to copies that Nim makes of values, and {pct(runtimeMs, jsTotal)} to Nim's helpers
  in all (copies, string conversion, search tables, garbage collection). Three small functions
  that run once per diagram cause {pct(coreCopies, copyMs)} of the copies.
- **In C, regular expressions and memory take the most time.** At least {pct(cRegex, 100)} of the
  time is spent inside the regular expression library, and {pct(cAlloc, 100)} in Nim's memory
  allocator.
- **One small fix is in this pull request.** The C build counted every SVG's length one
  character at a time, only to compare it with a limit. Now it checks the length in bytes first.
  The C time went from {ms(cBefore)} to {ms(cWarm)}, and every drawing is still identical to Pele's.
"""

nbText: """
## What a benchmark is

A *benchmark* runs the same work on several programs, under the same conditions, and times them.
Here the work is the corpus, every case of `corpus/cases.json`. The referee checks these same
cases (post [The referee](../the-referee/)), so we know already that the three engines draw the
same bytes. The only open question is how long each one takes.

The three engines:

- **C**: nimaki compiled to C with `-d:release`, Nim's normal fast mode. The benchmark calls
  `render` directly.
- **JavaScript**: `nimaki.js`, the file a web page loads (built by `tools/webbuild.nim`, minified),
  run in Node.
- **Pele**: Pele's npm package, `dist/pele.js`, in the same Node.

All three draw with a fixed `now`, as the referee does. Two words matter for reading the numbers:

- **Warm** is the time once the engine has already done the work a few times. JavaScript engines
  like Node's V8 have a *JIT* (just-in-time compiler). V8 first runs a function slowly. When the
  function runs often, V8 compiles it to machine code, based on the values it saw. So the first
  pass is slow and later passes are fast. A warm time is the *fastest* of several rounds, which
  hides the moments when the machine was busy with something else.
- **Cold** is the first pass in a new process: nothing cached and nothing compiled yet. A program
  that draws a few diagrams and exits only ever sees cold times.

`tools/bench.nim` does both. It measures a cold pass in a fresh process for each engine, then
draws each type several times. In Node, the rounds alternate Pele and nimaki, so that a slow
moment of the machine falls on both. It also counts the characters of every SVG, a quick check
that the three drew the same thing.

```sh
nim c -d:release -o:build/bench/bench tools/bench.nim
build/bench/bench --rounds:10 --out:bench.json
```
"""

nbNote &"""
The numbers come from one machine: the cloud sandbox where this post was written, with
{bench["cores"].getInt} cores of an {bench["cpu"].getStr}, Nim {bench["nim"].getStr} and Node
{bench["node"].getStr}. Another machine gives other numbers, but the ratios between the engines
should stay close. They still move from run to run. Summed over the types, the *median* round
(the middle one) is {pct(warmMedian(bench, "c") - cWarm, cWarm)} slower than the fastest round
for C, {pct(warmMedian(bench, "js") - jsWarm, jsWarm)} for nimaki.js and
{pct(warmMedian(bench, "pele") - peleWarm, peleWarm)} for Pele. Do not read much into a
difference of 10% for one type.
""", nkWarning, "One machine, some noise"

nbText: """
## The whole corpus

Each bar is the corpus drawn once, warm: the sum of the fastest round of each type. nimaki draws
this chart itself, and the build checks that Pele draws it the same.
"""

let chartWarm = &"""xychart-beta
  title "The corpus, warm (ms)"
  x-axis ["nimaki C", "nimaki.js", "Pele"]
  y-axis "milliseconds"
  bar [{int(round(cWarm))}, {int(round(jsWarm))}, {int(round(peleWarm))}]
"""
nbMermaid chartWarm, &"The {cases} cases, fastest of {rounds} rounds per type."

nbText: &"""
A fresh program is a different story. Here each bar is a program that starts, draws the corpus
once and stops. For Node, it adds three parts: starting Node ({ms(nodeStart)}, measured with
`node -e 0`), loading the engine's file ({ms(engines["pele"]["load"].getFloat)} for Pele,
{ms(engines["js"]["load"].getFloat)} for nimaki.js, which is bigger), and the cold pass. For C,
the bar is only the cold pass: a C program starts in about a millisecond, which this benchmark
does not measure.
"""

let chartFresh = &"""xychart-beta
  title "A fresh program, corpus once (ms)"
  x-axis ["nimaki C", "nimaki.js", "Pele"]
  y-axis "milliseconds"
  bar [{int(round(cFresh))}, {int(round(jsFresh))}, {int(round(peleFresh))}]
"""
nbMermaid chartFresh, "Start, load, and the first pass over every type."

nbText: &"""
The cold pass shows the JIT at work. Pele's first pass takes {ms(engines["pele"]["cold"].getFloat)},
{times(engines["pele"]["cold"].getFloat / peleWarm)} its warm time, because V8 is still compiling.
C has nothing to compile while it runs: its first pass takes {ms(cFresh)}, only
{times(cFresh / cWarm)} its warm time (the caches, such as the widths of text already measured,
are still empty).

For diagrammari, which draws the diagrams of a page while the page is built, this is the number
that counts: a few diagrams, in a new process. One diagram takes the C build
{ms(cFresh / cases.float)} on average, cold, while Node alone takes {ms(nodeStart)} to start.
"""

nbText: """
## Type by type

Each row is the fastest of the rounds for the cases of one type (the
[Coverage map](../../coverage/) says how many cases each type has). *C* is the C build and *JS* is nimaki.js. *C vs Pele* says how many times
faster C is (more than 1×) or slower (less than 1×). *JS vs Pele* says how many times slower
nimaki.js is than Pele.
"""

block:
  type Row = object
    diagram, c, js, pele, cVsPele, jsVsPele: string
  var rows: seq[Row]
  for t in types:
    let c = fastest(bench, "c", t)
    let j = fastest(bench, "js", t)
    let p = fastest(bench, "pele", t)
    rows.add Row(diagram: t, c: num(c), js: num(j),
                 pele: num(p), cVsPele: times(p / c), jsVsPele: times(j / p))
  let t = tabella(rows, rownameCol = "diagram"):
    tabHeader "The corpus, type by type", &"fastest of {rounds} rounds, in milliseconds"
    colsLabel {"c": "C", "js": "JS", "pele": "Pele", "cVsPele": "C vs Pele", "jsVsPele": "JS vs Pele"}
    optCssTheme()
  nbTable t

nbText: &"""
Pele is faster than C on several types, such as *railroad*, *wardley* and *gitGraph*. A likely
reason, not checked type by type, is regular expressions. V8's regular expression engine compiles each
pattern to machine code. The C build uses nitely's pure Nim `regex` library (decision 0016),
which runs the pattern step by step. The next section shows how much of C's time goes there.

nimaki.js is slower than Pele on every type, and most on the small ones: on *pie* and *info*
the drawing itself is short, so the fixed costs of each call stand out. Those costs are the
subject of the next section too.
"""

nbText: &"""
## Where nimaki.js spends its time

A *profiler* watches a program while it runs and says where the time goes. Node has one built in
(`node --cpu-prof`): many times a second, it notes which function is running. Summing those notes
gives each function's *self time*, the time spent in its own code and not in the functions it
calls. The profile was taken on nimaki.js before minifying, so that the functions keep their Nim
names, while it drew the corpus {profile["rounds"].getInt} times
(`docs/devlog/data/how_fast_nimaki_draws/profile.mjs`).
"""

block:
  type Row = object
    function, ms, share: string
  var rows: seq[Row]
  for f in profile["functions"].getElems[0 ..< 10]:
    rows.add Row(function: f["name"].getStr, ms: ms(f["ms"].getFloat), share: pct(f["ms"].getFloat, jsTotal))
  let t = tabella(rows, rownameCol = "function"):
    tabHeader "nimaki.js, the ten functions with the most self time", &"""of {ms(jsTotal)} sampled, Node {profile["node"].getStr}"""
    colsLabel {"ms": "self time", "share": "of the total"}
    optCssTheme()
  nbTable t

nbText: &"""
The first two lines are not nimaki's code. `nimCopy` and `nimCopyAux` are the functions that Nim
adds to its JavaScript to *copy* a value. In Nim, assigning an object or a sequence makes a new
copy: changing the copy does not change the original. JavaScript shares objects instead. To keep
Nim's meaning, `nim js` writes a copy wherever the program might change one of them. In C, Nim
can often *move* the value instead (hand it over without copying), but `nim js` does that much
less often. The earlier posts on speed ([Faster in JavaScript](../faster-in-javascript/) and those
after it) found and removed many such copies. Together they still take {pct(copyMs, jsTotal)} of
the time.

Three functions that run once per diagram ask for {pct(coreCopies, copyMs)} of those copies:
`detectDiagram`, which walks Pele's list of type detectors (a constant list: the loop seems to
copy each entry), and `withIcons` and `withMath`, which save and restore the host's icons and math for
each call. They are good candidates for the next round of speed work.

The other helpers in the table are Nim's too. `toJSStr` turns a Nim string, which is stored as
UTF-8 bytes, into a JavaScript string; almost all of its {ms(strMs)} is the finished SVG, turned
once per call. `nsuInitNewSkipTable` builds a search table each time `strutils.find` looks for a
string inside another ({ms(skipMs)}). And the *garbage collector*, which frees the memory nobody
uses any more, takes {ms(gcMs)}. Pele, written in JavaScript to begin with, pays for none of
these, or pays much less.
"""

nbText: &"""
## Where the C build spends its time

For C, the profiler is valgrind's *callgrind*. It does not sample: it counts every machine
instruction each function runs. It is slow (the program runs many times slower), but it is
exact, and the same on every run. It counted the benchmark drawing the corpus three times: the
cold pass, one round, and the pass that counts the characters
(`docs/devlog/data/how_fast_nimaki_draws/cprofile.sh`).

- **Reading** the text (`parseSource`: finding the type, then the parser) takes
  {pct(cParse, 100)} of the instructions, and **drawing** (`renderParsed`: layout and SVG) takes
  {pct(cDraw, 100)}.
- **Regular expressions** run inside all of that. One of the entry points into the library
  alone, `matchEnd`, takes {pct(cMatchEnd, 100)}, and at least {pct(cRegex, 100)} of the time is
  spent in the library's own code. Pele's parsers use some 150 regular expressions, and the port
  keeps each one as Pele wrote it (post
  [Regular expressions, as Pele writes them](../regular-expressions-as-pele-writes-them/)).
- **Finding the type** (`detectDiagram`) takes {pct(cDetect, 100)}. Pele tries each detector's
  pattern on the text in turn, and so does nimaki. Each pattern starts with `^`, so V8 gives up
  after the first character. The C library seems to try every position of the text before it
  gives up: this was not checked further, and is a lead for later.
- **Memory**: Nim's allocator takes {pct(cAlloc, 100)} of the instructions, for the many small
  strings and sequences that a drawing makes and drops.
"""

nbNote &"""
Callgrind showed one more thing, which this pull request fixes. Pele refuses an SVG longer than a
limit, measured in JavaScript characters (UTF-16 code units). nimaki stores strings in UTF-8, so
it counted the characters of every SVG one by one, on every call, only to compare them with a
limit of four million. Now it checks the size in bytes first. A character never takes more UTF-16
units than it takes UTF-8 bytes, so a text that fits in bytes also fits in characters, and the
count is only needed for a text that is close to the limit (`utf16LongerThan` in
`src/nimaki/js.nim`). The C build's warm time for the corpus went from {ms(cBefore)} to
{ms(cWarm)}. The referee still finds every case identical to Pele's, in C and in JavaScript.
""", nkNim, "A fix found on the way"

nbNote """
Should the next step close the gap in JavaScript? The profile points at the first targets: the
copies in `detectDiagram`, `withIcons` and `withMath`, and `strutils.find`'s search tables. A
second option is to make the benchmark a CI check, but runs on GitHub's shared machines vary
more than this sandbox does, so the check would only catch large slowdowns.
""", nkQuestion, "For Pietro"

nbText: &"""
## What this changes for the port

- The port now has a benchmark: `tools/bench.nim` times the C build, nimaki.js and Pele on the
  corpus, per type, cold and warm, and writes the numbers to a JSON file. Any later speed work
  can measure itself with it.
- For a Nim program, such as diagrammari building a page, the C build is already faster than
  calling Pele through Node, and much faster when the program starts fresh.
- For a web page, nimaki.js is correct but about ten times slower than Pele. One case takes
  {ms(jsWarm / cases.float)} on average, which a reader does not notice for a few diagrams, but a
  page with hundreds of them would. The profile above lists where to look first.
- In C, the regular expression library and the type detection are the next leads, after the
  small fix of this post.

## Sources

- The numbers: `build/bench/bench --rounds:10 --out:...`, run on 17 November 2026, written to
  `docs/devlog/data/how_fast_nimaki_draws/bench.json`, and `before.json` for the run before the fix.
- The JavaScript profile: `profile.mjs` in the same folder, written to `profile.json`.
- The C profile: `cprofile.sh` in the same folder ([valgrind's callgrind](https://valgrind.org/docs/manual/cl-manual.html)),
  written to `c-self.txt` and `c-inclusive.txt`.
- Node's [`--cpu-prof`](https://nodejs.org/api/cli.html#--cpu-prof) option, and V8's own
  explanation of its [regular expression compiler](https://v8.dev/blog/regexp-tier-up).
- Pele's `src/core.ts` at the pin: the output limit, measured with `svg.length`.
"""

nbSave
