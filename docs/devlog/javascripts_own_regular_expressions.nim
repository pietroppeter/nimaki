## devlog: 15 Nov 2026 B | JavaScript's own regular expressions | The JavaScript build now matches Pele's regular expressions with JavaScript's own engine, the one Pele runs on: a walk over a text is fifty times faster, and the build is smaller.
## kind: port
import std/[strformat, strutils, json, sequtils, math, algorithm, re]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site
import nimaki/js

nbInit
nb.usePost()

let timings = parseFile(docsDir / "devlog" / "data" / "javascripts_own_regular_expressions" / "timings.json")
let before = timings["countsBefore"]
let after = timings["countsAfter"]
let tests = timings["tests"].getElems
let bench = timings["rxbench"]["rows"].getElems
let bytes = timings["bridgeBytes"]
func n0(x: float): string = $int(round(x))  ## a whole number, without the point `:.0f` leaves
let walk = bench[0]
let lexer = bench[3]
let leftList = block:
  var over: seq[(float, string)]
  for t in parseFile(docsDir / "data" / "peletests.json")["notPassed"].getElems:
    if t["kind"].getStr != "speed": continue
    var m: array[2, string]
    if t["message"].getStr.find(re"expected ([0-9.]+) to be less than ([0-9]+)", m) >= 0:
      let ms = parseFloat(m[0])
      let limit = parseFloat(m[1])
      over.add (ms / limit, "- " & t["test"].getStr & ": " & n0(ms) & " ms against " & n0(limit))
  over.sort(proc (a, b: (float, string)): int = cmp(b[0], a[0]))
  over[0 ..< min(6, over.len)].mapIt(it[1]).join("\n")

nbText: &"""
## The findings, first

- **The JavaScript build runs Pele's patterns on JavaScript's own `RegExp`** now, the engine Pele
  runs on, as Pietro chose after [the last round](../dates-and-styles-in-javascript/)
  ([decision 0019](../../decisions/#0019-javascript-s-own-regexp-in-the-javascript-build)). The C
  build keeps nim-regex.
- **A walk over a text with a regular expression is {n0(walk["before"].getFloat / walk["after"].getFloat)}
  times faster** in the JavaScript build, and a lexer's matches
  {n0(lexer["before"].getFloat / lexer["after"].getFloat)} times.
- **Over all of Pele's tests, the misses on its time limits went from {before["speed"].getInt}, after
  the last round, to {after["speed"].getInt}.** Every drawing is still the same as Pele's, in both builds.
- **The JavaScript build is {n0((bytes["before"].getFloat - bytes["after"].getFloat) / 1024)} KB smaller**:
  it no longer carries the regex engine.
- **The hard part is the text.** nimaki's strings are UTF-8, JavaScript's are UTF-16. Each text
  is converted once and kept, with a table between the two ways of counting positions.
"""

nbText: """
## Two engines, one set of patterns

A *regular expression* is a small program that describes text: `\d{4}` is four digits,
`[ \t]+` a run of spaces and tabs. Pele writes about five hundred of them. An *engine* runs them.
Until now, both builds of nimaki ran them on [nim-regex](https://github.com/nitely/nim-regex),
written in Nim, after translating each pattern into its syntax
([Regular expressions, as Pele writes them](../regular-expressions-as-pele-writes-them/)).

In C, nim-regex is fast. In JavaScript, Nim's compiler turns it into code that copies the
engine's state at every character, and it was 30 to 50 times slower than in C, while
JavaScript's own engine was faster than both. The [last post](../dates-and-styles-in-javascript/)
measured this and listed four ways out. Pietro picked the one with the most effect: in the
JavaScript build, hand each pattern to JavaScript itself.

The change sits in one file. Every match in nimaki goes through `jsregex.nim`, so the rest of
the port did not change at all. Its shortcuts still run first: a pattern that is one class
repeated (`\s+`), plain text, a pattern that starts with fixed text. Only what used to go to
nim-regex now goes to `RegExp`, made once from Pele's own pattern and flags, as written.

## UTF-8 and UTF-16

The same text can be stored in two ways. nimaki stores it as UTF-8, as Nim does: one byte for an
English letter, two for `é`, three for `日`, four for an emoji. JavaScript stores it as UTF-16:
one *unit* for each of the first three, two units for the emoji. So a position in a text, which
nimaki counts in bytes and JavaScript in units, is a different number as soon as a character is
not plain ASCII:
"""

nbCode:
  let text = "café 日本 😀!"
  echo "bytes: ", text.len, "   UTF-16 units: ", utf16Len(text)
  # where the "!" is, counted both ways
  echo "byte ", text.find('!'), " is unit ", utf16Len(text, 0, text.find('!'))

nbText: """
JavaScript's `RegExp` reads only JavaScript strings, so `jsregex.nim` does three things:

1. **It converts the text once.** The bytes become a JavaScript string the first time a text is
   matched, and the last four texts are kept. A lexer matches the same source thousands of times,
   one token after the other, so it converts it once; converting at every match would have made
   it slower than before.
2. **It translates positions with a table.** For a text that is all ASCII, most diagrams, a
   byte and a unit are the same number and there is nothing to do. For any other text, the same
   pass that converts it also writes, for each byte, its unit, and for each unit, its byte. Where
   to start a match, and where it starts and ends, are looked up there.
3. **It converts the matched text back.** The text of a match and of its groups becomes UTF-8
   again, which costs as much as the match is long.

There is a gain in correctness too. The translation for nim-regex had a few known differences
from JavaScript: a `.` takes a whole emoji where JavaScript takes half of it, and a group inside
a repeated group keeps an old value where JavaScript forgets it. The JavaScript build now runs the
very engine Pele runs, so those can only remain in the C build. The referee, the fuzzers and
Pele's own tests compare both builds with Pele, as before.
"""

nbText: """
## Before and after

The regex benchmark of the last post, in the JavaScript build, before and after:
"""

block:
  type Row = object
    measured: string
    before, after: string
    faster: string
  var rows: seq[Row]
  for r in bench:
    let b = r["before"].getFloat
    let a = r["after"].getFloat
    rows.add Row(measured: r["case"].getStr, before: n0(b), after: &"{a:.1f}", faster: n0(b / a) & "x")
  let table = tabella(rows, rownameCol = "measured"):
    tabHeader "Matching 4,000 lines in the JavaScript build", "milliseconds: nim-regex, then JavaScript's own RegExp"
    optCssTheme()
  nbTable table

nbText: """
And Pele's tests whose profiles showed the most time in the regex library, each run alone on the
same machine, with the JavaScript build of `main` before this step and with it:
"""

block:
  type Row = object
    test: string
    before, after: int
    faster, now: string
  var rows: seq[Row]
  for t in tests:
    let b = t["before"].getInt
    let a = t["after"].getInt
    rows.add Row(test: t["test"].getStr, before: b, after: a, faster: &"{b / a:.1f}x",
                 now: (if t["afterStatus"].getStr == "passed": "within" else: "over"))
  let table = tabella(rows, rownameCol = "test"):
    tabHeader "Pele's tests that use regular expressions most", "milliseconds, before and after this step; now: against Pele's limit"
    fmtInteger ["before", "after"]
    optCssTheme()
  nbTable table

nbText: &"""
Most are faster by a little: the regular expressions were one cost among several in them, as
the profiles of the last post said. A box-drawing tree of 10,000 rows, which matches every line
against a few patterns, is three times faster.

The last row is not about regular expressions. A use case diagram whose `class` statement gives
4,000 classes to each of 2,500 elements adds ten million names to sets, as Pele does. In the
JavaScript build each name was copied and hashed slowly, so the test took twelve seconds. The set
is now sized once and keyed by `StrKey` ([the last round](../dates-and-styles-in-javascript/)),
which brings it under five. It is still over its limit: Pele builds the same sets, with
JavaScript's fast ones.

## What is left

{after["speed"].getInt} of Pele's tests are still over their limit in the JavaScript build. The furthest
over, from `docs/data/peletests.json`:

{leftList}

The two profiled here, class namespaces and the use case statement above, spend their time in
nimaki's own code, not in regular expressions; the next ones are outlines nested thousands deep.
"""

nbText: """
## What this changes for the port

- In the JavaScript build, a match runs on JavaScript's `RegExp`
  ([decision 0019](../../decisions/#0019-javascript-s-own-regexp-in-the-javascript-build)); the
  C build runs nim-regex. A pattern is still translated in both, so a `jsre` literal that nim-regex
  cannot run stops the build, as before.
- A text being matched must not be changed in place: the JavaScript build keeps its converted
  copy, found again by being the same array of the same length.
- The step *JavaScript's own RegExp in the JavaScript build* is done on the
  [roadmap](../../roadmap/); *Pele's time bounds in the JavaScript build* stays open for the tests
  above. The changes to nim-regex that would help it in JavaScript are proposed to its author in
  the next post, [A proposal for nim-regex](../a-proposal-for-nim-regex/).

## Sources

- `src/nimaki/jsregex.nim`, section *The JavaScript build*.
- The timings: `docs/devlog/data/javascripts_own_regular_expressions/` (`timings.sh`, the tests in
  `tests.tsv`, the results in `timings.json`). The counts of Pele's tests:
  `docs/data/peletests.json`, from `nim r tools/peletests.nim`.
- JavaScript's `RegExp`, sticky and global flags and `lastIndex`:
  [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/RegExp).
- UTF-16 in JavaScript strings:
  [MDN, String](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String#utf-16_characters_unicode_code_points_and_grapheme_clusters).
"""

nbSave
