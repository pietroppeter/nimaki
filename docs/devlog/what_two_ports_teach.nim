## devlog: 15 Nov 2026 D | What two ports teach | Before porting Gleam, gleam-in-nim read how seven other projects moved between languages and drew nine lessons. nimaki has now ported Pele whole: the lessons held, one changed, and TypeScript brought look-alikes of its own.
## kind: research
import std/[algorithm, json, math, os, sequtils, strformat, strutils, tables, unicode]
import nimib
import ../blocks
from nimaki/js import jsRound, toFixed, jsString, jsMax, utf16Len

nbInit
nb.usePost()

const
  docs = currentSourcePath().parentDir.parentDir
  here = currentSourcePath().parentDir / "data" / "two_ports"
proc data(name: string): JsonNode = parseJson(readFile(docs / "data" / name))
proc thousands(n: int): string = insertSep($n, ',')

let
  difftest = data("difftest.json")
  jsRun = data("js.json")["difftest"]
  pele = data("peletests.json")
  totals = data("portmap.json")["totals"]
  fuzz = data("fuzz.json")["types"]
  corpus = difftest["cases"].getInt + difftest["diagrammari"]["cases"].getInt
  identical = difftest["identical"].getInt + difftest["diagrammari"]["identical"].getInt
  identicalJs = jsRun["identical"].getInt + jsRun["diagrammari"]["identical"].getInt
  fuzzed = toSeq(fuzz.pairs).mapIt(it[1]["cases"].getInt).foldl(a + b, 0)
  conformant = totals["conformant"]["files"].getInt
  conformantLines = totals["conformant"]["code"].getInt
  verified = totals["verified"]["files"].getInt
  draft = totals["draft"]["files"].getInt

var mutated = 0
for seed in 1 .. 7:
  mutated += parseJson(readFile(docs / "devlog" / "data" / "both_builds_every_file" /
                                &"mutate-js-{seed}.json"))["cases"].getInt

# The rows of the porting guide's idiom map: the table between its two headings.
let guide = readFile(docs / "porting.nim")
let mapText = guide[guide.find("## The idiom map") ..< guide.find("## Names")]
let idiomRows = mapText.splitLines.countIt(it.startsWith("| `") or it.startsWith("| a ") or
                                           it.startsWith("| an "))

# The posts, in the order they were written; venn was the last diagram type to be drawn as Pele does.
var posts: seq[(string, string, string)]
for path in walkFiles(docs / "devlog" / "*.nim"):
  let first = readFile(path).splitLines[0]
  if first.startsWith("## devlog: "):
    let parts = first["## devlog: ".len .. ^1].split(" | ")
    let date = parts[0][0 ..< parts[0].len - 2]
    posts.add (date.split(' ')[0].align(2, '0'), $parts[0][^1], parts[1])
posts.sort()
let lastType = posts.mapIt(it[2]).find("Circles that overlap")
let after = posts.len - 1 - lastType

let (peleFiles, peleLines) = block:
  let cells = readFile(here / "lines.txt").strip.split('\t')
  (parseInt(cells[0]), parseInt(cells[1]))

nbText: &"""
## The findings, first

On 12 November 2026, before porting a line, gleam-in-nim (Pietro's port of the Gleam compiler from
Rust to Nim) read how seven other projects had moved a program from one language to another, and
wrote down
[nine lessons](https://github.com/pietroppeter/gleam-in-nim/blob/main/docs/devlog/learning_from_rewrites.nim).
nimaki borrowed its shape the same day ([A stage for a port](../a-stage-for-a-port/)). Three days
later every diagram type of Pele is drawn by nimaki as Pele draws it, so the lessons can be
checked against what happened.

- **Eight of the nine held**, and each has a number behind it here: {identical} of {corpus} drawings
  the same bytes as Pele's, {thousands(pele["counts"]["failed"].getInt)} failures among Pele's own
  {thousands(pele["tests"].getInt)} tests, {conformant} files conformant.
- **One changed: "one writes, another doubts".** A second reading of each file by another session
  was the plan. It never happened: {verified} files are `verified`. The doubting is done by tools
  instead (an oracle, two fuzzers, Pele's tests), and
  [decision 0014](../../decisions/#0014-tests-and-fuzzing-make-a-file-conformant-without-a-second-reading)
  says so.
- **The look-alikes are different ones.** Rust and Nim disagree about equality, characters and
  overflow. TypeScript and Nim disagree about how long a text is, how a number is rounded and
  printed, what `max` does with a missing number, and in which order a table is read. Each is
  shown below, as Nim that runs on this page.
- **New with TypeScript: a second target.** Nim also compiles to JavaScript, and nimaki is checked
  there too. That build brought traps of its own, which a port that builds only for C never meets.
"""

nbText: """
## A word on the words

A *port* moves a program to another language and keeps it the same program: the same files, the
same functions, the same order of steps. A *rewrite* keeps only what the program does and builds
it anew. An *oracle* is the old program, run on the same input, whose answer the new one must give.
A *look-alike* is a line that reads the same in two languages and means something different in
each: the bugs that survive a careful port live there.

## Nine lessons, three days on

The first column is gleam-in-nim's lesson, the second what it became in nimaki.
"""

nbText: &"""
| Lesson | In nimaki |
| --- | --- |
| **Port, do not rewrite** | [Decision 0002](../../decisions/#0002-this-is-a-port-not-a-rewrite): one TypeScript file, one Nim file, the same names. {conformant} files, {thousands(conformantLines)} lines, are conformant; {draft} is a draft. |
| **Choose by shape** | Pele's TypeScript is written the way Nim is: plain objects, functions, a garbage collector, and few classes (the table below counts them). Where the shapes only look alike, below. |
| **An oracle beats a test you wrote** | Pele's npm package in Node is the oracle ([decision 0003](../../decisions/#0003-pele-at-the-pin-is-the-specification-and-its-npm-package-is-the-oracle)). {identical} of {corpus} drawings the same bytes in the C build, {identicalJs} in the JavaScript one; {thousands(fuzzed)} generated diagrams; {thousands(mutated)} questions with one odd character, asked of each build. |
| **The old test suite is the treasure** | Pele's {thousands(pele["tests"].getInt)} tests run on nimaki ([Pele's tests, on nimaki](../pele-tests-on-nimaki/)): {thousands(pele["counts"]["passed"].getInt)} pass, {pele["counts"]["failed"].getInt} fail; the rest call what a port does not have, or are listed. |
| **Write the guide first** | The [porting guide](../../porting/), read before each file. Its idiom map has {idiomRows} rows now, each added by the step that met the idiom. |
| **One writes, another doubts** | Changed: the tools doubt, not a second session. Below. |
| **Look-alikes bite** | The traps of the porting guide, and the section after this one. |
| **The second 90%** | The last diagram type was drawn as Pele does on 14 November ([Circles that overlap](../circles-that-overlap/)). {after} posts came after it, and most are the second 90%: speed in JavaScript, models in Pele's shape, odd characters. |
| **Speed does not excuse review** | One step, one pull request, one post, and the review mode on every page. |

## The lesson that changed

gleam-in-nim planned three states for a file, after the Bun port: *draft* (translated),
*verified* (read again, against the original, by a session that did not write it), *conformant*
(proven equal by tests). nimaki started with the same three.

What happened is that the tests caught up first. A file of Pele's is small and does one thing, and
the referee runs every case of the corpus through it in both builds; then a fuzzer makes thousands
more cases, and a second one changes one character in every case; then Pele's own tests run. A
second reading finds what a reader can see. These find what Pele *does*, on more inputs than a
reader can try. When they all agree, a second reading was not finding anything, and it cost a
session per file. So decision 0014 made `verified` optional, and no file has used it.

This is not a general rule. It holds because the oracle is perfect (Pele itself, at the pin) and
the inputs are plentiful: Pele's corpus, two fuzzers and Pele's tests reach every file. A port
whose oracle is reached by fewer inputs may still find a second reader the cheaper doubter.
"""

nbText: """
## Look-alikes between TypeScript and Nim

Each of these is a line that a translator writes without thinking, because it reads the same in
both languages. Each gave, or would give, a drawing that differs from Pele's. The fix is a helper
of nimaki's own (`src/nimaki/js.nim`), and the porting guide's idiom map says which.

**How long is a text?** JavaScript keeps a string as 16-bit pieces, *code units*; a character
outside the first 65,536 (most emoji) takes two. Nim keeps a string as bytes, in UTF-8, where
`é` takes two and an emoji four. A third answer counts characters.
"""

nbCode:
  let s = "é😀"
  echo s.len, " bytes"
  echo utf16Len(s), " code units (JavaScript)"
  echo s.runeLen, " characters"

nbText: """
Pele counts in code units wherever a number comes out: a width, a limit, the column of an error.
Nim's `len` is wrong in all three ways at once, and right on plain ASCII, which is why it hides.
[Decision 0011](../../decisions/#0011-strings-stay-utf-8-javascript-s-utf-16-is-counted-only-where-it-shows)
keeps nimaki's strings in UTF-8 and counts code units only where they show.

**Rounding a half.** JavaScript rounds a tie toward +∞, Nim away from zero; and `toFixed`, which
Pele uses to write every percentage of a pie, is not Nim's `formatFloat`.
"""

nbCode:
  echo "Nim: ", round(-2.5)
  echo "JavaScript: ", jsRound(-2.5)
  echo "Nim: ", formatFloat(12.5, ffDecimal, 0)
  echo "JavaScript: ", toFixed(12.5, 0)

nbText: """
**A number as text.** JavaScript writes the shortest text that reads back as the same number, with
no `.0`; Nim keeps the `.0`, and writes minus zero.
"""

nbCode:
  echo "Nim: ", $100.0, " ", $(-0.0)
  echo "JavaScript: ", jsString(100.0), " ", jsString(-0.0)

nbText: """
**The largest of two, when one is missing.** Pele uses NaN, *not a number*, for a value it does not
know yet. `Math.max` answers NaN when any argument is NaN; Nim's `max` quietly picks the other one.
"""

nbCode:
  echo "Nim: ", max(1.0, NaN)
  echo "JavaScript: ", jsMax(1.0, NaN)

nbText: """
**The order of a table.** A JavaScript `Map` gives its keys back in the order they were added, and
Pele draws in that order. Nim's `Table` gives them in the order of their hashes. Rust's `HashMap`
was the same trap the other way round: there, upstream sorted, and the port had to sort too.
"""

nbCode:
  var t = initTable[string, int]()
  var o = initOrderedTable[string, int]()
  for k in ["zeta", "alpha", "mid", "beta"]:
    t[k] = 1
    o[k] = 1
  echo "Table: ", toSeq(t.keys)
  echo "OrderedTable: ", toSeq(o.keys)

nbText: """
**Functions made in a loop.** In JavaScript, an arrow function made at each turn of a `for` loop
keeps that turn's value. In Nim, the functions share the loop's variable, and all of them see its
last value.
"""

nbCode:
  var fs: seq[proc (): int]
  for i in 0 .. 2:
    fs.add(proc (): int = i)
  echo fs.mapIt(it())  # JavaScript: [0, 1, 2]

nbText: """
**A copy of an object.** Pele writes `{ ...span, width: w }`, a copy with one field changed: it
spreads one object into another. In Nim, `var b = a` copies an `object`, but only shares a
`ref object`; a changed field then changes both.
"""

nbCode:
  type Span = ref object
    width: float
  let a = Span(width: 1)
  var b = a
  b.width = 2
  echo "a.width is ", a.width
  var c = Span()
  c[] = a[]          # the copy that the spread makes
  c.width = 3
  echo "a.width is still ", a.width

nbText: """
**A lower-case letter.** `toLowerCase` lowers every letter of Unicode; Nim's `toLowerAscii` only
the 26 of English. The Kelvin sign, `K`, is `k` to JavaScript.
"""

nbCode:
  const kelvin = "\u212A"
  echo "toLowerAscii: ", toLowerAscii(kelvin)
  echo "unicode.toLower: ", unicode.toLower(kelvin)

nbText: """
**Two names that are one.** Nim ignores case and underscores in a name, except for its first
letter: `fooBar`, `foo_bar` and `foobar` are one name. Pele has `BOLD` beside `Bold`, and a
`T.END` beside `T.end`; the port renames one of each pair (the porting guide's table of names).
"""

nbCode:
  const fooBar = 1
  echo foo_bar + foobar

nbText: """
Two more could not be shown in a line. A regular expression in JavaScript reads code units too, so
a `.` can take half of an emoji; nimaki's take the whole character, a difference listed on the
[Decisions page](../../decisions/) (*Half of an emoji*). And `Math.sin` in Node is V8's own port of
fdlibm, which differs from the C library in the last bit; nimaki ports V8's
([Circles that overlap](../circles-that-overlap/)).

## What Pele's TypeScript asks of Nim

gleam-in-nim counted the Rust idioms of Gleam's compiler to see whether Nim could say them. Here
is the same count for Pele: lines of code (comments, blank lines and tests left out) that hold each
TypeScript idiom, and where the port says it.
"""

block:
  var table = "| TypeScript | Lines | In nimaki |\n| --- | ---: | --- |\n"
  for line in lines(here / "idioms.tsv"):
    let cells = line.split('\t')
    table.add "| " & cells[0] & " | " & thousands(parseInt(cells[1])) & " | " & cells[2] & " |\n"
  nbText: table

nbText: &"""
The counts are of {thousands(peleLines)} lines of code in {peleFiles} files of Pele's `src/`, by
`docs/devlog/data/two_ports/count_idioms.nim`, which matches each idiom with a regular expression:
a line with two counts once, and a slash in a string can look like a regular expression to it, so
take the numbers as sizes, not exact counts.

The table reads in two halves. The second half (missing values, copies, types, functions) is
where Nim has the same shape, and the port is a translation: `interface` becomes `object`, an
arrow function a `proc`, `undefined` an `Option`. The difference that was left showed up in
the models, and [Five ways a model differs](../five-ways-a-model-differs/) counted it in five
kinds. The first half (lengths, codes, regular expressions, rounding, printing, `max`, `Map`) is
where the shapes look the same and are not: every one of those lines goes through a helper of
nimaki's, and every helper is checked against Node.

## A second target

The one thing gleam-in-nim's lessons could not prepare for: Nim compiles to JavaScript as well as
to C, and nimaki promises both
([decision 0013](../../decisions/#0013-nimaki-also-builds-with-nim-js)). That makes two more
kinds of trap, which the porting guide lists.

- **Code that only C can run.** A few ways of writing Nim compile to JavaScript and do something
  else there: an address chosen by an `if`, a `ref` used as a number, a product of two large
  integers that a JavaScript number cannot hold exactly.
- **Code that JavaScript runs slowly.** A Nim string compiled to JavaScript is a list of bytes, and
  copying it copies them all, where a JavaScript string is shared. Pele's stress tests found
  these ([Faster in JavaScript](../faster-in-javascript/)).
- **Text at the border.** A string handed from Nim to JavaScript is decoded from UTF-8, and half
  an emoji was lost there ([Both builds, every file](../both-builds-every-file/)).

All three are found the same way as the look-alikes: by running the referee and the fuzzers on
the JavaScript build too, which CI does on every pull request.
"""

nbNote """
- The porting guide's idiom map gains the rows this post found missing: a spread, a division
  that floors, an object compared or copied, a class.
- A count of Pele's idioms, in `docs/devlog/data/two_ports/`.
""", nkNim, "In the port"

nbNote """
- Every look-alike above runs when this page is built, with nimaki's helpers.
- gleam-in-nim read at its commit of 12 November 2026: its post on rewrites, its decisions and
  `AGENTS.md`. Its later posts were not read for this one.
- The other projects of gleam-in-nim's post (Go, TypeScript, Ladybird, Bun, fish, Roc, a C
  compiler) were not read again: their lessons are taken as that post states them.
""", nkDone, "Checked"

nbText: """
## What this changes for the port

- The porting guide's idiom map has the rows above; nothing else in the way of working changes.
- The lesson for the next port from TypeScript, whatever the language: the costly differences are
  in strings and numbers, not in types. Port the helpers for them first, and test them against
  Node before any file uses them, as nimaki's core step did ([First light](../first-light/)).

## Sources

- gleam-in-nim: [What other rewrites teach us](https://github.com/pietroppeter/gleam-in-nim/blob/main/docs/devlog/learning_from_rewrites.nim),
  12 November 2026, and its [decisions](https://github.com/pietroppeter/gleam-in-nim/tree/main/docs/decisions).
- How JavaScript keeps strings:
  [MDN, UTF-16 characters, Unicode code points, and grapheme clusters](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String#utf-16_characters_unicode_code_points_and_grapheme_clusters).
- `Math.round` and `Math.max`: [ECMAScript, Math.round](https://tc39.es/ecma262/#sec-math.round),
  [Math.max](https://tc39.es/ecma262/#sec-math.max).
- A `Map` keeps the order of insertion:
  [MDN, Map](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Map).
- Nim's names: [the manual, identifier equality](https://nim-lang.org/docs/manual.html#lexical-analysis-identifier-equality).
- The counts: [`count_idioms.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/devlog/data/two_ports/count_idioms.nim), run on Pele at the pin.
"""

nbSave
