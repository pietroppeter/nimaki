## devlog: 13 Nov 2026 G | Maps and clouds: wardley and architecture | Two more beta diagrams come out of nimaki byte for byte as Pele draws them: Wardley maps, which place a value chain on an axis of evolution, and architecture diagrams, whose services and groups Pele puts on a grid from the sides their edges name.
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

- **Two more types.** Wardley maps ({same["wardley"]} of {cases["wardley"]} corpus cases
  identical) and architecture diagrams ({same["architecture"]} of {cases["architecture"]}) come
  out of nimaki byte for byte as Pele draws them. Both are *beta* in Mermaid: they start with
  `wardley-beta` and `architecture-beta`.
- **The fuzzer writes both.** CI draws {fuzzed("wardley")} generated maps and
  {fuzzed("architecture")} generated architecture diagrams on every pull request and compares
  each with Pele's. Before merging, seeds 1 to 4 were identical too, error messages included.
- **Both parsers are Langium grammars** in Mermaid, so both reuse the token reader that the
  [pie step](../first-light/) ported: a list of token types tried in order, where a keyword gives
  way to a longer identifier (`inertiaX` is a name, not the keyword `inertia` and an `X`).
- **A grid instead of a physics simulation.** Mermaid lays out architecture diagrams with a
  force-directed solver; Pele puts every service in a grid cell, and an edge `a:R -- L:b` puts
  `b` in the cell to the right of `a`. The port follows Pele's grid exactly.

## A Wardley map

A *Wardley map*, named after Simon Wardley, who made them up, draws what a business does for its
users as a chain of components: the user at the top, what they see below them, and what that
needs further down. Up and down is *visibility*: how close a component is to the user. Left to
right is *evolution*: from *genesis* (new, uncertain, made by hand) through *custom built* and
*product* to *commodity* (standard, bought by the unit, like electricity). A map shows where
each piece sits on that axis, and so which ones to build, which to buy, and which are about to
move.

Each component has two coordinates, `[visibility, evolution]`, both from 0 to 1:
"""

let mapText = """wardley-beta
title Tea shop
anchor Customer [0.95, 0.63]
component Cup of tea [0.79, 0.61] label [19, -4]
component Cup [0.73, 0.78]
component Tea [0.63, 0.81]
component Hot water [0.52, 0.80]
component Kettle [0.43, 0.35] (build)
component Power [0.10, 0.70] (buy)
Customer -> Cup of tea
Cup of tea -> Cup
Cup of tea -> Tea
Cup of tea -> Hot water
Hot water -> Kettle
Kettle -> Power
evolve Kettle 0.62
note "Kettles are a product now" [0.35, 0.55]
"""

nbText: &"""
```mermaid
{mapText.strip}
```
"""

nbCode:
  let mapPele = peleSvg(mapText)
  let mapNim = render(mapText).svg
  echo "identical to Pele's: ", mapNim == mapPele

nbSvg mapNim, "A Wardley map, drawn by nimaki; Pele draws the same bytes."

nbText: """
A name can have spaces (`Cup of tea`), so the parser cannot stop a name at the first blank:
it reads words until the `[` of the coordinates, and a link `Hot water -> Kettle` is resolved by
looking the words up among the components already named. `evolve Kettle 0.62` draws where the
kettle is heading, `(build)` and `(buy)` mark how each piece is sourced, and a note is free text
on the map. The drawing itself is the simplest part: the coordinates become positions on the
canvas, and the work is in placing labels where they do not cover lines.

## An architecture diagram

An architecture diagram draws a system as *services* (with an icon: a server, a database, a
disk, the internet, the cloud), *groups* that hold them, and *junctions* where edges meet. An
edge names the side of each end it attaches to: `L`, `R`, `T` or `B`.
"""

let archText = """architecture-beta
  group api(cloud)[API]
  service db(database)[Database] in api
  service disk1(disk)[Storage] in api
  service server(server)[Server] in api
  service gateway(internet)[Gateway]
  db:L -- R:server
  disk1:T -- B:server
  gateway:R --> L:server
"""

nbText: &"""
```mermaid
{archText.strip}
```
"""

nbCode:
  let archPele = peleSvg(archText)
  let archNim = render(archText).svg
  echo "identical to Pele's: ", archNim == archPele

nbSvg archNim, "An architecture diagram, drawn by nimaki; Pele draws the same bytes."

nbText: """
## Edges that say where things go

Mermaid gives the sides of each edge to a *force-directed* layout: the nodes repel each other
like charges, the edges pull like springs, and the solver moves everything a little at a time
until it settles. It works, but the answer depends on every step of the simulation.

Pele reads the sides as a placement instead. `db:L -- R:server` says that the database's left
side faces the server's right side, so the database goes in the cell to the right of the server.
Every service and junction takes one cell; a group is a solid rectangle of cells, laid out on its
own first and then placed in its parent as one block, so a group never encloses a service that
is not in it. When the cell an edge asks for is taken, the node slides sideways, to whichever
side is nearer, so the edge can still leave straight; edges between two like sides (`R` to `R`)
say least about where their ends go, so they are placed last. Edges are then drawn as straight
runs with rounded corners between the sides they name.

That is the part of the step that needed the most care: the cells are kept in tables keyed by
their column and row, and the order in which Pele visits nodes and edges decides which one wins
a contested cell, so the port keeps every list in Pele's order (insertion-ordered tables where
Pele uses a `Map`).
"""

nbNote """
Both diagrams fit labels to a width by cutting them, character by character, and JavaScript
counts characters in UTF-16 units: an emoji is two units, and cutting between them leaves half a
character. Nim strings are UTF-8 bytes. The port measures in UTF-16 units and maps each cut back
to a byte offset (`unitOffset` in the text measurer), and where Pele's cut falls inside a pair of
surrogates the port does the same, so the label ends with the same broken character Pele's does.
""", nkNim, "Cutting a label where JavaScript would"

nbNote &"""
- `nim r tools/difftest.nim wardley`: {same["wardley"]} of {cases["wardley"]} identical;
  `architecture`: {same["architecture"]} of {cases["architecture"]}.
- `nim r tools/fuzz.nim wardley` and `architecture`: 5,000 cases on seed 1 and 3,000 on each of
  seeds 2 to 4, all identical. The generators vary names with spaces and odd characters,
  coordinates in and out of range, links, pipelines, evolution stages, notes and annotations for
  maps; groups inside groups, icons and icon texts, edge sides and arrows, `{{group}}` ends and
  alignment rows for architecture; and the render options.
- The whole corpus and every other type's fuzz run, after merging main: identical.
""", nkDone, "Checked"

nbNote """
- Every file is `draft` until a second reading against the TypeScript.
- Mermaid marks both types beta, so their syntax may still change in a later Mermaid; the port
  follows the pin.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Wardley and architecture are done** on the [coverage map](../../coverage/) and the
  [roadmap](../../roadmap/).
- **Next, in this thread:** c4 and block, already identical locally, in the next pull request.

## Sources

- Pele at the pin: [`src/diagrams/wardley/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/wardley)
  and [`src/diagrams/architecture/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/architecture),
  read in full for this step; the grid placement is explained in the comment at the top of
  `architecture/layout.ts`.
- The idea: [Wardley map](https://en.wikipedia.org/wiki/Wardley_map) on Wikipedia, and
  [force-directed graph drawing](https://en.wikipedia.org/wiki/Force-directed_graph_drawing).
- The code of this step: [`src/nimaki/diagrams/wardley/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/wardley),
  [`src/nimaki/diagrams/architecture/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/architecture),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
