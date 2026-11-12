## devlog: 12 Nov 2026 N | Boxes in layers: the layered layout and flowchart | nimaki draws Mermaid's flowcharts byte for byte as Pele does, on a port of the layout engine most of Pele's diagrams are built on: ranks, orders, positions and routes.
## kind: port
import std/[os, strformat, strutils, json]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/layout/[layered, compound]

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var row: JsonNode
for r in difftest["types"]:
  if r["type"].getStr == "flowchart": row = r
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["flowchart"]

proc nimLines(paths: openArray[string]): int =
  for p in paths:
    let full = repoDir / p
    if dirExists(full):
      for path in walkDirRec(full):
        if path.endsWith(".nim"): result += readFile(path).countLines
    else: result += readFile(full).countLines

let layoutLines = nimLines(["src/nimaki/layout"])
let flowLines = nimLines(["src/nimaki/diagrams/flowchart"])
let sharedLines = nimLines(["src/nimaki/svg/shapes.nim", "src/nimaki/svg/edges.nim", "src/nimaki/svg/cluster.nim",
                            "src/nimaki/svg/title.nim", "src/nimaki/util/url.nim", "src/nimaki/util/unicode.nim"])

nbText: &"""
## The findings, first

- **nimaki draws flowcharts.** All {row["cases"].getInt} flowchart cases of the corpus come out
  identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} generated ones
  ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages), on every run of CI. Before merging, 7,000 more on three other seeds agreed too.
- **The layout engine is ported.** `layered.ts` and `compound.ts`, the part of Pele that decides
  where the boxes and lines of a graph go, are {layoutLines} lines of Nim. Pele's own 31 tests of
  that engine run on the port, unchanged in what they check, and pass.
- **The shared drawing parts came along.** The 53 documented node shapes, the edges and their arrowheads, the
  boxes of subgraphs, titles and safe links ({sharedLines} lines) are written once and will serve
  state, class, ER, requirement, use case and agentflow diagrams too.
- **It matched on the first full run.** Once the flowchart code compiled, the referee found no
  difference. One crash came later, found by the new flowchart fuzzer, where JavaScript
  reads past the end of an array and gets `undefined` where Nim stops.

## A flowchart, twice

A flowchart is boxes joined by arrows. Mermaid's text names each box once, with its shape in the
brackets around its label, and then the arrows:
"""

let flowText = """flowchart TD
  start([Mermaid text]) --> lex[Lexer]
  lex --> parse[Parser]
  parse --> layout{Layout}
  subgraph engine [The layered layout]
    layout --> ranks[Ranks]
    ranks --> order[Order]
    order --> place[Positions]
  end
  place --> svg[(SVG)]
  layout -. no edges .-> svg
"""

nbText: &"""
```mermaid
{flowText.strip}
```

Pele draws it, in Node, while this page is built:
"""

let fromPele = peleSvg(flowText)
nbSvg fromPele, "Pele 1.13.0, in Node."

nbText: "And nimaki, in the program that builds this page:"

nbCode:
  let fromNimaki = render(flowText).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "nimaki, in Nim. The same bytes."

nbText: """
## What a layout engine does

Parsing a flowchart gives a *graph*: a list of nodes, each with a width and a height (from its
label, measured), and a list of edges, each from one node to another. Nothing says where anything
goes. A *layout* gives every node a position and every edge a route, so that the drawing reads
well: arrows mostly point the same way, few lines cross, nothing overlaps.

There are many ways to lay out a graph. Mermaid, Graphviz's `dot`, dagre and ELK all use the same
family for flowcharts: the *layered* layout, described by Sugiyama, Tagawa and Toda in 1981. It
puts the nodes in rows (*layers*, or *ranks*), the way a family tree is drawn, and works in four
stages. Pele's `layered.ts` follows them, in its own way:

1. **Break the cycles.** Arrows should all point down. A cycle (A to B to C and back to A) makes
   that impossible, so some edges are turned round for the layout and drawn the right way at the
   end. Pele walks the graph depth first, in the order the text declares it, and reverses each
   edge that leads back to a node on the current path (`orient`).
2. **Give each node a rank.** A node goes at least one rank below every node that points to it.
   Pele starts from the longest path, which leaves loosely joined nodes far from their
   neighbours, then moves each node towards the side where it has more edges (`rank`). An edge
   that skips ranks is cut into pieces, with an invisible *dummy* node in each rank it crosses,
   so that every piece joins two neighbouring ranks.
3. **Order each rank.** Within a rank, the order of the nodes decides how many lines cross.
   Finding the order with the fewest crossings is NP-hard, so everyone uses heuristics: sweep
   down and up the ranks, and sort each one by the *barycenter* (the average position) of each
   node's neighbours in the rank before, then try swapping neighbours (`reduceCrossings`).
4. **Give each node a place across the rank**, so that edges are as straight as can be and nodes
   keep their distance. Pele uses the method of Brandes and Köpf (2001): line up chains of nodes
   in four ways (up-left, up-right, down-left, down-right) and take the balance of the four
   (`position`).

Then the routes: each edge becomes a list of points, from the side of one node, through the dummy
nodes, to the side of the other, and the drawing turns those points into curves.

Here are the stages on a small graph, run on this page. Four nodes, and five edges, one of which
(3 to 0) closes a cycle:
"""

nbCode:
  var nodes: seq[LNode]
  for i in 0 ..< 4: nodes.add lnode(60, 30)
  let edges = @[ledge(0, 1), ledge(0, 2), ledge(1, 3), ledge(2, 3), ledge(3, 0)]
  let laid = layered(nodes, edges, LayeredOptions(nodeSep: 40, edgeSep: 16, rankSep: 48, portSep: 20))
  for i, n in nodes:
    echo "node ", i, ": rank ", n.rank, ", centre (", n.x, ", ", n.y, ")"
  echo "edge 3 to 0 turned round for the layout: ", edges[4].reversed
  echo "size ", laid.width, " by ", laid.height, ", crossings ", laid.crossings

nbText: """
Node 0 is at the top, 1 and 2 share the second rank side by side, 3 is below them; the edge back
up was reversed so that it could be ranked like the others.

## Groups: the compound layout

A flowchart can put nodes in a `subgraph`, drawn as a box around them, and a subgraph can sit
inside another, and run in its own direction. The layered layout knows nothing of boxes, so
`compound.ts` wraps it: it lays out each group on its own, innermost first, in the group's own
direction, then places the group in its parent as a single box of that size. An edge that crosses
a group's border passes through a *port*, a point on the side of the box that faces the edge's
other end. Then everything is shifted to where its parents ended up.

`compoundLayout` takes nodes that may have a parent:
"""

nbCode:
  let group = cnode(0, 0)
  group.isGroup = true
  group.padX = 20
  group.padTop = 30
  group.padBottom = 20
  let cnodes = @[group, cnode(60, 30, parent = 0), cnode(60, 30, parent = 0), cnode(60, 30)]
  for i, c in cnodes: c.seq = float(i)
  let cedges = @[CEdge(src: 1, dst: 2, minlen: 1), CEdge(src: 2, dst: 3, minlen: 1)]
  let size = compoundLayout(cnodes, cedges, "LR", LayeredOptions(nodeSep: 40, edgeSep: 16, rankSep: 48, portSep: 20))
  echo "the group: ", cnodes[0].w, " by ", cnodes[0].h, " at (", cnodes[0].x, ", ", cnodes[0].y, ")"
  echo "the edge out of it has ", cedges[1].route.len div 3, " points"
  echo "the drawing: ", size.width, " by ", size.height

nbText: """
Pele's layout does much more than the textbook: it lets the edges on one side of a node spread
along it, keeps twin edges apart, gives labels a rank of their own, turns long edges at levels of
their own so that they do not run on top of each other, routes edges at right angles on *tracks*
when the curve style asks for steps, and counts where the drawn curves really cross. Each of
those is a comment and a few dozen lines in `layered.ts`, and each came over line by line.

## How it was ported

The rule of the port is to translate, not to improve
([decision 0002](../../decisions/#0002-this-is-a-port-not-a-rewrite)). `layered.ts` is written for
speed: the graph is kept in typed arrays (`Int32Array`, `Float64Array`), indexed by node and edge
number, and the stages are closures that share them. In the port the arrays are `seq`s, shared in
one object, and the closures are procs. A few things needed care:
"""

nbNote """
- **Sorting.** A JavaScript comparator often reads `a.rank - b.rank || a.seq - b.seq`: the second
  test only when the first is zero. The port writes it with `orElse`. JavaScript's sort is stable,
  and so is Nim's, so ties keep their order, which the byte-identical output depends on.
- **Reading past the end.** `route[0]` of an empty route is `undefined` in JavaScript, and
  arithmetic on it gives NaN; in Nim it stops the program. The fuzzer found one such read, for an
  edge between nodes the layout had left out; the port now reads NaN there, as Pele does.
- **Closures and `var`.** A Nim closure cannot capture a `var` parameter. Where a TypeScript inner
  function changes an array its outer function was given, the port takes the array's address once
  and reads it through a template.
- **Same values, by the rules of `Object.is`.** `compound.ts` caches the layout of each group and
  reuses it when nothing changed; the comparison treats NaN as equal to itself and 0 as different
  from -0, and so does the port's.
""", nkNim, "What changed in translation"

nbText: """
## The flowchart itself

The flowchart type is the largest of Pele's older, Jison-style types: a lexer of 955 lines that
works through Mermaid's many link forms (`-->`, `-.->`, `==>`, `--o`, `<-->`, `~~~`, `-- text -->`)
and bracket shapes, a parser, a *database* that collects nodes, edges, subgraphs, classes and
styles, and a renderer that measures labels, calls the layout and writes SVG. Its regular
expressions are hand-written scanners here, each with the pattern beside it, as the porting guide
asks; the backtracking of a few needed thought (`}\s*\n` matches up to the *last* line break of the
spaces after a brace, not the first).

A flowchart that runs across is wide. As timeline does, it turns to run down when the host says it
has a narrow screen and the drawing would not fit (`turnToFit`). Here it is for a phone 390 pixels
wide:
"""

let across = """flowchart LR
  idea[An idea] --> draft[A draft] --> review{Reviewed?}
  review -->|yes| merge[Merged]
  review -->|no| draft
"""

nbCode:
  var phone: RenderOptions
  phone.maxWidth = some(390.0)
  let down = render(across, phone)
  echo "width ", down.width, ", identical to Pele's: ", down.svg == peleSvg(across, %*{"maxWidth": 390})

nbSvg down.svg, "A flowchart that runs across, turned to run down a phone."

nbText: """
## The fuzzer, for flowcharts

`tools/fuzz.nim` learned a third grammar. It writes flowcharts from lists of ids, labels (with
Markdown, tags, entities, icons, long words, scripts other than Latin), every bracket shape, every
link form, `@{ shape: ... }` metadata with the documented shape names and a few wrong ones,
icons and images, subgraphs three deep with their own directions, `classDef`, `class`, `style`,
`linkStyle` with curves, `click` with links and callbacks, comments, accessibility lines, front
matter with spacing and curve options, and broken lines on purpose. About a third of its inputs
are errors. CI runs 5,000 on every pull request:
"""

nbCode:
  echo "fuzz: flowchart, seed ", fuzz["seed"].getInt, ", ", fuzz["cases"].getInt, " cases: ",
    fuzz["identical"].getInt, " identical, ", fuzz["different"].getInt, " different"

nbNote """
The flowchart corpus (383 cases), 5,000 generated flowcharts, and 7,000
more on seeds 2 to 4: identical. Pele's 31 layout tests (`tests/layout/layered.test.ts` and
`compound.test.ts`), ported to `tests/test_layout.nim`: all pass. Pie and timeline still identical.
""", nkDone, "Checked"

nbNote """
- `lanes.ts` (swimlanes) and `components.ts` (class diagrams) are not ported yet: flowchart does
  not use them. They come with the types that do.
- The `FlowVariant` hook (a diagram type that is a flowchart with another layout) is ported, but
  nothing uses it yet; swimlane will.
- Links to http(s) addresses are checked with a subset of the WHATWG URL rules; international
  domain names are not converted to Punycode. No case of the corpus or the fuzzer has one.
- Every file is `draft` until a second reading against the TypeScript
  ([decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)).
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Layered layout and flowchart are done** on the [roadmap](../../roadmap/) and the
  [coverage map](../../coverage/).
- **Most of what is left can run in parallel.** State, ER, requirement, use case and agentflow
  need only the compound layout and the shared shapes and edges, which are now ported. Sequence,
  block, C4, architecture, Wardley, Ishikawa and Cynefin need the edges and shapes but no layout.
  Swimlane needs `lanes.ts`, class needs `components.ts`.
- **`svg/edges.nim` is whole.** Timeline's partial port (the arrow marker) is replaced by the full
  file, under the same names.

## Sources

- Pele at the pin: [`src/layout/layered.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/layout/layered.ts),
  [`src/layout/compound.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/layout/compound.ts),
  [`src/diagrams/flowchart/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/flowchart),
  [`src/svg/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/svg)
  (`shapes.ts`, `edges.ts`, `cluster.ts`, `title.ts`),
  [`src/util/url.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/util/url.ts),
  and [`tests/layout/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/layout),
  read for this step.
- K. Sugiyama, S. Tagawa and M. Toda, *Methods for visual understanding of hierarchical system
  structures*, IEEE Transactions on Systems, Man, and Cybernetics, 1981
  ([doi:10.1109/TSMC.1981.4308636](https://doi.org/10.1109/TSMC.1981.4308636)). Not read for this
  post: the four stages are as Pele's code and comments describe them.
- U. Brandes and B. Köpf, *Fast and Simple Horizontal Coordinate Assignment*, Graph Drawing 2001
  ([doi:10.1007/3-540-45848-4_3](https://doi.org/10.1007/3-540-45848-4_3)), named in Pele's
  `position`. Not read for this post either.
- [Mermaid's flowchart syntax](https://mermaid.js.org/syntax/flowchart.html).
- The code of this step: [`src/nimaki/layout/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/layout),
  [`src/nimaki/diagrams/flowchart/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/flowchart),
  [`tests/test_layout.nim`](https://github.com/pietroppeter/nimaki/blob/main/tests/test_layout.nim),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
