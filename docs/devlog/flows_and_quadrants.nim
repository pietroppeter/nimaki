## devlog: 14 Nov 2026 C | Flows and quadrants | Sankey and quadrant charts join the port, byte for byte as Pele draws them: a CSV read with a lexer, columns of flows that settle into place, and a chart in four tiles with a quirk in how it reads numbers.
## kind: port
import std/[strformat, strutils, json, tables]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/diagrams/sankey/lexer as sankeyLexer

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
var identical = 0
for r in difftest["types"]:
  cases[r["type"].getStr] = r["cases"].getInt
  identical += r["identical"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]

nbText: &"""
## The findings, first

- **Two more types, identical on the first run.** Sankey ({cases["sankey"]} corpus cases) and
  quadrant charts ({cases["quadrantChart"]}) come out of nimaki byte for byte as Pele draws them,
  in the C build and in the JavaScript one. The referee now finds {identical} identical drawings
  in the corpus, and none different.
- **The fuzzer found nothing either.** 28,000 generated inputs of each type, across six seeds,
  were identical too, error messages included. CI writes
  {fuzz["sankey"]["cases"].getInt.thousands} of each on every pull request.
- **A sankey is a CSV file**, read by a small lexer with three states, and laid out in columns
  that are nudged six times so that the bands cross less.
- **A quadrant chart reads `[0,0.5]` as an error.** Mermaid's grammar takes `0`, any one
  character and digits as a number, so `0,0` is the x coordinate and the `.5` that follows has
  no place. Pele keeps this, and so does nimaki.
- **This thread's part of the port is done.** Venn and xychart, the last two types, are being
  ported in another thread.

## A flow, written as a table

A sankey diagram shows how much flows from where to where: each band is as thick as its flow.
Mermaid writes it as a CSV table, one row per band: the source, the target and the amount.
"""

let sankeyText = """sankey
Solar,Grid,40
Wind,Grid,60
Gas,Grid,80
Grid,Homes,70
Grid,Industry,90
Grid,Losses,20
Gas,Industry,30
"""

nbText: &"""
```mermaid
{sankeyText.strip}
```

CSV looks simple, but it has quotes: a field in double quotes can hold commas and line breaks,
and a doubled quote stands for one. So Pele reads it with a lexer with *states*, as Mermaid's
generated one does: outside quotes a comma ends a field, inside them it does not. Here are the
tokens of a row with a quoted name:
"""

nbCode:
  let toks = sankeyLexer.tokenize("sankey\n\"Coal, brown\",Grid,12\n")
  for k in 0 ..< toks.types.len:
    echo sankeyLexer.TOKEN_NAMES[toks.types[k]].alignLeft(18), " ", escapeJson(toks.texts[k])

nbText: """
Before that, Pele trims the blanks at the edges of each row (but not inside quotes) and folds
runs of line breaks into one, and it keeps a list of these edits, so that an error found in the
trimmed text is reported at its place in the text as written. nimaki keeps the same list, in
bytes.

## Columns that settle

The layout puts each node in a column: its distance from a node that nothing flows into, along
the longest path. Then each node gets a height for the flow through it, all scaled to fit the
tallest column. That is a first drawing, and its bands cross a lot. So the columns are then
*relaxed*, six times: each node moves towards the height where its bands would run level with
the nodes they come from (and, on the way back, go to), its column is sorted again, and the gaps
are restored. Each pass pulls a little less, by a factor of 0.99.
"""

nbCode:
  let sankeySvg = render(sankeyText).svg
  echo "identical to Pele's: ", sankeySvg == peleSvg(sankeyText)

nbSvg sankeySvg, "A sankey drawn by nimaki; Pele draws the same bytes."

nbText: """
The labels go beside the bars, on the side that faces the middle, and when two labels would
overlap, one moves to the other side of its bar or a line up or down. A band can be painted with
a gradient from the colour of its source to that of its target; each gradient's id is a hash of
the gradient itself (two 32-bit hashes, written in base 36), so two diagrams on one page agree on
their ids. JavaScript multiplies 32-bit numbers with `Math.imul`; nimaki does it in 16-bit halves,
as the [porting guide](../../porting/) asks, so that the JavaScript build gets the same bits.

On a phone the chart narrows, and its labels shrink with it:
"""

nbCode:
  var phone: RenderOptions
  phone.maxWidth = some(390.0)
  let narrow = render(sankeyText, phone)
  echo "width ", narrow.width, ", identical to Pele's: ", narrow.svg == peleSvg(sankeyText, %*{"maxWidth": 390})

nbSvg narrow.svg, "The same sankey for a phone."

nbText: """
A flow cannot go round in a circle, since a node's column comes from what flows into it. Pele
finds the loop and names one of its nodes:
"""

nbCode:
  let loop = "sankey\nA,B,1\nB,C,1\nC,A,1\n"
  try:
    discard render(loop)
  except PeleError as e:
    echo e.msg
    echo "identical to Pele's: ", e.msg == peleRenders([loop])[0]["message"].getStr

nbText: """
## Four tiles

A quadrant chart sorts things on two axes into four tiles. Its grammar is Jison again, with
states for strings, class names and points:
"""

let quadrantText = """quadrantChart
  title Which step next
  x-axis Small --> Large
  y-axis Rare --> Common
  quadrant-1 Do first
  quadrant-2 Plan
  quadrant-3 Later
  quadrant-4 Batch
  Sankey: [0.35, 0.3]
  Quadrant: [0.4, 0.2]
  Venn: [0.45, 0.25]
  Flowchart: [0.9, 0.9] radius: 8
  Sequence: [0.8, 0.75]
  Gantt: [0.6, 0.55]
"""

nbText: &"""
```mermaid
{quadrantText.strip}
```
"""

nbCode:
  let quadrantSvg = render(quadrantText).svg
  echo "identical to Pele's: ", quadrantSvg == peleSvg(quadrantText)

nbSvg quadrantSvg, "A quadrant chart drawn by nimaki."

nbText: """
A point's label goes below it, or above, right or left of it, or under its tile's title: the
first of these places that is inside the chart and does not cover a point, a title or a label
placed before it. If none is free, a second round lets it cross the gaps between the tiles.

## A number that eats a comma

Mermaid's grammar reads a coordinate as `(1)|(0(.\d+)?)`. The dot there is not a decimal point
but a regular expression's *any character*. So `0.5` is a number, and so is `0,5`, and in
`[0,0.5]` the x coordinate is `0,0`. The `.5` that is left has no rule, and the point is an
error. With a space after the comma, as Mermaid's examples write it, all is well:
"""

nbCode:
  for src in ["quadrantChart\n  A: [0,0.5]\n", "quadrantChart\n  A: [0, 0.5]\n"]:
    let pele = peleRenders([src])[0]
    try:
      discard render(src)
      echo "drawn, as by Pele: ", pele["ok"].getBool
    except PeleError as e:
      echo e.msg
      echo "identical to Pele's: ", e.msg == pele["message"].getStr

nbText: """
This is how Mermaid behaves, so Pele keeps it, and nimaki does what Pele does. In nimaki the
lexer reads bytes, where Pele reads UTF-16 units: when the *any character* is past U+FFFF, it is
two units in JavaScript, and the second is no digit, so nimaki checks that too.
"""

nbNote &"""
The corpus cases of sankey and quadrantChart: identical, in C and in JavaScript. Generated
inputs before merging: 28,000 of each type across six seeds, identical, with front matter
options, quoted fields, entities, blank fields, circular links, CRLF, classes, styles and bad
coordinates. CI runs {fuzz["sankey"]["cases"].getInt.thousands} of each on every pull request.
""", nkDone, "Checked"

nbNote """
- Gradients appear only with an `idPrefix` of letters, digits, `_` and `-`; the fuzzer gives one
  in a tenth of its cases.
- Pele sorts short lists by insertion and long ones with JavaScript's sort; every comparison
  breaks ties by index, so any sort gives the same order, and nimaki uses Nim's.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Sankey and quadrant are done** on the [coverage map](../../coverage/) and the
  [roadmap](../../roadmap/).
- **This thread's types are all ported.** Venn and xychart are claimed by another thread.

## Sources

- Pele at the pin: [`src/diagrams/sankey/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/sankey)
  and [`src/diagrams/quadrant/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/quadrant),
  read for this step.
- Mermaid's syntax: [sankey](https://mermaid.js.org/syntax/sankey.html) and
  [quadrant chart](https://mermaid.js.org/syntax/quadrantChart.html). The coordinate rule is
  quoted from Pele's lexer comment, which ports Mermaid's grammar; Mermaid's grammar file itself
  was not read for this step.
- The code of this step: [`src/nimaki/diagrams/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
