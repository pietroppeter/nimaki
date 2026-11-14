## devlog: 14 Nov 2026 M | Faster in JavaScript | The JavaScript build drew Pele's stress tests right but slowly, up to twelve times over Pele's limit. A profiler found one function behind almost all of it, copying, and eight small changes took most of those tests under the limit.
## kind: port
import std/[strformat, strutils, json, sequtils, math, algorithm]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site
import nimaki/js

nbInit
nb.usePost()

let timings = parseFile(docsDir / "devlog" / "data" / "faster_in_javascript" / "timings.json")
let now = parseFile(docsDir / "data" / "peletests.json")["counts"]
let before = timings["countsBefore"]
let tests = timings["tests"].getElems
let fixedTests = tests.filterIt(it["afterStatus"].getStr == "passed")
let worstBefore = tests.mapIt(it["before"].getInt).max
let speedups = fixedTests.mapIt(it["before"].getInt / it["after"].getInt)
let medianSpeedup = block:
  var s = speedups
  s.sort(system.cmp)
  s[s.len div 2]

nbText: &"""
## The findings, first

- **Pele's stress tests are a stopwatch.** Some of Pele's tests draw a huge diagram (5,000 states,
  a label of 50,000 characters) and fail when that takes longer than a limit, usually three
  seconds. nimaki's JavaScript build drew all of them the same as Pele, but
  {before["speed"].getInt} of them too slowly ([the post that ran them](../pele-tests-on-nimaki/)).
  The slowest of those timed below took {worstBefore div 1000} seconds, run alone.
- **Almost all of the time went into copying.** A profiler, which samples which function is
  running a thousand times a second, put one function on top of nearly every slow test:
  `nimCopy`, the function the Nim compiler uses in JavaScript to copy a value.
- **Eight patterns of ordinary Nim copy far more in JavaScript than they look.** Each was a small
  change: a helper that became a template, a field read without a copy, a list shared by
  reference. On the {fixedTests.len} tests timed here, the median one is **{int(round(medianSpeedup))}
  times faster**.
- **{now["speed"].getInt} tests are still over the limit**, down from {before["speed"].getInt}.
  The worst of the rest hash long strings (class namespaces, gantt dates); many others are near
  the limit, in code that the coming change to regular expressions rewrites, so they wait for it.
- **Nothing drawn changed.** The referee, the fuzzers and Pele's tests find every drawing
  identical, in C and in JavaScript.
"""

nbText: """
## Why a copy can be slow

In JavaScript a string is a value the engine shares: `let b = a` gives a second name to the same
characters, and nothing is copied. Nim promises something else: a `string` or a `seq` behaves as
if each variable had its own, so changing `b` never changes `a`. In C the compiler keeps that
promise cheaply, often by moving instead of copying. In JavaScript, Nim represents a string as an
array of bytes, which the engine does not share safely, so the compiler copies it, byte by byte,
wherever the promise could be broken.

One copy of a 50,000-character label is nothing. One copy *per character* is 2.5 billion bytes
moved. Every slow test had a copy that happened once per something small (a character, a token,
a node) of something large (the whole source, the whole label, every edge).

To see which, the tests ran with Node's profiler (`node --cpu-prof`), which writes, every
millisecond, which function is running and who called it. Adding the samples up by caller gives
lines like this one, for the venn diagram with 5,000 style statements:

```
  28095ms next   (the venn lexer, called once a token)
     79ms addStyleData
```

and the JavaScript that `next` compiled to shows the copy on its first line:

```js
var src = nimCopy(null, lx_p0.src, NTI33554449);  // let src = lx.src
```
"""

nbText: """
## The eight patterns

Each item is a piece of Nim, what it does in JavaScript, and what replaced it.

1. **A local name for a field.** `let src = lx.src` in a lexer copies the whole source each time
   the lexer reads a token. Now `template src: string = lx.src`, which writes `lx.src` wherever
   `src` is used (venn's lexer).
2. **A helper that captures a string.** A procedure written inside another is a *closure*: it
   can use the outer procedure's variables. Nim builds the closure when the outer procedure runs,
   and copies into it every parameter it uses. `pieceEnd`, called once for every word of a
   label, defined four such helpers on the label: a copy of the label for every word. They are
   now procedures that take the string as a parameter, behind templates of the old names
   (`text/label.nim`).
3. **The same with a list.** `sideEnds` of the layered layout, called for each side of each
   node, had a helper that captured the list of every edge's kind. It is a template now
   (`layout/layered.nim`).
4. **A tuple returned as a literal.** `return (rune, size)` copies the pair field by field, with
   a generic function that reads the type's description, and `codePointAt` does it once per
   character of every label. Now it sets `result.rune` and `result.size` (`js.nim`, and
   `ctrlAt` in `util/url.nim`).
5. **A list moved into a variable that exists.** `move` does not copy when it fills a new place,
   but `list = move frame.list` still copies, and so does `pop()`. The block parser keeps a stack
   of statement lists, one per open composite, and copied the whole list at every
   composite. The lists are a `ref object` now, which is copied as a pointer
   (`diagrams/block/parser.nim`).
6. **`a = a & b` on a growing list.** It builds a new list and copies it into `a`. A state named
   on 8,000 lines rebuilt its description 8,000 times. Now `a.add b`; and the description, which
   Pele slices again at each mention of a state, is sliced once at the end
   (`diagrams/state/graph.nim`).
7. **The fields of a value that is thrown away.** Merging a state into an existing one copied
   its label, description and styles, then dropped the state. They are moved now.
8. **A set of small numbers.** A `HashSet[int]` hashes each number with a 64-bit
   multiplication, which JavaScript, whose numbers are doubles, does by hand in pieces. The
   ancestors of an edge's ends, thousands deep in a flow of nested groups, were two such sets per
   edge. Now one array of marks, reused for every edge (`layout/compound.nim`).

The porting guide's note *Code that JavaScript runs slowly* lists all of them, with the four found
before, so that new code avoids them.
"""

nbCode:
  # Pattern 4, after the change: the code point at a byte, and its length, from fields set one by
  # one. The same answers as before for every kind of byte.
  for s in ["a", "é", "日", "😀", "\xff"]:
    let (rune, size) = codePointAt(s, 0)
    echo s.escape, " -> U+", rune.toHex(4), ", ", size, " bytes"

nbText: """
## Before and after

The same tests, each run alone on the same machine, with the JavaScript build of `main` before
this step and with this step's. The times are vitest's own, in milliseconds; they move by a tenth
or so from run to run.
"""

block:
  type Row = object
    test: string
    before, after: int
    faster: string
  var rows: seq[Row]
  for t in tests:
    let b = t["before"].getInt
    let a = t["after"].getInt
    rows.add Row(test: t["test"].getStr, before: b, after: a,
                 faster: &"{b / a:.1f}x" & (if t["afterStatus"].getStr == "passed": "" else: ", still over"))
  let table = tabella(rows, rownameCol = "test"):
    tabHeader "Pele's stress tests in the JavaScript build", "milliseconds, before and after this step"
    fmtInteger ["before", "after"]
    optCssTheme()
  nbTable table

nbText: &"""
The last two rows barely moved. In both, the time goes into hashing long strings: a class
diagram looks up thousands of class names in tables, and a gantt chart looks up each day of a
long task, formatted in a format of 25,000 tokens, in the set of excluded days. Nim hashes a
string by reading all of its bytes, with 32-bit arithmetic that JavaScript does slowly, where a
JavaScript engine computes the hash of a string once and keeps it. The fix is to key those tables
by something shorter, which changes code that the next step rewrites anyway.

## What is left, and why it waits

Pele's tests ran four files at a time, as CI runs them, and counted {now["speed"].getInt} misses,
against {before["speed"].getInt} before. A test near its limit can pass or miss depending on what
else the machine is doing, so the number moves by a few from run to run.

A pull request in review, [*Regular expressions, as Pele writes them*](https://github.com/pietroppeter/nimaki/pull/62), replaces about two hundred
hand-written scanners with Pele's own regular expressions, on a regex library written in Nim. It
rewrites the lexers of most types and makes drawing about 1.6 times slower for now, so measuring
the lexers before it lands would measure code about to go. This step fixed only what that
change does not touch, and goes on once it is on `main`: measure again, then the string hashes
and the lexers.
"""

nbText: """
## What this changes for the port

- The porting guide's *Code that JavaScript runs slowly* lists eight more patterns; new code avoids
  them, and a profile (`node --cpu-prof`, then the samples summed by caller) finds the next ones.
- The step *Pele's time bounds in the JavaScript build* stays open on the [roadmap](../../roadmap/):
  next, once the regular expressions are on `main`, the string hashes and the lexers.

## Sources

- Pele at the pin: the stress tests, for example
  [`tests/venn/stress.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/venn/stress.test.ts).
- Node's profiler: [`--cpu-prof`](https://nodejs.org/api/cli.html#--cpu-prof).
- The timings: `docs/devlog/data/faster_in_javascript/` (`timings.sh`, the tests in `tests.tsv`,
  the results in `timings.json`). The counts of Pele's tests: `docs/data/peletests.json`, from
  `nim r tools/peletests.nim`.
- The JavaScript that Nim writes was read in the bridge that `tools/peletests.nim` builds
  (`build/peletests/bridge.js`), with Nim 2.2.14.
"""

nbSave
