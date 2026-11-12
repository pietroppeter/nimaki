## devlog: 12 Nov 2026 Q | Lanes and handoffs: swimlane | nimaki draws Pele's swimlane diagrams byte for byte: a flowchart whose groups become lanes, on a port of the layout that shares one set of ranks across them and routes each handoff with a single corner where it can.
## kind: port
import std/[strformat, strutils, json, tables]
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

- **Swimlane is done.** Its {cases["swimlane"]} corpus cases come out of nimaki identical to Pele's,
  byte for byte, and so do {fuzz["swimlane"]["cases"].getInt.thousands} generated ones that CI now
  writes on every pull request.
- **A swimlane is a flowchart.** Same syntax, same parser, same drawing of nodes and edges: only
  the layout and the drawing of the top-level groups change. Pele's
  [`swimlane/index.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/swimlane/index.ts)
  is 80 lines that hand the flowchart renderer a *variant*, and the flowchart thread had already
  left the hook for it in the port.
- **The work is in the layout.** `layout/lanes.ts`, 629 lines, is a layered layout of its own:
  it ranks the steps with the shared ranking of `layered.ts`, then orders, places and routes them
  so that every step stays in its lane. It ported in one sitting and matched on the first run.
- **One compiler bug met.** A Nim iterator that read a sequence of the enclosing procedure, inside
  a closure, crashed the compiler (`internal error: expr: var not init`). A procedure that returns
  the runs as a list does the same work.

## What a swimlane diagram is

A process often passes between people or teams: the customer asks, support sorts the request,
engineering fixes. A *swimlane diagram* draws each actor as a lane, a long band like a lane of a
swimming pool, and puts each step in the lane of whoever does it. An arrow that crosses from one
lane to another is a *handoff*: the moment work changes hands.

Pele reads it with the flowchart syntax, behind the keyword `swimlane-beta`. Every top-level
`subgraph` is a lane:
"""

let laneText = """swimlane-beta LR
  subgraph Customer
    ask[Report a problem]
    done[Problem solved]
  end
  subgraph Support
    triage{Known issue?}
    answer[Send the answer]
  end
  subgraph Engineering
    fix[Prepare a fix]
    ship[Release it]
  end
  ask --> triage
  triage -->|yes| answer
  triage -->|no| fix
  fix --> ship
  ship --> answer
  answer --> done
"""

nbText: &"""
```mermaid
{laneText.strip}
```
"""

nbCode:
  let laneSvg = render(laneText).svg
  echo "identical to Pele's: ", laneSvg == peleSvg(laneText)

nbSvg laneSvg, "A support process in three lanes, drawn by nimaki; Pele draws the same bytes."

nbText: """
The same text as a flowchart (the first word changed) draws the lanes as ordinary groups: boxes
side by side, each laid out inside itself, with no shared bands to line the steps up:
"""

nbCode:
  let flowText = laneText.replace("swimlane-beta", "flowchart")
  let flowSvg = render(flowText).svg
  echo "identical to Pele's: ", flowSvg == peleSvg(flowText)

nbSvg flowSvg, "The same text drawn as a flowchart."

nbText: """
## How the lanes are laid out

The [post on the layered layout](../layered-layout-and-flowchart/) told the four stages of a
Sugiyama layout: give every node a *rank* (its step along the flow), *order* the nodes of each
rank, *place* them, and *route* the edges. `lanes.ts` keeps the four stages and adds one rule to
each: a node never leaves its lane.

**Ranks are shared.** All the steps of all lanes are ranked together, with the very same
`rank()` the flowchart uses. So "Prepare a fix" sits one rank after "Known issue?" even though
they are in different lanes: a step sits level with what happens at the same time elsewhere.
An edge that skips ranks gets an invisible *dummy* item in each rank it passes, as in the
layered layout, and its dummies drift from the first lane to the last one evenly along the way.

**Order: lane first.** In each rank, items are sorted by lane, and within a lane by the
*barycenter* of their neighbours: the average position of the items they connect to in the rank
before (sweeping down) or after (sweeping up). Eight sweeps settle the order. Sorting by lane
first is the whole trick: an item can move only among the items of its own lane.

**Place: lanes are bands.** Each lane is as broad as its fullest rank (a *run*, the items of one
lane in one rank side by side), or as its title needs. Across the flow, the items of a run start
centred in their lane, then four passes pull each one in line with its neighbours in the same
lane, as far as the lane's edges and the items beside it allow. Along the flow, each rank is a
band as deep as its deepest item.

**Route: handoffs take a corner.** A ranked route follows the dummies, rank by rank. For a
handoff that is often a diagonal stair across the lanes. So `lanes.ts` tries two simpler routes
with a single corner: leave towards the other lane and then follow the flow, or follow the flow
and then turn into the other lane. A route is kept only if it clears every other step and label,
and does not run along another line, which would read as one path. When both corners are
blocked, as for a return past the steps between, the handoff goes around, out to the margin of a
lane, along it, and back in; it takes the margin that crosses the fewest other lines.

**Then again, a little tighter.** A handoff with a simple route no longer needs the room its
dummies kept through the ranks, so the layout runs again without them, up to three rounds; a
handoff that loses its route in the new layout goes back to the ranked one. The gap between ranks
closes up where only straight lines and plain handoffs pass.
"""

nbNote """
`laneLayout` in Pele works on typed arrays (`Int32Array`, `Float64Array`) indexed by item, with
small arrow functions over them. The port keeps that shape: the arrays are `seq[int]` and
`seq[float]`, and the arrow functions are nested procedures, closures over the same arrays. One
change: the helper that visits each run of a rank, `eachRun(row, visit)`, became `runs(row)`,
which returns the runs as pairs. Written as an iterator first, it crashed the Nim compiler.
""", nkNim, "In the port"

nbText: """
## Turned and tightened

A swimlane that runs across (`LR`) is too wide for a phone. The flowchart renderer then draws it
running down, as it does for flowcharts, and if it is still too wide it tightens: lanes keep 12
pixels of room around their items instead of 24. The swimlane variant passes that on to the
layout, and the drawing of the lane turns its title band with it:
"""

nbCode:
  let narrow = render(laneText, RenderOptions(maxWidth: some(390.0)))
  echo "width ", narrow.width, ", identical to Pele's: ",
    narrow.svg == peleSvg(laneText, %*{"maxWidth": 390})

nbSvg narrow.svg, "The same process for a phone."

nbNote &"""
The {cases["swimlane"]} corpus cases of swimlane: identical. Generated inputs before merging:
2,000 and then 5,000 swimlanes on two seeds, identical, with lanes, loose steps (they share an
unnamed lane), groups inside lanes, labels, styles and every flowchart statement inside them; CI
runs {fuzz["swimlane"]["cases"].getInt.thousands} on every pull request.
""", nkDone, "Checked"

nbNote """
- Pele's own layout tests for lanes are in its `tests/layout/`; they are not ported yet (the
  flowchart thread ported the 31 of the layered layout).
- The safety limits (`MAX_DUMMIES`, `ROUTE_BUDGET`, past which a large graph is laid out once and
  routed simply) are ported but no corpus or generated case reaches them.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Swimlane is done** on the [coverage map](../../coverage/) and the [roadmap](../../roadmap/),
  and the shared layouts have three of their four parts: layered, compound, and now lanes.
- **The FlowVariant hook works.** The flowchart thread left it unused; swimlane is its first
  user, so any other flowchart-like type can plug in the same way.
- **Next, in this thread:** `layout/components.ts` and the class diagram.

## Sources

- Pele at the pin: [`src/layout/lanes.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/layout/lanes.ts),
  [`src/diagrams/swimlane/index.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/swimlane/index.ts),
  and the flowchart renderer it plugs into,
  [`src/diagrams/flowchart/render.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/flowchart/render.ts),
  read for this step.
- The code of this step: [`src/nimaki/layout/lanes.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/layout/lanes.nim),
  [`src/nimaki/diagrams/swimlane/index.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/diagrams/swimlane/index.nim),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
