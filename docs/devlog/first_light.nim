## devlog: 12 Nov 2026 L | First light: the core, and a pie | nimaki draws its first diagram: every pie of the corpus, and 5,000 generated ones, byte for byte as Pele does.
## kind: port
import std/[os, strformat, strutils, json, sequtils, algorithm]
import nimib
import ../blocks, ../site, ../pele
import nimaki
from nimaki/js import jsRound, toFixed, jsString, utf16Len, codeUnits
from nimaki/svg/builder import num
from nimaki/diagrams/common/tokens import tokenize, Tokens
from nimaki/diagrams/pie/parser import PIE_TOKENS, parsePie

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var pieRow: JsonNode
for row in difftest["types"]:
  if row["type"].getStr == "pie": pieRow = row
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["pie"]

proc nimLines(dir: string): int =
  for path in walkDirRec(repoDir / dir):
    if path.endsWith(".nim"): result += readFile(path).countLines

let portLines = nimLines("src")

nbText: &"""
## The findings, first

- **nimaki draws pies.** All {pieRow["cases"].getInt} pie cases of the corpus come out of the port
  identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} pie inputs made up
  by a generator ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages), on every run of CI. Astronomers call the first image a new telescope takes its
  *first light*; this is ours.
- **Most of the work was under the pie.** The pie itself is three short files. To draw it, the port
  needed the core it stands on: reading the input (front matter in YAML, directives, comments,
  entities), finding the diagram type, the tokenizer, measuring text, writing SVG, the colour
  palette, and `render()` itself. In all, {portLines.thousands} lines of Nim in `src/`.
- **JavaScript hides in the details.** How a number is written, how a tie is rounded, how long a
  string is: each is a small thing that changes bytes. They now live in one module,
  `src/nimaki/js.nim`, tested against Node on every run.
- **No regular expressions.** The core and pie needed about 60 of Pele's; each became a small
  hand-written scanner, as the porting guide asked. None needed a regex library.
- **Strings stay Nim strings.** We settled the open question of strings with a decision record:
  UTF-8 inside, and JavaScript's UTF-16 counted only where it shows.

## A pie, twice

Here is a pie written in Mermaid, the same one the [referee](../the-referee/) showed:
"""

let pieText = "pie title What a pie needs\n  \"text measurer\" : 675\n  \"SVG builder\" : 1751\n  \"pie itself\" : 328\n"

nbText: &"""
```mermaid
{pieText.strip}
```

First drawn by Pele, in Node, while this page was built:
"""

let fromPele = peleSvg(pieText)
nbSvg fromPele, "Pele 1.13.0, in Node."

nbText: "And then by nimaki, in the same program that builds this page:"

nbCode:
  let fromNimaki = render(pieText).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "nimaki, in Nim. The same bytes."

nbText: """
They are not two pictures that look alike: they are the same text, down to the last byte. That
is the bar for every part of the port ([decision 0004](../../decisions/#0004-done-means-byte-for-byte-identical)).

## What the core is

Pele draws every diagram type through the same few steps, which
[How Pele is built](../how-pele-is-built/) walked through. A pie uses most of them:
"""

nbPipeline [("preprocess", stDone), ("detect", stDone), ("tokenize", stDone), ("parse", stDone),
            ("measure", stDone), ("draw", stDone), ("SVG", stDone)]

nbText: """
1. **Preprocess** (`preprocess.ts`): the text before the diagram. A block of YAML between two
   `---` lines (the *front matter*) can set a title and a configuration; a `%%{init: ...}%%`
   *directive* can do the same in JSON; lines starting with `%%` are comments and go.
2. **Detect** (`detect.ts`): the first word says which of the 33 types this is.
3. **Tokenize and parse**: the pie's own grammar, read with Pele's shared tokenizer.
4. **Measure** every label: the legend, the title, the percentages.
5. **Draw**: angles to paths, labels in place, a legend beside.
6. **Write the SVG** around it: the root element, the theme's colours, accessibility.

Each TypeScript file became one Nim file with the same name and the same functions, in the same
order. The port map lists them, and each file starts with the one it ports:
"""

nbCode:
  echo readFile(repoDir / "src" / "nimaki" / "diagrams" / "pie" / "parser.nim").splitLines[0 .. 1].join("\n")

nbText: """
## Numbers, the JavaScript way

Every coordinate Pele writes goes through one small function, `num()`: round to two decimals,
and write the shortest text for it (`10`, not `10.00`). Pie also writes its percentages with
JavaScript's `toFixed(0)`. Both round, and rounding is where JavaScript and Nim part ways: on a
*tie* (a number exactly halfway, like 2.5), JavaScript's `Math.round` goes up, toward plus
infinity, while Nim's `round` goes away from zero. For a negative tie, they disagree:
"""

nbCode:
  import std/math
  echo "Nim round(-2.5)      = ", round(-2.5)
  echo "JavaScript's round   = ", jsRound(-2.5)
  echo "num(-0.125)          = ", num(-0.125)   # -12.5 hundredths: a tie, which goes up to -12
  echo "toFixed(12.5, 0)     = ", toFixed(12.5, 0)
  echo "Nim's $1e21          = ", $1e21
  echo "JavaScript's String  = ", jsString(1e21)

nbText: """
`toFixed` has one more subtlety. A number like 1.005 is not stored as 1.005: the computer keeps
the nearest number it can write in binary, which is a little less. JavaScript's `toFixed` rounds
that *exact* stored value, so `(1.005).toFixed(2)` is `1.00`, not `1.01`. Our `toFixed` writes the
exact decimal expansion of the stored number (every binary fraction has one) and rounds that.
`tests/test_js.nim` checks `jsString`, `toFixed` and `jsRound` against Node on about 4,000
seeded numbers, on every run.
"""

nbCode:
  echo "1.005 stored is      ", toFixed(1.005, 20)
  echo "toFixed(1.005, 2)  = ", toFixed(1.005, 2)

nbText: """
## Strings, the JavaScript way

Text in a computer is a list of numbers, and there is more than one way to make that list.
JavaScript uses *UTF-16*: each character is one 16-bit number, or two for the characters that did
not fit (most emoji). Nim, like the web pages and files around it, uses *UTF-8*: each character is
one to four bytes. So "how long is this text?" has three answers:
"""

nbCode:
  import std/unicode
  let party = "🎉 pie"
  echo "bytes (Nim's len):        ", party.len
  echo "characters (runeLen):     ", party.runeLen
  echo "UTF-16 units (JS length): ", utf16Len(party)

nbText: """
The difference shows in three places in the core: the limits on the size of the input and the
output (Pele counts UTF-16 units), the text measurer (it reads UTF-16 units one by one), and the
column of an error message (`Parse error on line 3`, and a `^` under the right character). We kept
Nim's strings and wrote helpers for exactly those three
([decision 0011](../../decisions/#0011-strings-stay-utf-8-javascript-s-utf-16-is-counted-only-where-it-shows)).
The other choice, carrying JavaScript's strings everywhere, would have made every line of the
port stranger to read, to save conversions in three places.

## Measuring text without a browser

A box must be as wide as its label, so a renderer must know how wide text is. In a browser you
ask the browser. Pele, when there is none, uses a table: the width of each printable ASCII
character in Arial, in thousandths of the font size, packed as two base-36 digits each
(`metrics.ts`). Anything else counts as 0.58 of the font size, or a full 1.0 for Chinese, Japanese
and Korean characters, which are square. Adding up is all there is to it:
"""

nbCode:
  for word in ["Dogs", "Cats", "日本"]:
    echo word, ": ", metricsMeasurer.width(word, 14, 0), " px at 14 px"

nbText: """
Ported line by line, this gives the same widths as Pele, so the legend sits at the same place to
the hundredth of a pixel, and the bytes agree.

## Reading a pie: tokens, then a parser

[Drawing a diagram from scratch](../drawing-a-diagram/) explained lexing and parsing with a toy.
Pele's pie works the same way, with a shared tokenizer (`common/tokens.ts`) that the types
written in Mermaid's newer grammar language, Langium, all use. Each kind of token is tried in
order at the current position, and the first that matches wins. Here are the tokens of a small
pie, as the port finds them:
"""

nbCode:
  let small = "pie showData\n  title Pets\n  \"Dogs\" : 386\n"
  let tokens = tokenize(small, PIE_TOKENS, "pie")
  for k in 0 ..< tokens.kinds.len - 1:
    echo PIE_TOKENS[tokens.kinds[k]].name.alignLeft(10), " ",
      small[tokens.starts[k] ..< tokens.ends[k]].escape

nbText: """
The spaces are gone (the `WHITESPACE` type is *hidden*), and so would be comments. The parser
then walks the tokens: `pie`, maybe `showData`, then line after line a title, an accessibility
title or description, or a section `"label" : number`. When a token is not what it expects, it
says so, as Pele does, with the line and a `^` under the column:
"""

nbCode:
  try:
    discard render("pie\n  \"Dogs\" 386\n")
  except PeleError as e:
    echo e.code, ": ", e.msg

nbText: """
Each of Pele's token types is a *regular expression*, a small pattern language for text
(`/[\t ]*title(?:[\t ][^\n\r]*|)/y` is the title's). Nim has regular expressions too, but not
JavaScript's, and they differ in small ways that would change bytes. So every pattern became a
small Nim procedure that answers, at a position, where the match ends, with the pattern in a
comment above it. About 60 of them, from the front matter to the legend's line breaks. The
trickiest are those where the pattern can try one way, fail, and step back to try another
(*backtracking*): each was worked through by hand.

## Drawing the pie

The drawing is geometry. Each slice is a share of the full turn (2π): it starts where the last one
ended. Its outline is a path: from the centre, a line to the rim, an arc along it, and back. A point
on the rim at angle *a* is (sin *a*, −cos *a*) times the radius, so the first slice starts at the
top and the slices go clockwise. A slice wider than half the pie sets the arc's *large* flag.
"""

nbCode:
  # the first slice of the pie above: 675 of 2754
  let share = 675 / (675 + 1751 + 328)
  let stop = share * PI * 2
  echo "the slice ends at ", num(sin(stop) * 120), ",", num(-cos(stop) * 120)
  echo "its label: ", toFixed(share * 100, 0), "%"

nbText: """
A slice too thin for its label (narrower, at the label's distance from the centre, than the
text) gets the label outside the rim, and the pie a margin around it; labels outside that would
overlap are moved along the rim until they clear each other. The legend is a column of colour
swatches and labels, beside the pie, or below it when the host says the pie must fit a narrow
width (the `maxWidth` option): then Pele draws it again, smaller, up to three times.

## The corpus is small, so we made more

The corpus has only 16 pies, and most of them are short. Many lines of the core are never run by
them: front matter with a theme, a palette of colours in `rgb()`, a label in Korean, a broken
number. So this step added a second tool beside the referee, `tools/fuzz.nim`, a *fuzzer*: it
makes up inputs from the pie's grammar, with a fixed seed so a run can be repeated, mixes in
options (font size, padding, a narrow width, an id prefix), and asks Pele and nimaki about each.
Some inputs are wrong on purpose, so the error messages are compared too. CI runs it on every
pull request:
"""

nbCode:
  echo "fuzz: pie, seed ", fuzz["seed"].getInt, ", ", fuzz["cases"].getInt, " cases: ",
    fuzz["identical"].getInt, " identical, ", fuzz["different"].getInt, " different"

nbText: """
While the port was written, the fuzzer ran on more than 20,000 inputs with several seeds, and
the tests of `js.nim` found the one difference the corpus could not: `(-0.0001).toFixed(2)` is
`-0.00` in JavaScript, with its minus sign, and our first `toFixed` dropped it. Pie only rounds
positive numbers, so no pie showed it; a later type would have.

The fuzzer's inputs come from a list of labels and numbers we wrote; it does not invent new
characters. What it checks is listed on the [coverage map](../../coverage/), and what it does
not, below.
"""

nbNote """
The pie corpus (16 cases) and 5,000 generated pies: identical. `detectType` on all 2,118 inputs of
the corpus: identical (`tests/test_detect.nim`). `jsString`, `toFixed(0..3)` and `jsRound` against
Node on about 4,000 numbers: identical (`tests/test_js.nim`).
""", nkDone, "Checked"

nbNote """
- Label features no pie uses: Markdown emphasis, line breaks inside a label, icons, math, and
  wrapping. They are ported with `label.ts` and will be checked by the types that use them.
- Pele's `\p{N}` (any digit, in any script) in a font family name: approximated by Nim's letter
  table. It matters only when a host passes `fontFamily`.
- The browser parts of Pele (`mount`, `enableZoom`, the canvas measurer) are not ported: nimaki
  never runs in a browser page that measures with a canvas.
- Every file is `draft`: translated and checked by the referee, not yet read again with fresh
  eyes against the TypeScript ([decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)).
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Milestone 1 is half done.** Pie is done on the [coverage map](../../coverage/); the
  [roadmap](../../roadmap/) marks the core steps done. Timeline is next: it needs only two small
  things from `svg/edges.ts` (an arrow marker), not the layered layout.
- **Every later type starts from this core.** `render()`, the tokenizer, the label and SVG
  helpers, and the JavaScript helpers are in place; a new type registers itself in `nimaki.nim`.
- **The porting guide grew an idiom map** from what this step met: scanners for regular
  expressions, `Option` for an option that may be missing, `jsTrim` for JavaScript's whitespace,
  templates for local helpers, and names Nim sees as one (`BOLD` and `Bold`).
- **Each type gets a fuzzer** in `tools/fuzz.nim` when it is ported, and CI runs it.
- **The layered layout can start in parallel.** It is the biggest piece of the core
  (`layout/layered.ts` alone is 2,227 lines) and the base of flowchart, state, class and more; it
  does not depend on anything this step left open.

## Sources

- Pele at the pin: [`src/diagrams/pie/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/pie),
  [`src/core.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/core.ts),
  [`src/preprocess.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/preprocess.ts),
  [`src/diagrams/common/tokens.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/tokens.ts),
  [`src/text/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/text),
  [`src/svg/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/svg),
  read for this step.
- JavaScript's rules: [Number::toString](https://tc39.es/ecma262/#sec-numeric-types-number-tostring)
  and [Number.prototype.toFixed](https://tc39.es/ecma262/#sec-number.prototype.tofixed) in the
  ECMAScript specification; [Math.round](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Math/round)
  and [UTF-16 strings](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String#utf-16_characters_unicode_code_points_and_grapheme_clusters) on MDN.
- The code of this step: [`src/nimaki/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim),
  [`tests/test_js.nim`](https://github.com/pietroppeter/nimaki/blob/main/tests/test_js.nim).
"""

nbSave
