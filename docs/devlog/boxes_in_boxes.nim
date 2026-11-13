## devlog: 13 Nov 2026 H | Boxes in boxes: c4 and block | The last two types of this thread come out of nimaki byte for byte as Pele draws them: C4 diagrams, whose boundaries nest and whose relations find lanes between shapes, and block diagrams, which put blocks on a grid of columns the author chooses.
## kind: port
import std/[os, strformat, strutils, json, tables]
import nimib
import ../blocks, ../site, ../pele
import nimaki

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
var same = initTable[string, int]()
for r in difftest["types"]:
  cases[r["type"].getStr] = r["cases"].getInt
  same[r["type"].getStr] = r["identical"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]
proc fuzzed(kind: string): string =
  if fuzz.hasKey(kind): fuzz[kind]["cases"].getInt.thousands else: "no"

nbText: &"""
## The findings, first

- **Two more types.** C4 ({same["c4"]} of {cases["c4"]} corpus cases identical) and block
  diagrams ({same["block"]} of {cases["block"]}) come out of nimaki byte for byte as Pele draws
  them. With them, every type this thread set out to port is done: sequence, ishikawa, cynefin,
  wardley, architecture, c4 and block.
- **The fuzzer writes both.** CI draws {fuzzed("c4")} generated C4 diagrams and
  {fuzzed("block")} generated block diagrams on every pull request and compares each with Pele's.
  Before merging, seeds 1 to 4 were identical too, error messages included.
- **Two more Jison lexers.** Both grammars come from Mermaid's Jison files, and Pele hand-writes
  their lexers as loops over *start conditions* (the lexer's modes: inside a string, inside an
  argument list, inside a node's brackets). The port follows each loop line by line, with byte
  offsets where JavaScript has UTF-16 ones.
- **Nesting without recursion.** Both diagrams nest boxes in boxes. Pele's parsers and layouts
  walk the nesting with explicit stacks and lists instead of recursive calls, so a deep diagram
  cannot overflow the call stack; the port keeps those stacks.

## A C4 diagram

The *C4 model*, by Simon Brown, describes software at four levels of zoom: the *context* (the
system and the people and systems around it), its *containers* (the apps and databases it is
made of), their *components*, and the code. Mermaid draws the first levels, plus dynamic and
deployment views, with a syntax that comes from C4-PlantUML: each element is a call with
arguments.
"""

let c4Text = """C4Context
  title A port and its referee
  Person(reviewer, "Reviewer", "Reads the posts")
  System_Boundary(b, "nimaki") {
    System(port, "The port", "Nim, standard library only")
    SystemDb(corpus, "Corpus", "Cases taken from Pele")
  }
  System_Ext(pele, "Pele", "Run in Node, the oracle")
  Rel(reviewer, port, "Reviews")
  Rel(port, corpus, "Reads")
  BiRel(port, pele, "Compares SVG with")
"""

nbText: &"""
```mermaid
{c4Text.strip}
```
"""

nbCode:
  let c4Pele = peleSvg(c4Text)
  let c4Nim = render(c4Text).svg
  echo "identical to Pele's: ", c4Nim == c4Pele

nbSvg c4Nim, "A C4 context diagram, drawn by nimaki; Pele draws the same bytes."

nbText: """
An argument is positional (`"Reviews"` is the label of a relation because it comes third) or
named (`$descr="..."`, which sets the description wherever it is written). One rule of the lexer
surprises: an argument without quotes runs to the next comma, through closing parentheses and
line breaks, so `Person(a)` followed by more lines swallows them all. Mermaid behaves the same,
and so the fuzzer quotes its last arguments most of the time to reach the drawing.

The layout is Mermaid's: in each boundary, its shapes in rows of `c4ShapeInRow` (4 unless
`UpdateLayoutConfig` says otherwise), then the boundaries inside it in rows of
`c4BoundaryInRow`. The relations are Pele's own: a straight line between two shapes when it
crosses nothing, otherwise a detour with two corners through a *lane* between columns or rows,
a little further out for each line already there, so that parallel lines do not merge. Labels
then slide along their line to the spot that covers least of the shapes, the arrowheads and the
labels placed before them.

## A block diagram

A block diagram leaves the layout to the author: `columns 3` makes a grid three blocks wide,
blocks fill it left to right, `a:2` makes a block two columns wide, `space` leaves a cell empty,
and `block ... end` makes a block that holds a grid of its own. Shapes use the flowchart's
brackets, and `<["label"]>(right)` is a *block arrow*, a fat arrow that is itself a block.
"""

let blockText = """block-beta
  columns 3
  source["Pele"] space:1 port["nimaki"]
  block:checks:3
    columns 2
    corpus[("Corpus")] fuzz(("Fuzz"))
  end
  go<["referee"]>(down):3
  verdict{"identical?"}:3
  source --> port
  port -- "SVG" --> verdict
"""

nbText: &"""
```mermaid
{blockText.strip}
```
"""

nbCode:
  let blockPele = peleSvg(blockText)
  let blockNim = render(blockText).svg
  echo "identical to Pele's: ", blockNim == blockPele

nbSvg blockNim, "A block diagram, drawn by nimaki; Pele draws the same bytes."

nbText: """
The layout runs in two passes over the tree of blocks. The first goes from the leaves up and
*measures*: each container works out its columns, each column is as wide as its widest block,
each row as tall as its tallest. The second goes from the root down and *arranges*: each
container hands its children their cells, sharing out any room it has beyond what they need.
Edges are then routed between the blocks they join, straight where two blocks share a row or a
column and with one bend otherwise; when several labelled edges join the same two blocks and
their labels would overlap, Pele widens the gap between those rows or columns and lays the
blocks out again, at most three times, and keeps the wider drawing only if the labels then
overlap less.
"""

nbNote """
JavaScript objects can lack a field, and Pele's code tells *missing* from *empty* in a few
places: a block whose header was a link statement has no id until the model gives it one, and a
block's `widthInColumns` is missing for every block of a link chain but the first. Nim objects
always have every field. The port marks the difference with a flag (`hasId`) or a value no input
can produce (NaN for a missing number, `-1` for missing columns), and says so at the top of each
file.
""", nkNim, "Missing is not empty"

nbNote &"""
- `nim r tools/difftest.nim c4`: {same["c4"]} of {cases["c4"]} identical; `block`:
  {same["block"]} of {cases["block"]}.
- `nim r tools/fuzz.nim c4` and `block`: 5,000 cases on seed 1 and 3,000 on each of seeds 2 to
  4, all identical. The generators vary every element and boundary keyword, positional, named
  and empty arguments, nesting, relations of every kind, style and layout updates, titles,
  accessibility lines and comments for C4; and shapes, block arrows, spans, columns, spaces,
  nested blocks, link chains with and without labels, classes and styles for block diagrams;
  and the render options.
- The whole corpus and every other type's fuzz run, after merging main: identical.
""", nkDone, "Checked"

nbNote """
- Every file is `draft` until a second reading against the TypeScript.
- In Pele the cells of a `space:N` block share one class list when the block already had one,
  so a later `class` statement naming one cell reaches them all. The port gives each cell its
  own list. No corpus case or fuzz case names such a cell; a later step can share the lists.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **C4 and block are done** on the [coverage map](../../coverage/) and the
  [roadmap](../../roadmap/).
- **This thread's list is done.** It ported sequence, ishikawa, cynefin, wardley, architecture,
  c4 and block; it takes the next unclaimed step on the roadmap next.

## Sources

- Pele at the pin: [`src/diagrams/c4/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/c4)
  and [`src/diagrams/block/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/block),
  read in full for this step.
- The idea: [the C4 model](https://c4model.com/) and
  [C4-PlantUML](https://github.com/plantuml-stdlib/C4-PlantUML), whose syntax Mermaid follows.
- The code of this step: [`src/nimaki/diagrams/c4/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/c4),
  [`src/nimaki/diagrams/block/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/block),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
