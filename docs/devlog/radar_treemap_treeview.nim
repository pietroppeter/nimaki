## devlog: 12 Nov 2026 P | Radar, treemap and treeview | Three more diagrams, byte for byte as Pele draws them: a spider chart, rectangles that share out an area, and a folder tree that accepts the box-drawing characters people paste.
## kind: port
import std/[strformat, strutils, json, tables]
import nimib
import ../blocks, ../site, ../pele
import nimaki
from nimaki/js import toPrecision, toExponential, jsParseFloat, jsString, utf16Len
import nimaki/diagrams/treemap/format
import nimaki/diagrams/treeview/box_drawing

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

- **Three more types.** Radar ({cases["radar"]} corpus cases), treemap ({cases["treemap"]}) and
  treeview ({cases["treeView"]}) come out of nimaki identical to Pele's, byte for byte. With
  flowchart, which landed beside them, the referee now finds {identical} identical drawings in the
  corpus, and none different.
- **The fuzzer writes them too.** CI renders {fuzz["radar"]["cases"].getInt.thousands} radars,
  {fuzz["treemap"]["cases"].getInt.thousands} treemaps and {fuzz["treeView"]["cases"].getInt.thousands}
  trees on every pull request and compares every drawing and every error message.
- **The fuzzer caught a Nim trap.** Closures made in a Nim loop share the loop's variables, where
  JavaScript gives each turn its own. One wrong column in thirteen error messages, out of 3,000
  trees, gave it away. The fix is a new row in the [porting guide](../../porting/).
- **More of JavaScript's numbers.** Treemap labels its values with `toPrecision` and
  `toExponential`, and reads them with `parseFloat`. All three are now in `js.nim`, tested against
  Node.

## Radar

A *radar chart* (or spider chart) compares a few things on several measures at once. Each
measure is an *axis*, a spoke from the centre; each thing is a *curve*, a closed line through its
value on every spoke:
"""

let radarText = """radar-beta
  title Three ports
  axis lex["Lexing"], parse["Parsing"], layout["Layout"], text["Text"], svg["SVG"]
  curve pie["Pie"]{3, 2, 1, 2, 4}
  curve tree["Treeview"]{4, 3, 2, 3, 3}
  max 5
"""

nbText: &"""
```mermaid
{radarText.strip}
```
"""

nbCode:
  let radarSvg = render(radarText).svg
  echo "identical to Pele's: ", radarSvg == peleSvg(radarText)

nbSvg radarSvg, "A radar chart, drawn by nimaki; Pele draws the same bytes."

nbText: """
Radar is read by the Langium-style tokenizer that pie uses ([First light](../first-light/)
explains it). Two things in it were new:

- **A curve through the points.** On a round grid (`graticule circle`, the default), Pele draws
  each curve as a *Catmull-Rom spline*: a smooth
  line that passes through every point, where the direction at each point is the direction from
  the point before it to the point after it. Each piece between two points becomes one cubic
  Bézier curve, the kind SVG draws with `C`, whose two control points are computed from those four
  neighbours and the `curveTension` of the configuration. On a polygon grid the curve is a polygon.
- **A matcher that remembers.** A number token is `/[0-9]+\.[0-9]+(?!\.)|0|[1-9][0-9]*(?!\.)/`. Tried
  at every digit of a long run of zeros, a regular expression reads to the end of the run each
  time: quadratic. Pele remembers the run it last read in two module variables, reset for each
  text. In nimaki the token type has a `scanner` field instead: a procedure that makes the matcher,
  called once per text, so the matcher's memory starts fresh with each diagram.

## Treemap

A *treemap* shows a hierarchy of sizes, such as a budget or a disk, as rectangles: each leaf gets
an area in proportion to its value, inside the rectangle of its section.
"""

let treemapText = """treemap-beta
"Budget"
    "People"
        "Salaries": 700
        "Training": 60
    "Things"
        "Equipment": 200
        "Supplies": 100
        "Rent": 240
"""

nbText: &"""
```mermaid
{treemapText.strip}
```
"""

nbCode:
  let treemapSvg = render(treemapText).svg
  echo "identical to Pele's: ", treemapSvg == peleSvg(treemapText)

nbSvg treemapSvg, "A treemap, drawn by nimaki."

nbText: """
Which rectangles? Cutting a rectangle into strips, one per value, is easy, but thin strips are
hard to read and to label. The *squarified* layout (Bruls, Huizing and van Wijk, 2000) keeps the
rectangles close to squares. It sorts the values from largest to smallest and lays them along the
shorter side of the free space, in a row. Before adding the next value to the row, it asks: would
the worst rectangle of the row, the one furthest from a square, get better or worse? While it gets
better the row grows; when it would get worse the row is closed, and a new row starts in the space
left. Pele's `squarify` is that loop in twenty lines, and the port is the same twenty lines.

### Writing a value

A treemap can print values with a format, `valueFormat`, in the language of
[d3-format](https://d3js.org/d3-format): `,` for thousands separators, `$`, `.2f` for two
decimals, `%`, `e`. Pele reads the parts treemaps use and leaves out the rest. Its default, with
no type letter, writes the value with twelve significant digits, through `toPrecision`:
"""

nbCode:
  for spec in [",", "$,.2f", ".1%", ".3e", "d"]:
    let f = formatter(spec)
    echo spec.alignLeft(6), " → ", f(1234.5678), "   ", f(0.000123)

nbText: """
`toPrecision(12)` and `toExponential(3)` write the exact decimal value of the double and round it,
ties up, as the ECMAScript specification asks; `toFixed` already did. They are in `js.nim` beside
`jsParseFloat`, which reads the longest number at the start of a text, as `parseFloat` does:
"""

nbCode:
  echo toPrecision(0.1 + 0.2, 17), "  ", toPrecision(1234.5678, 2), "  ", toExponential(1234.5678, 3)
  echo jsString(jsParseFloat("12.5kg")), "  ", jsString(jsParseFloat("  -Infinityx")), "  ", jsString(jsParseFloat("x1"))

nbText: """
## Treeview

A *treeview* draws a folder tree, as a file manager or the `tree` command shows it. The plain
form is indentation, with a `/` after a folder name. It also takes the tree as `tree` prints
it, with the box-drawing characters `├──`, `└──` and `│`, so you can paste one in:
"""

let treeText = """treeView-beta
├── src/
│   ├── nimaki.nim :::highlight ## the entry point
│   └── nimaki/
│       └── diagrams/
├── docs/
└── README.md
"""

nbText: &"""
```mermaid
{treeText.strip}
```
"""

nbCode:
  let treeSvg = render(treeText).svg
  echo "identical to Pele's: ", treeSvg == peleSvg(treeText)

nbSvg treeSvg, "A treeview from box-drawing input, drawn by nimaki."

nbText: """
The grammar reads only indentation. Before parsing, a *preprocessor* (Mermaid's, which Pele
ports) rewrites box-drawing lines into indentation: the depth of an entry is the column of its
branch character, `├` or `└`, divided by the width of one level, plus one.
"""

nbCode:
  echo preprocessBoxDrawing(treeText).text

nbText: """
That column is where UTF-8 and UTF-16 part ways. JavaScript counts a line in UTF-16 code units,
and a box character is one of them; in UTF-8 it is three bytes. `│   ├── ` has its branch
character at column 4 for Pele, and at byte 6 in Nim. Divided by a level width of 4, the bytes
would put the entry one level too deep. So the preprocessor counts code units wherever a
position enters arithmetic, and slices bytes only to cut text:
"""

nbCode:
  let line = "│   ├── nimaki/"
  echo "bytes before ├: ", line.find("├"), ", UTF-16 code units: ", utf16Len(line, 0, line.find("├"))

nbText: """
### Errors on the lines you wrote

When the rewritten text has a syntax error, its line and column are those of the rewritten text,
which you never saw. Pele keeps, for each new line, the line it came from and a function that
turns a column of the new line into one of the old, undoing the box prefix and any tab expanded
to four spaces. The error is then located again in the original text, and its message rewritten.
"""

let badTree = "treeView-beta\n├── src/\n│   └── \"unclosed\n"

nbCode:
  try:
    discard render(badTree)
  except PeleError as e:
    echo e.msg
    echo "same message as Pele's: ", e.msg == peleRenders([badTree])[0]["message"].getStr

nbText: """
Here the fuzzer found the one bug of this step. Pele makes one column function per line, inside
the loop over the lines. In JavaScript each turn of a loop has its own `const` variables, so each
function keeps its own line. A Nim closure captures the variables themselves, and a loop body's
variables live in one place shared by every turn, so every function saw the last line's prefix.
Most errors fall at the start of a line, where the prefix is all that matters; thirteen fuzzed
trees in 3,000 had their column wrong. The fix makes each function in a procedure of its own,
`columnMap`, which gives every call fresh variables.

### Icons

With `showIcons`, or an `icon(...)` on an entry, a row gets an icon: a folder or a file outline of
Pele's own, or the host's. A name like `logos:react` is handed to the host's icon resolver
(`options.icons`), and the configuration can pick icons by file name or extension. nimaki takes
the same resolver, as a Nim procedure.
"""

nbNote &"""
The corpus cases of radar, treemap and treeview: identical. Generated inputs before merging: more
than 25,000 of each type across several seeds, identical, including box-drawing trees with tabs,
heavy lines and errors, and the `monospace: ["files"]` option, new in the fuzzer. CI runs
{fuzz["treeView"]["cases"].getInt.thousands} of each on every pull request. `toPrecision`,
`toExponential` and `jsParseFloat` against Node (`tests/test_js.nim`).
""", nkDone, "Checked"

nbNote """
- An icon resolver can only be passed from code, not through the oracle's JSON, so the host's
  icons are not compared; the built-in outlines are.
- `toLowerCase()` of an extension uses Nim's Unicode lowercase, which agrees with JavaScript's
  except for a few special cases (a dotted capital I); no corpus case has one.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Radar, treemap and treeview are done** on the [coverage map](../../coverage/) and the
  [roadmap](../../roadmap/). `common/accDescr.ts`, the accessible-description token for grammars
  where `accDescr` can also be a name, is shared and ported.
- **The porting guide** has new rows: `toPrecision`, `toExponential` and `parseFloat`; matchers
  that keep state (`scanner`); closures made in a loop; and positions counted in UTF-16 code
  units (`utf16Len`, and `unitOffset` back to bytes).
- **Next, in this thread:** the remaining types that need no layered layout and that no other
  thread has claimed, smallest first, each claimed on the roadmap before it starts.

## Sources

- Pele at the pin: [`src/diagrams/radar/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/radar),
  [`src/diagrams/treemap/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/treemap),
  [`src/diagrams/treeview/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/treeview),
  [`src/diagrams/common/accDescr.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/accDescr.ts),
  read for this step.
- The squarified layout: Mark Bruls, Kees Huizing and Jarke J. van Wijk,
  [Squarified Treemaps](https://www.win.tue.nl/~vanwijk/stm.pdf) (2000); not read for this step,
  the description above follows Pele's code.
- JavaScript's rules: [Number.prototype.toPrecision](https://tc39.es/ecma262/#sec-number.prototype.toprecision),
  [toExponential](https://tc39.es/ecma262/#sec-number.prototype.toexponential) and
  [parseFloat](https://tc39.es/ecma262/#sec-parsefloat-string) in the ECMAScript specification.
- Mermaid's syntax: [radar](https://mermaid.js.org/syntax/radar.html),
  [treemap](https://mermaid.js.org/syntax/treemap.html) and
  [d3-format](https://d3js.org/d3-format) for `valueFormat`.
- The code of this step: [`src/nimaki/diagrams/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams),
  [`src/nimaki/js.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/js.nim),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
