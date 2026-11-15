## devlog: 14 Nov 2026 S | One odd character | The corpus with one odd character slipped into each case now gives Pele's answers every time: nimaki writes a host name in any script as a URL does, and four places that counted bytes count as JavaScript does.
## kind: port
import std/[json, math, os, osproc, options, sequtils, strformat, strutils, tables, unicode]
import nimib
import tabelline, tabelline/nimib
import ../blocks
import nimaki
import nimaki/util/[url, idna, idna_data]
from nimaki/jsdate import parseDate

nbInit
nb.usePost()

# The runs this post counts: the seven of the article that found the differences (their texts),
# the same texts again on this code, and seven new runs, seeds 1 to 7, on this code.
const here = currentSourcePath.parentDir / "data"
var before, again, after: seq[JsonNode]
for seed in 1 .. 7:
  before.add parseJson(readFile(here / "how_nimaki_reads_text" / &"mutate-{seed}.json"))
  again.add parseJson(readFile(here / "one_odd_character" / &"again-{seed}.json"))
  after.add parseJson(readFile(here / "one_odd_character" / &"mutate-{seed}.json"))

proc thousands(n: int): string = insertSep($n, ',')
proc total(runs: seq[JsonNode], key: string): int = runs.mapIt(it[key].getInt).foldl(a + b, 0)

let
  beforeCases = total(before, "cases")
  beforeDifferent = total(before, "different")
  againIdentical = total(again, "identical")
  afterCases = total(after, "cases")
  afterDifferent = total(after, "different")
var hostDifferences = 0
for run in before:
  for d in run["differences"]:
    if "href" in d["detail"].getStr: inc hostDifferences
# Figures of runs made while writing: the test of hosts, and the first port (from tr46).
let notes = parseJson(readFile(here / "one_odd_character" / "notes.json"))
# The size of the JavaScript build, before this step (main when it started) and now.
let jsBefore = parseJson(execCmdEx("git show d1414ae32d00cb2a78ef01ee246c16de56421938:docs/data/js.json",
                                   workingDir = here / ".." / "..").output)["bytes"].getInt
let jsAfter = parseJson(readFile(here / ".." / ".." / "data" / "js.json"))["bytes"].getInt
proc kilobytes(n: int): string = thousands((n + 512) div 1024) & " KB"
# The version of ada, from the header of the tables it wrote.
let adaVersion = readFile(currentSourcePath.parentDir.parentDir.parentDir / "src/nimaki/util/idna_data.nim")
  .split("as ada ")[1].split(" ")[0]

nbText: &"""
## The findings, first

- **No difference left.** The article [How nimaki reads text](../how-nimaki-reads-text/) slipped
  one odd character into each case of the corpus (a no-break space, a line separator, an emoji...)
  and found {beforeDifferent} answers of {thousands(beforeCases)} that were not Pele's. The same
  {againIdentical} texts are now answered as Pele answers them, and so are all
  {thousands(afterCases)} answers of seven new runs: {afterDifferent} different.
- **Most of them were links.** {hostDifferences} of the {beforeDifferent} were a link whose host
  name held the odd character: `https://exampleΩ.com`. A browser writes such a name in ASCII,
  `xn--example-...`, by rules called IDNA, or refuses it. nimaki kept it as written. It now
  follows the same rules, ported from the code that Node itself runs, and gives the same host as
  Node on every one of the {thousands(notes["testHosts"].getInt)} names of a new test.
- **The others counted bytes where JavaScript counts code units**, or read a character as
  JavaScript does not: the indentation of a YAML block, a method of a class, the `href` of a
  flowchart link, and a date with a line separator in it.
- `tools/mutate.nim` now runs in CI, on seeds 1 to 7, and takes the differences of an earlier run
  again with `--again:FILE`.

## A name for a computer, in any script

A link in a diagram is a URL, such as `https://example.com/page`. Between `//` and the next `/`
is the *host*: the name of the computer that serves the page. The system that finds a computer
from its name (DNS, the Domain Name System) was made for a few characters only: the letters `a`
to `z`, digits and the hyphen. A name is cut into *labels* at each dot: `example` and `com`.

People write in every script, though, so there are names like `bücher.de` or `例え.jp`. The
rules called **IDNA** (Internationalized Domain Names in Applications) turn such a name into
the few characters DNS knows. Each label outside ASCII is written as `xn--` followed by its
**Punycode**, a way of writing any text with letters, digits and hyphens. A browser does it each
time it reads a URL, and so does `new URL()` in JavaScript, which Pele calls to clean each link:
"""

nbCode:
  for host in ["Example.COM", "bücher.de", "exampleΩ.com", "例え.jp", "ｅｘａｍｐｌｅ。ｃｏｍ"]:
    echo host, "  ->  ", parseDomain(host).get("(refused)")

nbText: """
Before the labels are written, each character is *mapped*: upper case becomes lower case, a
full-width letter (as Japanese text writes Latin letters, `ｅ`) becomes its ASCII one, the
ideographic full stop `。` becomes a dot. Some characters are *ignored*, such as a soft hyphen or a
zero-width space, and some are *disallowed*: then the whole name is refused, and Pele leaves the
link out of the drawing. A no-break space is mapped to a plain space, and a host may not hold a
space, so it is refused too:
"""

nbCode:
  for (name, c) in [("a space", " "), ("a no-break space", "\u00A0"), ("a zero-width space", "\u200B"),
                    ("a line separator", "\u2028"), ("an emoji", "😀")]:
    echo "git, ", name, ", hub.com  ->  ", parseDomain("git" & c & "hub.com").get("(refused)")

nbText: """
Then the text is *normalized*. Unicode can write `é` in two ways: as one character, or as `e`
followed by a combining accent. The two look the same, so they must give the same name;
normalization (here the form called NFC) turns each into the single character. Last, each label
is checked: it may not start with an accent, a joiner (an invisible character that tells two
letters to join or not, in Arabic or in Indic scripts) must sit where it does something, and a
label that holds a letter written right to left, as Hebrew and Arabic are, must follow the rules
for such labels (RFC 5893: it may not mix in letters written left to right, and must end with a
letter or a digit).
"""

nbCode:
  echo parseDomain("cafe\u0301.fr").get, " = ", parseDomain("café.fr").get
  echo parseDomain("שלום.co.il").get("(refused)")
  echo parseDomain("\u0301x.com").get("(refused)")

nbText: &"""
## Punycode, in a few lines

Punycode writes the ASCII characters of a label first, then a hyphen, then the others as numbers
in base 36 (the 26 letters and 10 digits), each number saying which character to insert and
where. For `bücher`: `bcher`, a hyphen, then `kva`, which says "insert `ü` (U+00FC) at place 1".
The numbers are written with a variable length, and the length adapts to how far apart the
characters are, so a label in one script stays short:
"""

nbCode:
  for label in ["bücher", "例え", "😀"]:
    var cps: seq[int]
    for r in label.runes: cps.add int(r)
    echo label, "  ->  xn--", codePointsToPunycode(cps).get
  echo punycodeToCodePoints("bcher-kva").get

nbText: &"""
## Ported from Node

Pele does none of this itself: it calls `new URL()`, and Node answers. So the port follows the
code Node runs. Node parses URLs with [ada](https://github.com/ada-url/ada), a C++ library, and
its IDNA is one file, `src/ada_idna.cpp` (version {adaVersion} in the oracle's Node 22).
`src/nimaki/util/idna.nim` ports its steps: map, normalize, cut into labels, check, write
Punycode.

ada's tables (which characters are mapped and to what, and which way each one is written) are
read from that C++ file by a new tool, `tools/idna_data.nim`, into `idna_data.nim`:
{thousands(idnaStarts.len)} ranges of code points, {thousands(idnaMappings.len)} code points of
mappings, {thousands(idnaDirFirst.len)} ranges of writing direction. Normalization reads the
tables of unicodedb, which the regular expressions already use. They are of a later Unicode
(17.0) than ada's (15.0), and that does not matter: Unicode promises that text normalizes the same
way in every later version, and a character newer than ada's tables is disallowed before it is
normalized.

The tables cost room: the JavaScript build grew from {kilobytes(jsBefore)} to
{kilobytes(jsAfter)}, mostly for them and for the normalization tables of unicodedb, which it did
not hold before. They are written as flat arrays of numbers, since `nim js` writes each tuple of an
array as an object with named fields, which is larger.
"""

nbNote &"""
Where ada departs from the IDNA standard, the port does too, since the oracle does:

- A joiner that passes its rule ends the checks of its label: what follows it is not checked for
  direction.
- The rules for right-to-left labels apply only to a label that holds such a letter, not to every
  label of a name that does. A label that starts with a Latin letter and holds a Hebrew one is
  checked as left to right, and its last character is not checked.

The first port followed tr46, the JavaScript library that the URL standard's own reference code
uses, and it differed from Node on {thousands(notes["tr46Different"].getInt)} of
{thousands(notes["tr46Hosts"].getInt)} test names, most of them on such labels. Ported from ada,
it differs on none.
""", nkNim, "Node's IDNA, not the standard's"

nbText: """
## Counting like JavaScript, four more times

The [previous post](../where-each-statement-sits/) told how JavaScript counts a string in UTF-16
code units, where Nim counts UTF-8 bytes: `€` is one unit and three bytes. The other differences
were the same mistake, or its cousin.

**The indentation of YAML.** A diagram's front matter is YAML, where the depth of a line is how
many spaces start it. Pele measures it as `line.length - line.trimStart().length`: the code units
of the white space at the start. The port measured bytes, so an ideographic space (U+3000, one
unit, three bytes) pushed a line three columns in instead of one, and a line that Pele finds badly
indented, the port read as the continuation of the line before:
"""

nbCode:
  let front = "---\nconfig:\n  radar:\n    curveTension: 0.1\n \u3000 theme: base\n---\nradar-beta\n  axis A, B, C\n  curve c{1,2,3}\n"
  try:
    discard render(front)
    echo "drawn"
  except CatchableError as e:
    echo e.msg

nbText: """
**A method of a class.** A class member is cut into lines to find its parentheses, and after each
line end the search starts one character later. The port moved one byte, which is right for a
newline but lands inside a line separator (U+2028, three bytes): the rest of its bytes were read as
the start of a method's name. It now moves past the whole character.

**A flowchart `href`.** In `click A href "page.html"`, the keyword takes the white space after it.
Pele takes one code unit; the port took one byte, which cut an ideographic space in two. The error
message for that line is now Pele's.

**A date.** A gantt task can give its start as a date that the format does not fit, and then Pele
asks JavaScript's own date parser (`new Date(text)`), which `src/nimaki/jsdate.nim` ports from
V8, Node's JavaScript engine. V8 reads a date as words, numbers and white space, and a line
separator is white space between two of them, but *not* the end of a word: V8 asks one question
for "is this white space or a line end?" and another for "is this white space?". The port asked
the first for both, so it read `2014-01-` and `12` around a line separator as a date where V8
finds none:
"""

nbCode:
  const ls = "\u2028"   # the line separator
  for (shown, text) in [("2014-01- 12", "2014-01- 12"), ("2014-01-(line separator)12", "2014-01-" & ls & "12"),
                        ("Jan(line separator) 12 2014", "Jan" & ls & " 12 2014")]:
    echo shown, "  ->  ", (if parseDate(text).isNaN: "Invalid Date" else: "a date")

nbText: &"""
The last one is a date, for V8 too: `Jan` followed by a line separator is read as one word, whose
first three letters name a month.
"""

var rows: seq[tuple[seed: int, cases, identical, different: int]]
for i, run in after:
  rows.add (seed: run["seed"].getInt, cases: run["cases"].getInt,
            identical: run["identical"].getInt, different: run["different"].getInt)

nbFold "The seven runs, seed by seed":
  let t = tabella(rows):
    tabHeader "One character slipped in, nimaki against Pele", "tools/mutate.nim, " &
      $after[0]["copies"].getInt & " copies of each ported case"
    optCssTheme()
  nbTable t

nbNote """
- `src/nimaki/util/idna.nim` (new): ada's `to_ascii`, `map`, `is_label_valid` and Punycode;
  `idna_data.nim` (new, written by `tools/idna_data.nim`): ada's tables.
- `src/nimaki/util/url.nim`: `parseDomain`, the host as `new URL()` writes it (IDNA, then the
  characters a host may not hold, then IPv4).
- `src/nimaki/util/yaml.nim`: indentation in UTF-16 code units.
- `src/nimaki/diagrams/class/members.nim`, `src/nimaki/diagrams/flowchart/lexer.nim`: past a line
  end or a space of more than one byte.
- `src/nimaki/jsdate.nim`: a word of a date ends at white space, not at a line end.
- `src/nimaki/diagrams/usecase/json.nim`: a lone surrogate in the message of a JSON error is
  written as U+FFFD before the message is searched, where it stopped the regular expressions (the
  first run of this step found it, by stopping).
- `tools/mutate.nim`: `--again:FILE`; it runs in CI on seeds 1 to 7.
""", nkNim, "In the port"

nbNote &"""
- `tests/test_idna.nim`: {thousands(notes["testHosts"].getInt)} host names, random ones and each code point up to U+2FFFF next to
  a letter, through `new URL()` in Node and `parseDomain`: the same.
- `tests/test_jsdate.nim`: dates with line separators, against Node.
- difftest in C and in JavaScript: every drawing of the corpus still the same bytes as Pele's.
- The article's differences again, and seven new runs of `tools/mutate.nim`: the counts above.
""", nkDone, "Checked"

nbNote """
- `tools/mutate.nim` runs nimaki's C build only. In the JavaScript build, the regular expression
  library reads a lone surrogate (half of a character past U+FFFF, as `&#55296;` makes it) in its
  own way, not as JavaScript does; no case of the corpus has met it.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- A link with a host in any script is written as Node writes it, or left out where Node refuses
  it, so links in diagrams written in any language are Pele's.
- The roadmap step *Odd characters* is done, and the fuzzer keeps watch in CI.

## Sources

- ada's IDNA, [`src/ada_idna.cpp` at v2.9.2](https://github.com/ada-url/ada/blob/v2.9.2/src/ada_idna.cpp),
  and where ada calls it for a host, [`src/unicode.cpp`](https://github.com/ada-url/ada/blob/v2.9.2/src/unicode.cpp).
- [UTS #46, Unicode IDNA Compatibility Processing](https://www.unicode.org/reports/tr46/), and
  [RFC 3492, Punycode](https://www.rfc-editor.org/rfc/rfc3492), [RFC 5893, right-to-left
  scripts](https://www.rfc-editor.org/rfc/rfc5893).
- The URL standard's [host parsing](https://url.spec.whatwg.org/#host-parsing).
- tr46, the first attempt: [the npm package](https://www.npmjs.com/package/tr46).
- V8's date parser, [`src/date/dateparser-inl.h`](https://github.com/v8/v8/blob/12.4.254.21/src/date/dateparser-inl.h).
- [Unicode normalization stability](https://www.unicode.org/policies/stability_policy.html#Normalization).
"""

nbSave
