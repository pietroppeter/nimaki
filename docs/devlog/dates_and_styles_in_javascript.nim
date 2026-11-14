## devlog: 14 Nov 2026 Q | Dates and styles in JavaScript | The third round on the JavaScript build's speed: gantt charts that read long date formats and class diagrams with thousands of style declarations are two to three times faster, and the regex library, measured, waits for a choice.
## kind: port
import std/[strformat, json, sequtils, hashes, math]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site
import nimaki/[js, jsregex]

nbInit
nb.usePost()

let timings = parseFile(docsDir / "devlog" / "data" / "dates_and_styles_in_javascript" / "timings.json")
let regex = parseFile(docsDir / "devlog" / "data" / "dates_and_styles_in_javascript" / "regex.json")
let before = timings["countsBefore"]
let after = timings["countsAfter"]
let tests = timings["tests"].getElems
let passedNow = tests.countIt(it["afterStatus"].getStr == "passed")
let failedBefore = tests.countIt(it["beforeStatus"].getStr != "passed")
let rx = regex["rows"].getElems
let walk = rx[0]
let lexer = rx[3]
let quad = regex["quadratic"]["rows"].getElems
func n0(x: float): string = $int(round(x))  ## a whole number, without the point `:.0f` leaves

nbText: &"""
## The findings, first

- **{failedBefore} of the {tests.len} gantt and class stress tests timed here missed Pele's time
  limit in the JavaScript build. Now all {passedNow} are within it**, two to three times faster.
  Over all of Pele's tests, the misses went from {before["speed"].getInt} to {after["speed"].getInt}.
  Every drawing is still identical to Pele's, in C and in JavaScript.
- **Gantt charts read dates by hand now, where it is cheap.** A long date format was read again
  for every day of every task, a regex was started for every digit of every date, and a date of
  25,000 tokens was sliced and rebuilt once per token.
- **Class styles look up each declaration once, with a quicker hash.** A new key type, `StrKey`,
  hashes a string where it lies instead of copying it first.
- **The regex library, measured: in JavaScript it is about
  {n0(walk["js"].getFloat / walk["c"].getFloat)} times slower than in C**, and JavaScript's own
  regular expressions are faster than both. A patch of its copies would make it about
  {walk["js"].getFloat / walk["patched"].getFloat:.1f} times faster. The library is not ours to
  change lightly, so the options are written down below, for Pietro to choose.
"""

nbText: """
## Two kinds of slow

The [first round](../faster-in-javascript/) and [the second](../hashing-in-javascript/) found
code that is fast in C and slow in JavaScript: copies Nim makes there and not in C, and hashes
that need 64-bit arithmetic. This round found both again, and one more kind: code that is slow in
both builds, because it does more work as the input grows than it needs to. Doubling the input
of such code makes it four times slower, not two: it takes time *in the square* of the input. C
hides it longer, because it is faster; Pele's stress tests are large enough to show it anyway.

### A date format of 25,000 tokens

A gantt chart says how its dates are written with a *format*, such as `YYYY-MM-DD`: four digits
of year, a dash, two of month, a dash, two of day. Mermaid reads dates with dayjs, a JavaScript
library, and Pele copies what dayjs does. To read a date, dayjs splits the format into tokens
(`YYYY`, `-`, `MM`...), and for each token it matches the date's text that is left, then drops
what it matched from that text.

One of Pele's stress tests writes a format of 25,000 tokens (`D D D ...`) and a date as long.
Three things in the port took time in the square of that:

1. **Splitting the format.** The tokens are found with a regular expression that has three
   *capture groups*, the parts in parentheses whose text a match also reports. The regex library
   keeps the groups of every match it has found until the walk over the text ends, and checks
   all of them again at each character, so a walk of many matches slows down as it goes. The
   port only reads the whole text of each token, so it now splits with the same pattern without
   the groups (the table below measures the difference).
2. **Slicing.** For each token, the port cut the rest of the date into a new string, as dayjs's
   `substring` does, and matched in it. In JavaScript `substring` is cheap: the engine keeps a
   reference to the original. In Nim it copies. The port now matches in place, from the offset
   where the slice would start.
3. **Rebuilding.** Dropping the matched text built a new string each time. It is deleted in
   place now.
"""

block:
  type Row = object
    tokens: int
    cWith, cWithout, jsWith, jsWithout: int
  var rows: seq[Row]
  for r in quad:
    rows.add Row(tokens: r["tokens"].getInt, cWith: r["cGroups"].getInt, cWithout: r["cNoGroups"].getInt,
                 jsWith: r["jsGroups"].getInt, jsWithout: r["jsNoGroups"].getInt)
  let table = tabella(rows, rownameCol = "tokens"):
    tabHeader "Splitting a format with the regex library", "milliseconds; with dayjs's three groups and without them, in C and in JavaScript"
    fmtInteger ["cWith", "cWithout", "jsWith", "jsWithout"]
    optCssTheme()
  nbTable table

nbText: """
Double the tokens, and with the groups the time goes up four times in C; without them, it
doubles. The two patterns find the same tokens:
"""

nbCode:
  let format = "YYYY-MM-DD [at] HH:mm"
  let withGroups = jsre"/(\[[^[]*\])|([-_:/.,()\s]+)|(A|a|Q|YYYY|YY?|ww?|MM?M?M?|Do|DD?|hh?|HH?|mm?|ss?|S{1,3}|z|ZZ?)/g"
  let withoutGroups = jsre"/\[[^[]*\]|[-_:/.,()\s]+|A|a|Q|YYYY|YY?|ww?|MM?M?M?|Do|DD?|hh?|HH?|mm?|ss?|S{1,3}|z|ZZ?/g"
  echo format.match(withGroups)
  echo format.match(withoutGroups) == format.match(withGroups)

nbText: """
### Every day of every task

Another stress test excludes some days (`excludes 01.01.2024`) from 500 tasks of 20,000 days,
with a format that carries 2,000 characters of literal text in brackets. To know whether a day is
excluded, the chart writes the day in its format and looks it up in the set of excluded days.
Pele limits how much of this work a chart may ask for; within that limit, each day did more than
it needed to in the port:

- the format was trimmed of spaces, and measured, for every day: now once, when it is set;
- the 2,000 characters in brackets were turned into a JavaScript string for every day, to compare
  them with each token of the format: a bracket is now recognized first, and kept as it is;
- the matches of the format were copied out of the cache that holds them, for every day;
- a small helper that captured the formatted day copied it each time, as closures do in nim js
  ([the first round](../faster-in-javascript/)): it is a template now;
- and the formatted day, 2,000 characters long, was hashed to look it up, which brings the next
  part.

### A hash that does not copy

The [second round](../hashing-in-javascript/) made Nim hash strings with murmur, which needs
only 32-bit arithmetic. The profiles of this round showed that it is still slow in JavaScript, for
two reasons that are not murmur's: Nim's JavaScript build copies the string before hashing it,
and it does each 32-bit multiplication in pieces, where JavaScript has `Math.imul` for it.

The port now has a key type for the tables that are looked up millions of times: `StrKey` of
`js.nim`, a string under another name. Its hash is murmur written in JavaScript, which reads the
bytes where they are, with `Math.imul`. It gives the same number as Nim's own hash, so a table
keyed by `StrKey` keeps its keys in the same order as one keyed by `string`, in both builds:
"""

nbCode:
  for name in ["Kitchen", "fill:#fff", "a classDef of 5,000 declarations"]:
    echo hash(StrKey(name)) == hash(name), "  ", hash(StrKey(name))

nbText: """
### Thousands of style declarations

A class diagram can give a class its look with `classDef` and `style`, each a list of
declarations such as `fill:#fff`. Pele resolves the styles of each class by going through its
declarations, keeping the last one of each property that has an effect. One stress test gives
800 classes a `classDef` of 5,000 declarations each, so this goes through four million
declarations. Pele remembers which declarations have an effect; the port asked that question
twice per declaration (*is it known?*, then *what is it?*), with two hashes. Now it asks once, and
the remembered answers and the kept properties are keyed by `StrKey`.

A second class test, 1,600 `classDef` lines, spent its time somewhere else: before any parsing,
Mermaid drops the last semicolon of a line that looks like a color (`style a fill:#f00;`), and
the port's search for that semicolon went back from each line to the start of the text, rather
than to the `#` it must come after.

### Digits, read by hand

Last, a chart of 8,000 tasks reads 8,000 dates. dayjs matches each digit token with a small
regular expression (`\d\d` for `MM`, `\d{4}` for `YYYY`). Starting a match in the regex library
costs a few microseconds in JavaScript, and these patterns are only digits. They are matched by
a loop now (`digitsFrom` in `diagrams/gantt/dates.nim`), checked against the regex on 18,000
random texts during this step. And the gantt lexer copied each of its keyword patterns as it
tried them, once per keyword: it reads them in place now.
"""

nbText: """
## Before and after

The same tests, each run alone on the same machine, with the JavaScript build of `main` after
the second round, and with this round. The times are vitest's own, in milliseconds.
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
    tabHeader "Gantt and class stress tests in the JavaScript build", "milliseconds, before and after this round; now: against Pele's limit"
    fmtInteger ["before", "after"]
    optCssTheme()
  nbTable table

nbText: &"""
The last row was already within its limit, and near it: it is safer now.

## The regex library, measured

nimaki reads text with Pele's own regular expressions, run by [nitely's
nim-regex](https://github.com/nitely/nim-regex), a regex library written in Nim
([decision 0016](../../decisions/#0016-regular-expressions-as-pele-writes-them-on-nim-regex)). It is fast in C.
In JavaScript, it builds a small object for each state of its machine at each character, and Nim's
JavaScript build copies such objects with a generic function that reads the type's description:
in a profile of the walk below, the copies take more than half of the time. A program of
this step (`rxbench.nim` in this post's data) runs the same patterns on 4,000 lines of text:
"""

block:
  type Row = object
    measured: string
    c, js, patched, native: string
  var rows: seq[Row]
  for r in rx:
    rows.add Row(measured: r["case"].getStr, c: &"""{r["c"].getFloat:.1f}""",
                 js: &"""{n0(r["js"].getFloat)}""", patched: &"""{n0(r["patched"].getFloat)}""",
                 native: (if r["native"].kind == JNull: "" else: &"""{r["native"].getFloat:.1f}"""))
  let table = tabella(rows, rownameCol = "measured"):
    tabHeader "The same patterns, four ways", "milliseconds: nim-regex in C, in JavaScript, in JavaScript with a patch of its copies, and JavaScript's own RegExp"
    optCssTheme()
  nbTable table

nbText: &"""
So in JavaScript the library is {n0(walk["js"].getFloat / walk["c"].getFloat)} times slower than in
C on a walk over the text, and {n0(lexer["js"].getFloat / lexer["c"].getFloat)} times on a lexer's
matches; JavaScript's own engine is faster than either. The patch (`pstate.patch`, beside this
post's data) sets the fields of the library's state one by one instead of building and copying
it: about {walk["js"].getFloat / walk["patched"].getFloat:.1f} times faster on a walk, little on a
lexer. It was tried on a scratch copy of the library and is not in the repository.

How much of the slow tests is this? Less than it seemed. Profiles of eight of the tests still over
their limit put between 0 and 40 percent of the drawing's time inside the library; the rest is
the port's own code, of the kinds above.
"""

nbNote """
Options for the regex library in the JavaScript build, for Pietro to choose; none is taken yet.

1. **Shortcuts in nimaki's wrapper** (`jsregex.nim`, nimaki's own code). It already runs some
   patterns without the library (a run of one class, plain text); more shapes could be added, and
   `match`, `test` and `split`, which do not read groups, could ask the library for none. Safe and
   gradual; each shortcut helps only its patterns.
2. **A patch kept in the vendored copy**, applied by `tools/setup.sh` on top of the pinned commit:
   the state copies (`pstate.patch`, about 1.8 times on a walk), then the groups kept for a whole
   walk. One more thing to carry each time the pin moves.
3. **Propose the same changes upstream**, in a post, as the project does for diagrammari: the
   library's author decides. It helps every user of nim-regex in JavaScript, and takes time.
4. **JavaScript's own RegExp in the JavaScript build.** The fastest, and the same engine that
   runs Pele; but nimaki's strings are UTF-8 and JavaScript's are UTF-16, so each match would
   convert the text or keep a converted copy, and the C build would keep nim-regex. The largest
   change.

A start that needs no decision on the others: 1 now, 3 in a post, and 2 only if the walks still
show up in the profiles after that.
""", nkQuestion, "What to do about the regex library"

nbText: """
## What this changes for the port

- `StrKey` of `js.nim`: the key of a table or set that is looked up very often. Its hash is the
  same number as `hash(string)`, computed without a copy in JavaScript.
- A `g` regex with groups, walked to its end, takes time in the square of its matches in the
  regex library: where only the whole text is read, the pattern goes without groups.
- The porting guide's note *Code that JavaScript runs slowly* says both.
- The step *Pele's time bounds in the JavaScript build* stays open on the
  [roadmap](../../roadmap/): the regex library waits for a choice among the options above, and
  the class namespaces and state transitions of the slowest tests left are the port's own code.

## Sources

- The timings: `docs/devlog/data/dates_and_styles_in_javascript/` (`timings.sh`, the tests in
  `tests.tsv`, the results in `timings.json`). The counts of Pele's tests:
  `docs/data/peletests.json`, from `nim r tools/peletests.nim`.
- The regex measurements: `rxbench.nim`, `native.js`, `pstate.patch` and `regex.json` in the same
  folder; nim-regex at the commit of `deps.lock`, read in `deps/regex/src/regex/nfatype.nim` and
  `nfafindall2.nim`.
- dayjs's parsing, as Pele copies it: `src/diagrams/gantt/dates.ts` of Pele at the pin, for example the
  stress cases in
  [`tests/gantt/stress.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/gantt/stress.test.ts).
- `Math.imul`: [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Math/imul).
"""

nbSave
