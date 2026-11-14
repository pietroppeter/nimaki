## devlog: 14 Nov 2026 L | Regular expressions, as Pele writes them | nimaki now reads text with Pele's own regular expressions, on nitely's pure Nim regex package, instead of two hundred hand-written scanners: what that took, what it costs, and why the drawings did not change by a single byte.
## kind: tooling
import std/[algorithm, json, os, strformat, strutils, tables]
import nimib
import tabelline, tabelline/nimib
import ../blocks
import nimaki/jsregex
import regex

nbInit
nb.usePost()

# Every number of this post comes from this file: the measures of the tree before (main) and after
# (the branch of this post), taken in one sandbox on the day, as its `note` says.
const dataDir = currentSourcePath.parentDir / "data" / "regular_expressions"
let data = parseJson(readFile(dataDir / "numbers.json"))

proc thousands(n: int): string = insertSep($n, ',')
proc ms(x: float): string = formatFloat(x, ffDecimal, 1)
proc mb(bytes: int): string = formatFloat(bytes / 1_000_000, ffDecimal, 1)
proc times(a, b: float): string = formatFloat(b / a, ffDecimal, 1)

let
  before = data["lines"]["before"]
  after = data["lines"]["after"]
  bench = data["bench"]
  totalBefore = bench["before"]["total_ms"].getFloat
  totalAfter = bench["after"]["total_ms"].getFloat
  first = data["firstMeasure"]
  dt = data["difftest"]
  fz = data["fuzz"]
  tj = data["test_jsregex"]
  cs = data["compile_s"]
  by = data["bytes"]
  commit = data["commit"].getStr
  shortCommit = commit[0 .. 6]
  linesCut = before["nim"].getInt - after["nim"].getInt
  helpersBefore = before["helpers"].getInt
  helpersAfter = after["helpers"].getInt
var benchCases = 0
for kind, b in bench["after"]["types"]: benchCases += b["cases"].getInt

nbText: &"""
## The findings, first

- **Pele's regular expressions, as Pele writes them.** Until today the port answered each of
  Pele's regular expressions with a function written by hand. Now it writes the expression
  itself, `jsre"/title([\t ][^\n\r]*|)/"`, and a new module, `src/nimaki/jsregex.nim`, runs it on
  [nitely's `regex` package](https://github.com/nitely/nim-regex), a regex engine written in
  pure Nim. {data["uses"].getInt} places in `src/` now hold a regular expression.
- **The drawings did not change.** The referee finds **{dt["identical"].getInt.thousands} of
  {dt["cases"].getInt.thousands}** cases identical to Pele, byte for byte, in the C build and
  {dt["js_identical"].getInt.thousands} in the JavaScript one; the fuzzers, **{fz["identical"].getInt.thousands}**
  generated cases over {fz["types"].getInt} types, all identical.
- **Less code.** The hand-written scanners that quoted a regex went from **{helpersBefore}** to
  **{helpersAfter}**, and `src/` from {before["nim"].getInt.thousands} lines of code to
  {after["nim"].getInt.thousands}: {linesCut.thousands} fewer, though the new module adds
  {data["wrapperLines"].getInt}.
- **Slower, and that is the price.** Drawing the whole corpus takes **{ms(totalAfter)} ms**
  instead of {ms(totalBefore)} ms, {times(totalBefore, totalAfter)} times as long; it was
  {times(first["before_ms"].getFloat, first["after_ms"].getFloat)} times before the fixes told
  below. The programs are a little larger and take a little longer to build.
- **Same syntax, not the same meaning.** nim-regex reads `\s`, `\w`, `.` and the `i` flag in its
  own way. The module translates every pattern into one that means what JavaScript means, and a
  test runs Pele's {tj["regexes"].getInt} patterns against Node on {tj["strings"].getInt.thousands} strings.

## What a regular expression is

A diagram starts as text, and the first job of a renderer is to find the pieces in it: the word
`pie`, a title, a number. A **regular expression** (a *regex*) is a small language for
describing such a piece. `\d` is a digit, `+` means one or more of what comes before, `[\t ]` is
a tab or a space, `(...)` keeps what it matched as a *group*, `|` means or. So `/\d+/` describes
a run of digits, and `/title([\t ][^\n\r]*|)/` the word `title`, then either a blank and the rest
of the line (`[^\n\r]*`, anything but a line end, as many as there are) or nothing.

A regex *engine* takes the pattern and a text and finds where the pattern matches. JavaScript has
one built in, and Pele uses it about five hundred times. Here is one of them running in Nim, on
this page:
"""

nbCode:
  let title = jsre"/title([\t ][^\n\r]*|)/"
  let m = title.exec("pie title Pets adopted by volunteers")
  echo m.found, ", at byte ", m.index, ": ", m[1]

nbText: """
The letters after the last `/` are *flags*. `g` (global) finds every match, one after the other.
`y` (sticky) matches only exactly where it is told to start, which is what a **lexer** needs: the
part of a renderer that walks the text from left to right and asks, at each position, "which
kind of token starts *here*?" Pele's pie lexer asks it with this number pattern:
"""

nbCode:
  let number = jsre"/(?:-?[0-9]+\.[0-9]+(?!\.))|(?:-?(0|[1-9][0-9]*)(?!\.))/y"
  echo number.matchEnd("  42.5 apples", 2)   # a number starts at 2 and ends at 6
  echo number.matchEnd("  42.5 apples", 0)   # nothing starts at 0: -1
  echo "a\n   b\n\tc".replace(jsre"/\n\s+/g", " | ")

nbText: """
`(?!\.)` is a *lookahead*: "and no dot follows". The last line is the most common regex in
Pele's diagrams, `/\n\s+/g`, which takes the indent off the lines of an accessible description.

## How the port read text until today

When the port began, the porting guide asked for a hand-written function instead of each regex,
with the pattern it answers as in a comment. There were good reasons. Nim's standard `std/re`
calls PCRE, a C library that must be installed where the program runs, and PCRE does not mean
what JavaScript means by `\s` or by a sticky match. No other engine had been looked at, and
taking a dependency needed a decision record that nobody had written. So a pattern like
`/[\t ]*accTitle[\t ]*:/y` became a loop:
"""

nbCode:
  func accTitleAt(src: string, p: int): int =
    ## /[\t ]*accTitle[\t ]*:/y: where the match ends, or -1
    var i = p
    while i < src.len and src[i] in {'\t', ' '}: inc i
    if not src.continuesWith("accTitle", i): return -1
    i += 8
    while i < src.len and src[i] in {'\t', ' '}: inc i
    if i < src.len and src[i] == ':': i + 1 else: -1

  let sticky = jsre"/[\t ]*accTitle[\t ]*:/y"
  for text in ["accTitle: Pets", "  accTitle :x", "accTitles: no"]:
    echo accTitleAt(text, 0), " ", sticky.matchEnd(text, 0)

nbText: &"""
The two answer the same, and the loop is fast. But the loop is ten lines where Pele has one, it
must be read closely to see that it is right, and the same pattern was written again in every
file that needed it. By this morning the port held **{helpersBefore}** such functions for
**{before["regexes"].getInt}** different patterns (counted by `tools/census.nim`), and
`/\n\s+/g` alone was written by hand in 23 files. The post
[*The shape of the port*](../the-shape-of-the-port/) proposed gathering them in one shared
module. Pietro asked for something else: use the pure Nim regex package, "a dependency, but a
good one". [Decision 0016](../../decisions/#0016-regular-expressions-as-pele-writes-them-on-nim-regex)
records it.

## Same syntax, another meaning

nimaki's renderer had needed only Nim's standard library. nitely's `regex` (MIT, with its Unicode
tables in `unicodedb`, by the same author) is written in Nim, so it needs nothing installed,
compiles to JavaScript too, and matches in time proportional to the text, never exponential. Its
syntax is almost JavaScript's. Its meaning is not:
"""

nbCode:
  # U+0085 is a line break in Unicode; JavaScript's \s does not count it.
  echo "\u0085".contains(re2"\s"), " ", jsre"/\s/".test("\u0085")
  # U+FEFF, the byte order mark, is white space to JavaScript, not to the package.
  echo "﻿".contains(re2"\s"), " ", jsre"/\s/".test("﻿")
  # In JavaScript . stops at \r; in the package it does not.
  echo "\r".contains(re2"."), " ", jsre"/./".test("\r")

nbText: """
The first answer of each line is the package's, the second JavaScript's, through nimaki's module.
The list of differences found by test is longer: `\w`, `\d` and `\b` are Unicode in the package
and ASCII in JavaScript; the `i` flag makes `ſ` (a long s) equal to `s` and the Kelvin sign equal
to `k`, which JavaScript does without the `u` flag; a repeat over 100, `x{1,200}`, is refused;
and `[^]`, JavaScript's "any character", is not understood.

So `jsregex.nim` does not hand the pattern over as it is. It **translates** it: each class is
spelled out as the ranges of code points JavaScript means, ASCII letters are paired under `i`,
`^`, `$` and `.` get JavaScript's line ends, a long repeat is cut into pieces of 100. The
translation of a literal happens when the program is compiled, and a pattern it cannot
translate faithfully stops the build. Here is what the engine gets for a four-character pattern:
"""

nbCode:
  echo jsre"/\s+$/".translated

nbText: &"""
A compiled regex is large, so the program carries only the translated text and compiles each
pattern the first time it is used. Compiling all of them up front made the build 29 seconds
slower and the JavaScript a megabyte larger.

## How it was checked

Three referees, each from a different side:

- **The regex test.** `tests/test_jsregex.nim` takes each of Pele's {tj["literals"].getInt} regex
  literals and {tj["built"].getInt} patterns the port builds from pieces, makes strings from the
  pattern's own characters and from the ones where engines disagree (spaces beyond ASCII, letters
  with two cases, line ends, an emoji), and runs `exec`, `replace`, `split` and every match of a
  `g` regex in Node and in Nim: {tj["strings"].getInt.thousands} strings, no difference. On
  {tj["halfEmoji"].getInt} of them JavaScript returns half of an emoji, which a UTF-8 string cannot
  hold; those are left out and listed in the divergences.
- **The referee.** `tools/difftest.nim` draws the {dt["cases"].getInt.thousands} cases of the corpus
  ({dt["diagrammari"].getInt} of them from diagrammari) with Pele in Node and with nimaki, in its C
  build and in its JavaScript build, and compares the SVG byte for byte: all identical, after every
  type was converted, and again at the end.
- **The fuzzers.** `tools/fuzz.nim` writes new diagrams for each type, odd ones included, and
  draws them both ways: {fz["casesPerType"].getInt.thousands} for each of {fz["types"].getInt}
  types, all identical.

## What it costs
"""

block:
  type Row = object
    what, before, after: string
  let rows = @[
    Row(what: "lines of code in src/", before: before["nim"].getInt.thousands, after: after["nim"].getInt.thousands),
    Row(what: "scanners written by hand for a regex", before: $helpersBefore, after: $helpersAfter),
    Row(what: "drawing the corpus (ms)", before: ms(totalBefore), after: ms(totalAfter)),
    Row(what: "compiling the C build (s)", before: ms(cs["before_c"].getFloat), after: ms(cs["after_c"].getFloat)),
    Row(what: "compiling the JavaScript build (s)", before: ms(cs["before_js"].getFloat), after: ms(cs["after_js"].getFloat)),
    Row(what: "the C program (MB)", before: mb(by["before_c"].getInt), after: mb(by["after_c"].getInt)),
    Row(what: "the JavaScript (MB)", before: mb(by["before_js"].getInt), after: mb(by["after_js"].getInt)),
    Row(what: "the JavaScript, gzipped (MB)", before: mb(by["before_js_gzip"].getInt), after: mb(by["after_js_gzip"].getInt)),
  ]
  let t = tabella(rows, rownameCol = "what"):
    tabHeader "Before and after", "main at " & data["base"].getStr[0 .. 6] & " and the branch at " & shortCommit
    colsLabel {"what": ""}
    optCssTheme()
  nbTable t

nbText: &"""
The bench (`tools/bench.nim`) draws each of the {bench["before"]["types"].len} types' cases five
times and keeps the fastest round; the numbers are the fastest of four such runs, the two trees
taking turns on the same machine. Compile times are clean builds, the faster of two.

The first measure was worse: {ms(first["after_ms"].getFloat)} ms against {ms(first["before_ms"].getFloat)}.
A profiler (valgrind's callgrind) showed where the time went, and two causes were in the new module,
not in the patterns:

- **A search tries every position.** To find `/^\s*flowchart/` in a text, the engine starts its
  automaton at position 0, then 1, then 2, to the end. With `^` and no `m` flag a match can only
  start at 0, so the module now tries 0 alone. Detecting the diagram type runs 37 such patterns on
  every text.
- **A pattern that starts with plain text.** `/var\(--_(r|tw|hw|w)\)/g` runs over the whole SVG
  of a drawing. Every match starts with `var(--_`, so the module now finds that text with an
  ordinary string search, and runs the engine only where it is.

A third was one pattern: `/^[\w\s#%.,+\-/()]{{1,200}}$/` checks a colour of a theme. The package
spells a bounded repeat out, one state for each of the 200 turns, and one test took
{data["paletteTest_us"]["bounded"].getInt} µs where the same class with `+` takes
{data["paletteTest_us"]["unbounded"].getInt}. The port now checks the class with `+` and the
length apart.

What is left is the price of an engine: a regex tried at one position costs a few thousand
machine instructions, a hand-written test a few dozen. Each type, before and after:
"""

block:
  type Row = object
    kind: string
    cases: int
    before, after, ratio: string
  var rows: seq[Row]
  for kind, b in bench["before"]["types"]:
    let a = bench["after"]["types"][kind]
    rows.add Row(kind: kind, cases: b["cases"].getInt, before: ms(b["ms"].getFloat), after: ms(a["ms"].getFloat),
                 ratio: times(b["ms"].getFloat, a["ms"].getFloat))
  rows.sort(proc (x, y: Row): int = cmp(parseFloat(y.ratio), parseFloat(x.ratio)))
  nbFold "Show the time of each type":
    let t = tabella(rows, rownameCol = "kind"):
      tabHeader "Drawing each type's cases, in ms", "fastest round of build/bench, before and after"
      colsLabel {"kind": "type", "ratio": "times"}
      optCssTheme()
    nbTable t

nbText: &"""
The types that read their text with a table of tokens (radar, gantt, c4, kanban) pay most, as
their lexer tries pattern after pattern at each position. Still, {ms(totalAfter)} ms for the
bench's {benchCases.thousands} diagrams is under a tenth of a millisecond a diagram.

## What is still written by hand

A scanner stays where a regex cannot be faithful, and says why in its comment:

- **Half a character.** JavaScript strings are UTF-16, so a lone half of an emoji (a *surrogate*)
  can be in one, and Pele's `esc`, its URL checks and sankey's check of names look for one. In the
  port's UTF-8 strings that half is a byte that is not UTF-8, which no regex over characters sees.
- **Counting in UTF-16.** `/\W/g` in use case ids turns an emoji into two `_`, one per code unit;
  in a treemap format, `.` takes half an emoji as the fill character. A scanner counts the same way.
- **Pele's own scanners.** Where Pele itself writes a function beside a pattern (a token that keeps
  state, a run of digits read once), the port keeps the function, as Pele does.
- **One character.** A regex applied to one character, `/\s/.test(c)`, stays a test on the character.

## A bug the JavaScript build found

The gantt lexer kept its keywords in small constant arrays, one per first letter, picked by a
`case` expression. In C that works. In the JavaScript build, a `case` expression whose branch is a
constant array made a `seq` (`of 'a': @KEYWORDS_A`) gives `undefined`, and every gantt chart
stopped with `Cannot read properties of undefined (reading 'length')`. It is the same Nim 2.2
behaviour the post [*nimaki in JavaScript*](../nimaki-in-javascript/) found for an `if`
expression. The keywords are now one array, as in Pele, and the porting guide lists the case.

## What this changes for the port

- A file is ported with its regexes copied as they are: `jsre"/.../flags"` for a literal,
  `jsre(pattern, flags)` for one built from constants, `newRegExp` for `new RegExp`. The porting
  guide's idiom map says how `exec`, `lastIndex`, `replace`, `split` and `matchAll` are written.
- A new release of Pele that changes a pattern is followed by copying the pattern, and the test
  against Node checks the new one.
- The renderer has one dependency, pinned in `deps.lock`. `sh tools/setup.sh` fetches it.
- Drawing is {times(totalBefore, totalAfter)} times slower. If speed matters later (a browser
  page drawing as one types), the next places to look are the lexers made of token tables and the
  label layout, which run the most patterns.
- The shared-scanners step on the roadmap is closed by this one: the scanners that stay are few,
  and each is in the file whose behaviour it ports.

## Sources

- nimaki at [`{shortCommit}`](https://github.com/pietroppeter/nimaki/tree/{commit}):
  [`src/nimaki/jsregex.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/jsregex.nim),
  [`tests/test_jsregex.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/tests/test_jsregex.nim),
  [`corpus/regexes.json`](https://github.com/pietroppeter/nimaki/blob/{commit}/corpus/regexes.json)
  (Pele's regexes, listed by `tools/pele_regexes.mjs`); the numbers of this post,
  [`regular_expressions/numbers.json`](https://github.com/pietroppeter/nimaki/tree/main/docs/devlog/data/regular_expressions).
- [Decision 0016](../../decisions/#0016-regular-expressions-as-pele-writes-them-on-nim-regex),
  and the divergences it brings, on the same page.
- [nim-regex](https://github.com/nitely/nim-regex) and
  [nim-unicodedb](https://github.com/nitely/nim-unicodedb), by nitely, at the commits of `deps.lock`.
- JavaScript's regular expressions: the [ECMAScript specification](https://tc39.es/ecma262/#sec-regexp-regular-expression-objects)
  and [MDN's guide](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_expressions).
- Pele at the pin: [`src/diagrams/common/tokens.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/tokens.ts),
  [`src/svg/palette.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/svg/palette.ts),
  [`src/svg/root.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/svg/root.ts),
  [`src/detect.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/detect.ts).
"""

nbSave
