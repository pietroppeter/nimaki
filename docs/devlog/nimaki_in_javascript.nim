## devlog: 13 Nov 2026 H | nimaki in JavaScript | Nim also compiles to JavaScript, and nimaki compiled that way now draws every ported case as Pele does, once two lines of Nim that only C could run were written another way.
## kind: tooling
import std/[strformat, strutils, json, algorithm]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site

nbInit
nb.usePost()

let js = parseFile(docsDir / "data" / "js.json")
let dt = js["difftest"]
var fuzzCases, fuzzIdentical, fuzzTypes = 0
for kind, run in js["fuzz"]:
  fuzzCases += run["cases"].getInt
  fuzzIdentical += run["identical"].getInt
  inc fuzzTypes
let megabytes = formatFloat(js["bytes"].getInt / 1_000_000, ffDecimal, 1)

nbText: &"""
## The findings, first

- **The same code, a second target.** Nim compiles to C, and also to JavaScript. nimaki compiled
  to JavaScript (`nim js`) and run in Node now draws **{dt["identical"].getInt.thousands}** of Pele's
  corpus cases byte for byte as Pele does, the same {dt["identical"].getInt.thousands} the C build draws,
  and {dt["diagrammari"]["identical"].getInt} of diagrammari's. It differs on {dt["different"].getInt}.
- **Generated inputs agree too:** {fuzzIdentical.thousands} of {fuzzCases.thousands} generated
  cases, over the {fuzzTypes} ported types the fuzzer knows.
- **It compiled at once.** The renderer uses only Nim's standard library, which runs in both. A
  first run drew most cases right. The rest failed on two ways of writing Nim that the C backend
  runs and the JavaScript backend does not. Both are rewritten, and the porting guide now lists
  them.
- **Checked on every pull request.** `tools/difftest.nim --js` compiles the JavaScript build and
  compares it with Pele, and CI runs it. Decision 0013 records that nimaki builds both ways.
- **Not yet in a browser.** The build runs in Node; a page that draws with it, and making the
  {megabytes} MB file smaller, come next.

## Compiling to JavaScript

A *compiler* turns a program into another language, usually one closer to the machine. Nim's
usual target is C, which a C compiler then turns into machine code. Nim has a second *backend*
that writes JavaScript instead, so the same Nim program can run in Node or in a browser. Pele is
written in TypeScript, which becomes JavaScript too: compiled this way, nimaki can run wherever
Pele runs.

The two backends have to map Nim's values onto very different machines. In C an `int` is 64 bits
and a `ref` is an address in memory. In JavaScript there are no addresses: an object is a value
the engine moves around, and a number is a 64-bit float. So Nim writes a `ref object` as a
JavaScript object, a `seq` as an array, a `string` as an array of bytes, and an address, which
has no JavaScript equivalent, as a pair: the object that holds the value and the name of its
field. Almost all of nimaki maps cleanly. Two things did not.

## The first: an address picked by `if`

The layered layout (`layout/layered.nim`, the port of Pele's `layout/layered.ts`) runs the same
sweep down and up the layers of a graph. Going down it reads a node's predecessors, going up its
successors. Pele picks one of two arrays; the port picked the address of one of two `seq`s, so
as not to copy them:
"""

nbText: """
```nim
let startP = if down: addr g.predStart else: addr g.succStart
template start: untyped = startP[]
```

In C that is a pointer, and it works. In JavaScript the address is the pair (object, field), and
when the address comes out of an `if` expression, Nim 2.2's JavaScript backend keeps the object
but loses the field name: reading through it gives `undefined`, and the sweep stops with
`Cannot read properties of undefined (reading 'length')`. An `if` statement that assigns the
address does not have the problem, so a small helper does that:

```nim
proc choose[T](cond: bool, a, b: var T): ptr T {.inline.} =
  if cond: result = addr a
  else: result = addr b

let startP = choose(down, g.predStart, g.succStart)
```

Every type drawn on the layered layout (flowchart, state, class, er, requirement, use case) had
cases that failed this way, and they all work now.

## The second: a reference as a number

Pele's railroad renderer and gantt renderer keep a `Map` keyed by object, which in JavaScript
compares objects by identity. The port keyed a `Table` by the object's address,
`cast[int](node)`. In JavaScript there is no address to turn into a number, and the hash of the
key failed with `Cannot convert [object Object] to a BigInt`. The fix keys the table by the
reference itself, with a hash that Nim's standard library gives a meaning in both backends: the
address in C, and in JavaScript an id it stores on the object the first time it is asked.

```nim
proc hash(r: RailroadNode): Hash = hash(cast[pointer](r))
var budgets = initTable[RailroadNode, float]()
```

## How the referee runs it

The referee, `tools/difftest.nim`, compares Pele's SVG with nimaki's. Until today it called
nimaki inside its own process. With `--js` it compiles `tools/jsrunner.nim` with
`nim js -d:nodejs -d:release`, gives it every case in a file, runs it in Node with `TZ=UTC`, as
the oracle runs, and compares what it writes with Pele's answers, byte for byte, as before.
`tools/fuzz.nim --js` does the same with generated inputs. Both record their last run in
`docs/data/js.json`, which this page reads:
"""

block:
  type Row = object
    `type`: string
    cases, identical: int
  var rows: seq[Row]
  for kind, run in js["fuzz"]:
    rows.add Row(`type`: kind, cases: run["cases"].getInt, identical: run["identical"].getInt)
  rows.sort(proc (a, b: Row): int = cmp(a.`type`.toLowerAscii, b.`type`.toLowerAscii))
  let t = tabella(rows, rownameCol = "type"):
    tabHeader "Generated inputs, JavaScript build", "the last run of tools/fuzz.nim --js for each type"
    colsLabel {"identical": "same SVG"}
    fmtInteger ["cases", "identical"]
    optCssTheme()
  nbTable t

nbNote """
- `tools/answers.nim` holds nimaki's side of the referee for both builds (the options, the answer,
  and `jsAnswers`, which compiles and runs the JavaScript build); `tools/jsrunner.nim` is the
  program compiled with `nim js`.
- The two fixes are in `layout/layered.nim`, `diagrams/railroad/render.nim` and
  `diagrams/gantt/render.nim`. They change no output of the C build: the corpus and the fuzzer
  give the same results as before.
- No `when defined(js)` was needed in the renderer.
""", nkNim, "In the port"

nbNote &"""
- `difftest --js`: {dt["identical"].getInt} of {dt["cases"].getInt} of Pele's cases identical,
  {dt["unsupported"].getInt} of types not ported yet; {dt["diagrammari"]["identical"].getInt} of
  {dt["diagrammari"]["cases"].getInt} of diagrammari's.
- `fuzz --js`: {fuzzIdentical.thousands} of {fuzzCases.thousands} generated cases identical, over
  {fuzzTypes} types.
- CI runs `difftest --js --check-done` on every pull request.
""", nkDone, "Checked"

nbNote &"""
- Only in Node. A browser has no `require('fs')`; the build for a page needs its own small entry
  point (`render(text)` exported to JavaScript), which is the next part of this step.
- The file is {megabytes} MB, unminified. Nim can drop the parts no page needs, and a minifier can
  do the rest; nothing was tried yet.
- Speed was not measured.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **A ported file must also compile to JavaScript**, and CI checks it: rule 9 of the
  [porting guide](../../porting/), with the two traps above.
- **nimaki can run where Pele runs.** The next step is a page whose diagrams nimaki draws in the
  reader's browser.

## Sources

- Nim's standard library, `hashes.nim` (the id it gives an object in JavaScript), read in the
  installed Nim 2.2. The behaviour of an address picked by `if` was found by a small program
  compiled both ways, not in Nim's documentation; its page on
  [backends](https://nim-lang.org/docs/backends.html) was not read for this step.
- The code of this step: [`tools/jsrunner.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/jsrunner.nim),
  [`tools/answers.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/answers.nim),
  [`src/nimaki/layout/layered.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/layout/layered.nim).
"""

nbSave
