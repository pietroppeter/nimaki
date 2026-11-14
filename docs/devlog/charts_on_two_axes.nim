## devlog: 14 Nov 2026 B | Charts on two axes | nimaki now draws xychart, Mermaid's bar and line charts, as Pele does, byte for byte: round numbers on the axes, bars that share a slot, and lines cut where they leave the plot.
## kind: port
import std/[strformat, strutils, json, tables]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/diagrams/xychart/ticks

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
for r in difftest["types"]:
  cases[r["type"].getStr] = r["cases"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["xychart"]

nbText: &"""
## The findings, first

- **One more type.** nimaki draws Mermaid's `xychart` identical to Pele, byte for byte, on all
  {cases["xychart"]} of the corpus's cases, compiled to C and to JavaScript.
- **The fuzzer agrees:** {fuzz["cases"].getInt.thousands} generated charts, {fuzz["identical"].getInt.thousands}
  identical, {fuzz["rendered"].getInt.thousands} of them drawn and the rest refused with the same
  error as Pele's.
- **First time right.** The seven files (a lexer, a parser, the chart's data, the ticks and the
  drawing, about a thousand lines of TypeScript) gave the same bytes as Pele on the first run.
- **Done from the other end.** Pietro asked to finish the last types quickly, so this thread took
  xychart and venn while the thread that started the small charts takes sankey and quadrant.
"""

nbText: """
## What an xychart is

An xychart has two axes. Along one runs the *category* axis: either named slots (`jan`, `feb`,
`mar`, a *band* axis) or a range of numbers (a *linear* axis). Along the other runs the *value*
axis, always numbers. Each series is a `bar` or a `line` of values, one per slot.
"""

let chartText = """xychart-beta
  title "Sales revenue"
  x-axis [jan, feb, mar, apr, may, jun]
  y-axis "Revenue (in $)" 4000 --> 11000
  bar [5000, 6000, 7500, 8200, 9500, 10500]
  line [5000, 6000, 7500, 8200, 9500, 10500]
"""

nbText: "```mermaid\n" & chartText & "```"

nbCode:
  let chartSvg = render(chartText).svg
  echo "identical to Pele's: ", chartSvg == peleSvg(chartText)

nbSvg chartSvg, "An xychart, drawn by nimaki; Pele draws the same bytes."

nbText: """
`horizontal` after `xychart-beta` turns it on its side: the categories run down and the bars
run right. Without a `y-axis` range, the range comes from the data.

## Round numbers on an axis

An axis from 0 to 10,500 should not be labelled 0, 1,312.5, 2,625. People read axes in round
steps: 1, 2 or 5 times a power of ten. Pele picks the step this way: divide the span by about how
many ticks fit (one per 56 pixels up the side), then round that raw step to the nearest of 1, 2,
5 and 10 times its power of ten. The thresholds are the geometric middles: 1.41 is about the
square root of 2, 3.16 of 10, 7.07 of 50.
"""

nbCode:
  for (span, count) in [(10500.0, 7.0), (1.0, 5.0), (0.3, 3.0), (37.0, 10.0)]:
    let step = tickStep(span, count)
    echo span, " in about ", count, " parts: step ", step, ", ticks ", ticksBetween(0, span, step)

nbText: """
A step below one comes back negative: −10 stands for 0.1, −5 for 0.2. Ticks are then found by
dividing by a whole number, never by multiplying by 0.1, so the third tick of 0.1 prints as 0.3
and not as 0.30000000000000004, the sum that 0.1 + 0.1 + 0.1 gives in binary floating point.
When the range comes from the data, its ends grow to whole steps, and a chart with bars always
includes zero, so that a bar's length means its value.

## Bars in a slot, lines cut at the edge

Each category is a slot of equal width. With several bar series, the bars of one category share
70% of its slot side by side, with a gap of at most 2 pixels between them. A bar that goes below
zero runs down from a baseline, and the chart draws that baseline.

A line can leave the plot, when a `y-axis` range is narrower than the data. Pele cuts each
segment at the edges, the way the Liang–Barsky algorithm clips a line to a box: it writes the
segment as a start plus a fraction `t` of its length, and finds the fractions where it crosses
the bottom (value 0) and the top (value 1). The part between them is drawn; a segment entirely
outside is skipped, and the next visible point starts a new stroke.
"""

let clipText = """xychart-beta
  x-axis [a, b, c, d, e, f]
  y-axis 0 --> 10
  line [2, 14, 6, -4, 8, 3]
  bar [1, 3, 5, 7, 9, 11]
"""

nbText: "```mermaid\n" & clipText & "```"

nbCode:
  let clipSvg = render(clipText).svg
  echo "identical to Pele's: ", clipSvg == peleSvg(clipText)

nbSvg clipSvg, "The line leaves the plot twice and is cut at its edges; the last bar stops at the top."

nbNote """
Mermaid's grammar for xychart is written for Jison, a parser generator. Its rule for markdown
strings (a quote followed by a backtick) is quoted so that it matches a long, odd piece of text
instead: Pele reproduces that rule as written, as `BROKEN_RULE`, so it accepts and rejects what
Mermaid does. A series may also be declared before its categories, and keep more values than
there are categories; the extra ones are not drawn.
""", nkPele, "Kept from Mermaid"

nbNote """
- Seven files under `src/nimaki/diagrams/xychart/`, one per TypeScript file, with Pele's names.
- `undefined` for a value is NaN, which no value read from the text can be, and `finite` gives
  NaN for anything that is not a finite number.
- `wordAt`, which matches a keyword in either case, is a new shared file,
  `diagrams/common/caseless.nim`. The keyword test of the older lexers (`keywordAt`) is not the
  same: it treats a carriage return as a hyphen (13 or 32 is 45), so `x-axis` needed its own.
""", nkNim, "In the port"

nbNote &"""
- `difftest xychart`: {cases["xychart"]} of {cases["xychart"]} identical, also with `--js`.
- `fuzz xychart`: {fuzz["cases"].getInt.thousands} cases of seed 1, all identical, error messages
  included; seeds 2 and 3 were also run by hand, identical. CI runs seed 1 on every pull request.
""", nkDone, "Checked"

nbText: """
## What this changes for the port

- **xychart is done**, on the [roadmap](../../roadmap/) and the
  [coverage map](../../coverage/).
- **Next in this thread:** venn, then the proposal for diagrammari.

## Sources

- Pele at the pin: [`src/diagrams/xychart/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/xychart)
  and [`src/diagrams/common/caseless.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/caseless.ts),
  read for this step.
- Mermaid's syntax: [XY chart](https://mermaid.js.org/syntax/xyChart.html); not read for this
  step, the description above follows Pele's code.
- The clipping: Y.-D. Liang and B. A. Barsky, *A new concept and method for line clipping*,
  ACM Transactions on Graphics 3 (1), 1984; not read for this step, named for the method Pele's
  code follows.
- The code of this step: [`src/nimaki/diagrams/xychart/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/xychart),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
