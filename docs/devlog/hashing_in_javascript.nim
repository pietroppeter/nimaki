## devlog: 14 Nov 2026 O | Hashing in JavaScript | The second round on the JavaScript build's speed, after the regular expressions: the tables that look up long names spent their time in a hash function built for 64-bit machines. Two lines of configuration, and a few more copies avoided, took the misses on Pele's time limits from 57 to 34.
## kind: port
import std/[strformat, strutils, json, sequtils, hashes]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site

nbInit
nb.usePost()

let timings = parseFile(docsDir / "devlog" / "data" / "hashing_in_javascript" / "timings.json")
let live = parseFile(docsDir / "data" / "peletests.json")["counts"]
let now = timings["countsAfter"]
let before = timings["countsBefore"]
let tests = timings["tests"].getElems
let passedNow = tests.countIt(it["afterStatus"].getStr == "passed")

nbText: &"""
## The findings, first

- **After the regular expressions, {before["speed"].getInt} of Pele's stress tests missed their
  time limit** in nimaki's JavaScript build, more than before it: the step that reads text with Pele's own
  regular expressions ([its post](../regular-expressions-as-pele-writes-them/)) is slower in
  JavaScript, as it said it would be. Nothing failed: every drawing was still the same.
- **The worst were not in the regular expressions but in hashing.** A table finds a key by
  turning it into a number, its *hash*. Nim's default hash for strings multiplies 64-bit
  integers, and JavaScript has none, so it does each multiplication by hand. Murmur, a hash Nim
  also ships, uses 32-bit arithmetic and is about 25 times faster there.
- **Two lines of configuration** pick murmur for strings, and the number itself for integers, in
  both builds ([decision 0017](../../decisions/#0017-one-fast-hash-for-both-builds)).
- **Three smaller changes** avoid more copies: the escaping of every text drawn, a state's
  styles, and turning numbers into text.
- **{now["speed"].getInt} tests are over the limit now**, down from {before["speed"].getInt}. The
  slowest left are inside the regular expression library, which copies its state at every
  character in JavaScript, and in two gantt and class cases that still take a few seconds.
- **The count moved again the same evening, for a good reason.** Pele's tests of `parse()` now run
  on nimaki too ([Pele's tests read the models](../pele-tests-read-the-models/)), and some of
  them are stress tests: with them, and this round, the count is {live["speed"].getInt}.
"""

nbText: """
## What a hash is

A `Table` is how a program finds `"Kitchen"` among ten thousand names without reading them all.
It keeps an array of slots. To store a name, it computes a number from its characters, the hash,
and puts the name in the slot that number points at. To find it again, it computes the same
number and looks in one slot, or a few. A good hash spreads names evenly over the slots; a fast
one does it with little arithmetic.

Here is a hash at work: the same name always gives the same number, and a name one letter apart
gives a very different one.
"""

nbCode:
  for name in ["Kitchen", "Kitchens", "kitchen"]:
    echo name.alignLeft(9), " -> ", hash(name)

nbText: """
Nim has two hashes for strings. The default, farmhash, reads 8 bytes at a time and multiplies
64-bit numbers. Murmur reads 4 bytes at a time and multiplies 32-bit numbers. On a 64-bit
processor both are fast. In JavaScript, every number is a 64-bit floating point value, which
holds integers exactly only up to 2^53, so Nim's JavaScript build splits each 64-bit
multiplication into pieces of 16 bits and puts them back together. In a quick measurement
during this step, hashing a string of 3,000 characters 2,000 times took about a second that way,
and a few hundredths of a second with murmur.

Pele's stress tests hash long strings often. A class diagram with 2,000 nested namespaces names
each one by its whole path (`a.b.c...`), thousands of characters long by the end; a gantt chart
looks up every day of a long task in a set of excluded days. JavaScript's own `Map` computes a
string's hash once and keeps it with the string. Nim's tables compute it at every lookup, so the
speed of the hash is the speed of the table.

## Two lines of configuration

Nim chooses the hash when it compiles, from two flags: `nimStringHash2` for murmur, and
`nimIntHash1` for integers that hash to themselves, which also skips 64-bit arithmetic. The flags
go in `nim.cfg`, the file Nim reads before it compiles anything in the repository.

The first attempt set them only for the JavaScript build, with a condition on the backend. It
did nothing: Nim 2.2 reads `nim.cfg` before it knows which backend it is compiling for, so the
condition is always false. A small test file that prints which hash it got showed it. The flags
now apply to both builds. That is also simpler to reason about: the C build and the JavaScript
build hash alike, so they keep a plain `Table` in the same order.

Does the order matter? It must not. Pele's `Map` and `Set` remember the order things went in,
and the port writes them as `OrderedTable` and `OrderedSet`, whose order does not depend on the
hash. The referee confirmed it: every case of the corpus is drawn identically, in both builds,
with the new hashes.

## Three more copies

The [first round](../faster-in-javascript/) found that Nim's JavaScript build copies strings and
lists where the C build does not. Three more turned up:

1. **Escaping text.** Every text drawn goes through `esc`, which checks each character for the
   few that XML forbids. It called a function that returned a pair, `(bad, size)`, once per
   character, and returning a pair copies it in JavaScript. Now the pair's fields are set one by
   one, and plain printable ASCII, most of any text, skips the check altogether
   (`svg/builder.nim`).
2. **A state's styles.** Each time a state is named again, its class styles were copied into a
   new list and back. They are now added in place. And `move`, which hands a list from one
   object to another without copying in C, still copies into an existing field in JavaScript: a
   new template, `moveField` of `js.nim`, hands the list over as JavaScript would
   (`diagrams/state/graph.nim`).
3. **Numbers as text.** `jsString` writes a number as JavaScript's `String(x)` does, for the SVG.
   The C build computes it by hand. The JavaScript build now just calls `String(x)`.
"""

nbText: """
## Before and after

The same tests, each run alone on the same machine, with the JavaScript build of `main` just
after the regular expressions, and with this round. The times are vitest's own, in milliseconds.
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
    tabHeader "Pele's stress tests in the JavaScript build", "milliseconds, before and after this round; now: against Pele's limit"
    fmtInteger ["before", "after"]
    optCssTheme()
  nbTable table

nbText: &"""
These are the slowest tests, so most of them are still over the limit: {passedNow} of
{tests.len} are within it now. Most are two to three times faster. One is not faster: a `classDef` of 5,000 declarations, which spends its time splitting and
resolving styles rather than looking them up.

## What is left

Profiles of the tests still over the limit point at three places:

- **The regular expression library.** It runs a small machine over the text, and in JavaScript
  it copies the machine's state at every character. The thread that brought the regular
  expressions already routed the simplest patterns around it; the rest would need a change in
  the library, which belongs to its author, or a different way to run the patterns in
  JavaScript.
- **Gantt date formats**, which compile a format of 25,000 tokens into a pattern.
- **Class styles**, split and resolved one declaration at a time.

## What this changes for the port

- `nim.cfg` picks murmur for strings and identity for integers, in both builds (decision 0017).
  A program that compiles nimaki with its own configuration keeps Nim's defaults: the same
  drawings, more slowly in JavaScript.
- `moveField` of `js.nim` hands a string or list from an object about to be dropped to another
  without a copy in JavaScript.
- The porting guide's note *Code that JavaScript runs slowly* says both.
- The step *Pele's time bounds in the JavaScript build* stays open on the
  [roadmap](../../roadmap/), with the three places above.

## Sources

- Nim's hashes: `lib/pure/hashes.nim` of Nim 2.2.14, read in the installed compiler, where
  `nimStringHash2` and `nimIntHash1` choose the hashes.
- The timings: `docs/devlog/data/hashing_in_javascript/` (`timings.sh`, the tests in `tests.tsv`,
  the results in `timings.json`). The counts of Pele's tests: `docs/data/peletests.json`, from
  `nim r tools/peletests.nim`.
- Pele at the pin: the stress tests, for example
  [`tests/class/stress.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/class/stress.test.ts).
"""

nbSave
