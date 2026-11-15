## devlog: 15 Nov 2026 G | Copies on the way out | The fourth round on the JavaScript build's speed: a drawing of megabytes was copied whole at each wrapper it passed on its way out, and a source text at each step of reading it. Handed over instead, with a few smaller fixes, each of the 12 tests that were over Pele's time limit runs within it when run alone.
## kind: port
import std/[strformat, strutils, json, re, sequtils]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site
import nimaki/js

nbInit
nb.usePost()

let dataDir = docsDir / "devlog" / "data" / "copies_on_the_way_out"
let before = parseFile(dataDir / "before.json")["before"].getElems
let after = parseFile(dataDir / "after.json")
let left = after["speed"].getElems
let rows = parseFile(dataDir / "timings.json")["rows"].getElems
var limitOf: seq[(string, int)]
for b in before:
  var m: array[1, string]
  if b["message"].getStr.find(re"to be less than ([0-9]+)", m) >= 0: limitOf.add (b["test"].getStr, parseInt(m[0]))
proc limit(test: string): int =
  for (name, l) in limitOf:
    if name == test: return l
var within, withinBefore = 0
for r in rows:
  if r["after"][0].getInt < limit(r["test"].getStr) and r["after"][1].getInt < limit(r["test"].getStr): inc within
  if r["before"][0].getInt < limit(r["test"].getStr) and r["before"][1].getInt < limit(r["test"].getStr): inc withinBefore
let beforeNames = before.mapIt(it["test"].getStr)
let again = left.filterIt(it["test"].getStr in beforeNames).len
func n0(x: float): string = $int(x + 0.5)  ## a whole number of milliseconds
proc ms(message: string): (string, string) =
  ## The time a test took and its limit, from vitest's message.
  var m: array[2, string]
  if message.find(re"expected ([0-9.]+) to be less than ([0-9]+)", m) >= 0: (n0(parseFloat(m[0])), m[1])
  else: ("", "")

nbText: &"""
## The findings, first

- **{before.len} of Pele's tests were over their time limit** in nimaki's JavaScript build after
  [the last round](../javascripts-own-regular-expressions/), all in nimaki's own code. Every
  drawing was already the same as Pele's.
- **The largest cost was a copy nobody wrote.** When a function hands back an object, the
  JavaScript that Nim writes copies it into the caller's result, every byte of its strings. A
  drawing passes through seven or eight small functions on its way out (a palette, math, icons,
  error tags), so a drawing of ten megabytes was copied seven or eight times.
- **The same held for the source text** on its way in: each step of preprocessing handed back a
  new text, and each was copied once more.
- **A new helper, `handOver`, hands the value over instead**, as JavaScript itself would, where a
  long value passes through. Smaller fixes took care of the rest: lists of classes, a boundary's
  members, a table made for every vertex, and a few spots that built an object at each character.
- **Run one at a time, {within} of the {rows.len} tests are now within their limit**, against
  {withinBefore} before, and each is faster. On a full run of Pele's tests, four at once on four cores, {after["counts"]["speed"].getInt}
  tests still go over, and a different few each run: tests that are near their limit land on either
  side of it when they share the machine.
- Nothing else changed: every drawing and every model is still the same as Pele's, in both builds.
"""

nbText: """
## A copy you do not see

Nim has *value semantics*: when you write `b = a` for a string, `b` gets its own copy, and
changing `b` later leaves `a` alone. In C, Nim gets this cheaply: when `a` is never read again,
the compiler moves it into `b` instead of copying it. Here is the helper this step adds, run in C,
where it is just an assignment:
"""

nbCode:
  type Drawing = object
    svg: string
    width: float

  proc draw(): Drawing = Drawing(svg: "<svg>" & "<rect/>".repeat(3) & "</svg>", width: 120)

  proc withWrapper(run: proc (): Drawing): Drawing =
    # set something up, run, tidy up: the shape of withPalette, withMath, withIcons
    handOver(result, run())

  echo withWrapper(draw).svg

nbText: """
In JavaScript, a Nim string is an array of bytes. JavaScript shares an array when it is
assigned, so to keep value semantics Nim's JavaScript backend copies it. It does not look for the
cases where nothing else holds the value: `result = run()` becomes a copy of the whole object,
strings and lists inside it included, even though `run()` has just made it. This is what Nim
writes for `result = run()`, and for `handOver(result, run())`:

```js
result = nimCopy(result, run(), NTI_Drawing);   // result = run()
var fresh = run(); result = fresh;              // handOver(result, run())
```

`nimCopy` walks the type of `Drawing` and copies each field: for the `svg` string, a new array of
every byte. A drawing of ten megabytes is ten million numbers copied.

`handOver(dst, value)` is in `js.nim`, beside `moveField` from [an earlier
round](../hashing-in-javascript/). In C it is `dst = value`. In JavaScript it writes the plain
assignment. It is for a value nothing else holds: a call, or a local variable that is not read
again. Used on a value that something else still changes, both would change together; so it
goes only where a long value passes through, with a comment saying why.

## Where the drawing went

A class diagram with a namespace of 3,000 parts draws a name of up to 6,000 characters for each
of its 3,000 nested boxes. The drawing is almost ten million characters, and a profile of the test showed
more than a second in `nimCopy`, under these callers, each one a function that hands the drawing up:

- `draw` builds `Rendered(svg: svg, ...)`, and `withTitle` builds the content under the title;
- `tighten` and `turnToFit` draw a diagram a second way when the first is too wide, and return one;
- `renderClass`, then `withIcons`, `withMath`, `withPalette`, `tagErrors` and `guarded` in
  `core.nim`, each a wrapper that sets something up around the drawing and returns it;
- `renderParsed` and `render`, which copy it into the result the host gets.

Each now hands the drawing over or sets its result field by field. (The drawing is then refused,
as it is in Pele: it is longer than the output limit of four million characters, and the test
expects that error. The copies were all made before the check.) With that, both class namespace
tests passed, and so did several tests of other types that draw large diagrams,
since all of them go through `core.nim`.

The source text had the same story on its way in. `preprocess` makes a new text at each step
(line breaks, HTML tags, front matter, directives, comments), and each was copied when it was
assigned; `parseSource` copied it again into each closure that captured it. A text that is only
ever replaced, never changed in place, can be shared between those steps. An outline 3,000 levels
deep spent half as long in copies after this.

## Smaller ones

- **A use case class statement on 2,500 ids and 4,000 classes.** Pele adds each class to each
  element unless it is there already: ten million checks. nimaki made a set for each element; it
  now removes the repeats from the 4,000 classes once, and adds the result as it is to each
  element that has no classes yet, which is the same list.
- **A boundary with 10,000 members** checked each new member against the list of those before
  it, fifty million comparisons in all; a set beside the list answers at once.
- **A state named in a class statement 1,500 times** has a list of 1,500 times `hot`, and each
  time the state is drawn the list is read again, one table lookup per name. A name the same as
  the one before is not looked up again.
- **Agentflow's 10,000 vertices** each got a table of properties made with `initTable`, which
  makes 32 empty slots, and then copied twice into an `Option`. It now starts with a table that
  has made no slots yet.
- **A namespace's full name**, thousands of characters long, is the key of a table: it is now a
  `StrKey` ([Dates and styles in JavaScript](../dates-and-styles-in-javascript/)), hashed in place.
- **Per character**: the shortcut that matches a run of one class (`\s+`) read each character
  as a tuple, which nim js copies; and the bridge that runs Pele's tests on nimaki tested each
  character with `c in 0xD800 .. 0xDBFF`, which builds the range as an object each time.
- **The models Pele's `parse()` tests read** go through JSON in that bridge: its objects of
  thousands of keys now have room for them from the start, and are walked without copying their
  table, which json's own `pairs` does in nim js.
"""

block:
  type Row = object
    test: string
    limit: int
    before, after: string
  var t: seq[Row]
  for r in rows:
    t.add Row(test: r["test"].getStr, limit: limit(r["test"].getStr),
              before: $r["before"][0].getInt & ", " & $r["before"][1].getInt,
              after: $r["after"][0].getInt & ", " & $r["after"][1].getInt)
  let table = tabella(t, rownameCol = "test"):
    tabHeader "The tests over Pele's time limit before this round", "milliseconds, each test run alone, twice: with main before this round, and with it; limit: Pele's"
    fmtInteger ["limit"]
    optCssTheme()
  nbTable table

nbText: &"""
Run alone, the same test can take up to a fifth more or less from one run to the next, as the two
columns show. Run with Pele's whole suite, four files at a time, a test shares the machine with
three others, and takes longer still. A test that ran alone a little under its limit, like the
nested namespaces at 2.7 seconds against 3, can go over. On the last full run,
{after["counts"]["speed"].getInt} tests went over:

{left.mapIt("- " & it["test"].getStr & ": " & ms(it["message"].getStr)[0] & " ms against " & ms(it["message"].getStr)[1]).join("\n")}

{again} of them were among the {before.len}. Two full runs before that, during this round, gave 6
each, and not the same 6, and the two C4 tests went over on neither. These are the next ones to
look at.

## What this changes for the port

- `handOver` of `js.nim` hands a long value to its place without a copy in the JavaScript build.
  The porting guide's note *Code that JavaScript runs slowly* says where it goes: a value handed
  back through wrappers, an object built whole, a text replaced step by step. A value handed over
  must not be changed in place afterwards.
- `locatingIn` in `errors.nim` takes the parsed text and its finder, not an `Origin`.
- The step *Pele's time bounds in the JavaScript build* on the [roadmap](../../roadmap/) stays
  open while any test is over its limit.

## Sources

- The fixes: `src/nimaki/js.nim` (`handOver`), `core.nim`, `errors.nim`, `preprocess.nim`,
  `svg/root.nim`, `svg/title.nim`, `svg/palette.nim`, `text/icons.nim`, `text/math.nim`,
  `diagrams/common/fit_width.nim`, `diagrams/class/render.nim`, `diagrams/usecase/db.nim`,
  `diagrams/state/graph.nim`, `diagrams/agentflow/db.nim`, `jsregex.nim` (`codeAt`, `inRun`),
  `tools/peletests/bridge.nim` (`wtf8`).
- The data: `docs/devlog/data/copies_on_the_way_out/`: `before.json` (the tests over their limit
  on `main` before this round, from `docs/data/peletests.json`), `timings.sh` over `tests.tsv`
  (each test alone) into `timings.json`, and `after.json` (the last full run, `nim r
  tools/peletests.nim`).
- How Nim's JavaScript backend copies: `nimCopy` in `lib/system/jssys.nim` of
  [Nim](https://github.com/nim-lang/Nim/blob/devel/lib/system/jssys.nim).
"""

nbSave
