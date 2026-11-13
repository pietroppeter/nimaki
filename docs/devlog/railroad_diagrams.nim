## devlog: 13 Nov 2026 A | Grammars as tracks: railroad diagrams | nimaki draws Mermaid's railroad diagrams byte for byte as Pele does, in all four of its notations: one rule model, and boxes that know how far they reach above and below their track.
## kind: port
import std/[strformat, strutils, json, tables, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
for r in difftest["types"]: cases[r["type"].getStr] = r["cases"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]

nbText: &"""
## The findings, first

- **Railroad diagrams are done.** The {cases["railroad"]} corpus cases come out of nimaki
  identical to Pele's, byte for byte, and so do {fuzz["railroad"]["cases"].getInt.thousands}
  generated grammars that CI now checks on every pull request.
- **Four notations, one model.** Mermaid reads a grammar written in its own notation, in EBNF, in
  ABNF or as a PEG. Each has its own small parser, and all four end in the same seven kinds of
  node. The drawing only ever sees those.
- **No layout engine needed.** Each piece of a grammar becomes a box that knows its width and how
  far it reaches above and below the line the track runs on. Boxes go side by side or stacked, and
  the arithmetic is all there is.
- **Nine files, about 1,300 lines.** They matched on the first run.

## What a railroad diagram is

A *grammar* says which texts belong to a language: which strings are numbers, say, or valid
lines of a config file. It is a list of *rules*, each a name and what that name stands for. A
*railroad diagram* draws each rule as a track you can ride from left to right: every way through
the track spells something the rule allows. A rounded box is a *terminal*, text that appears
literally; a square box is a *non-terminal*, another rule by name; a fork is a *choice*; a loop
back is a *repetition*; a bypass over a box makes it *optional*.

Here is a small grammar for numbers, in EBNF, the notation most textbooks use:
"""

let ebnfText = """railroad-ebnf-beta
title Numbers
number = [ "-" ], digit, { digit }, [ ".", digit+ ] ;
digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
"""

nbText: &"""
```mermaid
{ebnfText.strip}
```
"""

nbCode:
  let ebnfSvg = render(ebnfText).svg
  echo "identical to Pele's: ", ebnfSvg == peleSvg(ebnfText)

nbSvg ebnfSvg, "Numbers, drawn by nimaki from EBNF; Pele draws the same bytes."

nbText: """
## Four ways to write a rule

The same rule can be written in each of Mermaid's four notations. In Mermaid's own, every node
is a call; in EBNF a comma joins, a bar chooses, brackets make optional and braces repeat; in ABNF
a slash chooses and a number with a star before a part says how many times it repeats; a PEG
writes its choice with a slash, too, and can look ahead with `&` and `!`:
"""

let notations = [
  ("railroad-beta", "sign = sequence(optional(terminal(\"-\")), oneOrMore(nonterminal(\"digit\")));"),
  ("railroad-ebnf-beta", "sign = [ \"-\" ], digit, { digit } ;"),
  ("railroad-abnf-beta", "sign = [\"-\"] 1*digit;"),
  ("railroad-peg-beta", "sign <- \"-\"? digit+ ;"),
]

nbCode:
  for (keyword, rule) in notations:
    let text = keyword & "\n" & rule & "\n"
    echo keyword.alignLeft(20), "identical to Pele's: ", render(text).svg == peleSvg(text)

nbText: """
All four end in the same tree: a *sequence* of an *optional* `-` and a *repetition* of `digit`
at least once. Each parser keeps its own syntax tree, as Mermaid's do, and a short function turns
each kind of syntax node into one of the seven kinds of the model. Some choices happen there: a
sequence or a choice of one thing is that thing, an ABNF `0*1` is an optional, an EBNF exception
`a - b` is drawn as `a`, a `-` and `b` in a row, and a PEG predicate `&x` becomes a dashed box that
reads `&x`.

The trees are rebuilt from the bottom up with a stack of their own, not by recursion, so a
grammar nested a thousand brackets deep does not run out of call stack. The port keeps that walk
(`fold` in `common.nim`) and gives the four syntax trees a single node type, whose kind is the
name the TypeScript uses.

## Boxes that know their reach

To draw, each node becomes a *box*. Its track comes in on the left and leaves on the right, on
one line, the *baseline*; the box records its width and how far it reaches *up* and *down* from
that line. Then:

- a **sequence** is its parts side by side, with a gap between them, as tall as its tallest part;
- a **choice** stacks its branches under the first one, each placed just below the one above it,
  with curves out of the baseline and back;
- an **optional** adds a bypass that rises above its part;
- a **repetition** adds a loop under its part that runs back, with a count under it when the count
  is not just "once or more": `3×`, `≥2×`, `≤5×`, `2–5×`.

Because every box knows its reach, placing the next rule or the next branch is a sum. The
drawing is a second walk over the boxes, with an explicit stack again, that writes the track as
one SVG path per rule.

When a host says the diagram must fit a narrow width, a sequence too wide for its room *folds*:
it breaks into rows that the track runs through one after another, turning back at the end of
each row. Each node is given the room its parent leaves it, from the top down, before any box is
measured:
"""

let longText = """railroad-beta
statement = sequence(terminal("if"), nonterminal("condition"), terminal("then"), nonterminal("block"), optional(sequence(terminal("else"), nonterminal("block"))), terminal("end"));
"""

nbCode:
  let wide = render(longText)
  let narrow = render(longText, RenderOptions(maxWidth: some(390.0)))
  echo "wide ", wide.width, ", narrow ", narrow.width, ", identical to Pele's: ",
    narrow.svg == peleSvg(longText, %*{"maxWidth": 390})

nbSvg narrow.svg, "A long rule, folded for a phone."

nbNote """
- Pele's syntax trees are four sets of TypeScript types; here they are one `Part` with the
  TypeScript `$type` as its kind and its parts in a list, in the order Pele's `parts` reads them.
- Pele keys the room of each node by the node object in a `Map`; the port keys it by the node's
  address in a `Table`.
- Two names clash with Nim: `except` is a keyword (an EBNF frame's flag is `exception`), and
  `unescape` is also in `std/strutils`, so the railroad files import it without that one.
""", nkNim, "In the port"

nbNote &"""
The {cases["railroad"]} corpus cases: identical. Generated grammars before merging: 3,000 and
then three times 5,000 on three seeds, identical. The generator writes all four notations, with
front matter that sets the railroad options, titles, comments and rules nested up to three
deep, and breaks a rule now and then; about three in five draw and the rest check Mermaid's
error messages. CI runs {fuzz["railroad"]["cases"].getInt.thousands} on every pull request.
""", nkDone, "Checked"

nbNote """
- Pele's tests for the four grammars (`tests/railroad/`) are not ported; the corpus and
  the fuzzer check the parsers through the drawing.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Railroad is done** on the [coverage map](../../coverage/) and the [roadmap](../../roadmap/).
- **Next, in this thread:** gantt, the one with dates.

## Sources

- Pele at the pin: [`src/diagrams/railroad/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/railroad),
  read for this step.
- Mermaid's examples, as Pele keeps them: [`tests/corpus/railroad-docs.json`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/corpus/railroad-docs.json).
  Mermaid's own page on the syntax could not be reached from the sandbox, so it was not read.
- The code of this step: [`src/nimaki/diagrams/railroad/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/railroad),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
