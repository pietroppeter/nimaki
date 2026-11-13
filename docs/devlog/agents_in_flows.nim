## devlog: 13 Nov 2026 E | Agents in flows | nimaki draws Mermaid's agentflow diagrams byte for byte as Pele does: a flowchart that knows what each node is, colours it by kind, folds flows away, and reads YAML that block YAML would refuse.
## kind: port
import std/[os, strformat, strutils, json]
import nimib
import ../blocks, ../site, ../pele
import nimaki

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var row: JsonNode
for r in difftest["types"]:
  if r["type"].getStr == "agentflow": row = r
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["agentflow"]

proc nimLines(dir: string): int =
  for path in walkDirRec(repoDir / dir):
    if path.endsWith(".nim"): result += readFile(path).countLines

let afLines = nimLines("src/nimaki/diagrams/agentflow")

nbText: &"""
## The findings, first

- **nimaki draws agentflow diagrams.** All {row["cases"].getInt} agentflow cases of the corpus come
  out identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} generated
  ones ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages), on every run of CI. Before merging, 9,000 more on three other seeds agreed too.
- **It is {afLines} lines of Nim**, one file for each TypeScript file of
  `src/diagrams/agentflow/` but one (`diagnostics.ts`, which only names warnings).
- **It matched on the first run.** Agentflow is a flowchart underneath: the same kind of lexer
  and parser, the same compound layout, the same shapes. What it adds sits on top, and the port
  of the flowchart had already done the hard part.
- **This finishes the compound-layout types**: flowchart, state, ER, requirement, use case and
  agentflow all draw through the layout that the flowchart brought.

## What an agentflow is

An *agentflow* is Mermaid's diagram for software agents: programs, often driven by a language
model, that take a task, call tools, read documents and decide what to do next. It is written
like a flowchart (`a --> b`), but each node says what it is with a shape that has a meaning:
a `task`, a `tool` the agent calls, an `input`, a `decision`, a `refdoc` it reads, an `action`
on the world. A `flow` is a group: one agent and the steps it owns. A `connector` stands for an
outside service. Three kinds of line say three things: `-->` is the next step, `--x` is what
happens on failure, and the dotted `-.-` is a reference, "this step reads that".
"""

let afText = """agentflow-beta LR
  connector github["GitHub API"]
  brief["Release brief"]@{ shape: input }
  flow writer["Drafting Agent"]
    draft["Draft the notes"]@{ shape: task }
    lookup["changelog_search"]@{ shape: tool }
    guide["Tone of voice"]@{ shape: refdoc }
    ok["Good enough?"]@{ shape: decision }
    draft --> lookup
    draft -.- guide
    draft --> ok
  end
  flow archive["Archive"]
    old["Old notes"]
    older["Older notes"]
  end
  archive@{ view: "collapsed" }
  brief --> draft
  lookup --> github
  ok -- no --x draft
  ok -- yes --> publish["Publish"]@{ shape: action }
  draft -.- archive
"""

nbText: &"""
```mermaid
{afText.strip}
```

Pele draws it, in Node, while this page is built:
"""

let fromPele = peleSvg(afText)
nbSvg fromPele, "Pele 1.13.0, in Node."

nbText: "And nimaki, in the program that builds this page:"

nbCode:
  let fromNimaki = render(afText).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "nimaki, in Nim. The same bytes."

nbText: """
## What agentflow adds to a flowchart

**Colour by kind.** A flowchart draws every node alike; an agentflow colours each by what it is.
The palette has eight slots (the theme's series colours), and each kind has a fixed one: tool 0,
task 1, decision 2, input 3, refdoc 4, connector 5, action 6. Fixed slots mean that adding a node
never recolours the others. Flows take the slots above the kinds, counted in the order they were
written, so a flow is never the colour of a node inside it.

**Fewer shapes.** Agentflow keeps six of the flowchart's shapes and gives them names
(`tool` is the flowchart's `subroutine`, `refdoc` its `lin-doc`). A shape Mermaid removed from
agentflow, or one it never had, is drawn as a rounded box instead, and Pele notes the change
on the model. A name that is not a shape at all, or is not lowercase, is an error:
"""

nbCode:
  for line in ["a@{ shape: Task }", "a@{ shape: nope }", "a@{ shape: [1, 2] }"]:
    try:
      discard render("agentflow-beta\n  " & line & "\n")
    except PeleError as e:
      echo line.alignLeft(22), " ", e.msg

nbText: """
**Folding a flow away.** `view: "collapsed"` turns a flow into a single box with three dots,
and every line that went to something inside it now goes to the box. Flows nest, and folded flows
can sit inside folded flows, so Pele walks each one and sends everything inside to the outermost
folded flow around it.

**Lines to the box around you.** In the example, nothing draws a line from a node to the flow
that holds it, but an agentflow can (`draft --> writer`, from inside `writer`). The layout has no
place for such a line, because a group is not a node of the layered layout: Pele leaves it out of
the layout and draws it afterwards, straight from the node to the flow's border, along the flow's
direction, or to one side if another node is in the way.

**`global`.** A `global ... end` block holds nodes that belong to no flow, even when a flow
lists them, such as a document every agent reads.

## YAML that block YAML refuses

The `@{ ... }` after a node is YAML. On one line, `@{ shape: tool, label: "x" }` is read as a
YAML flow mapping: Pele wraps it in braces. Written over several lines, it is block YAML, and
there a comma at the end of a line is part of the value. People write the commas anyway, so when
the YAML does not parse, Pele removes each comma that ends a line (but not one inside quotes,
brackets or a block scalar) and tries once more. The port does the same:
"""

nbCode:
  let multi = "agentflow-beta\n  a@{\n    label: \"Several lines\",\n    shape: tool,\n  }\n"
  echo "renders: ", render(multi).svg.len > 0
  try:
    discard render("agentflow-beta\n  a@{ label: [ }\n")
  except PeleError as e:
    echo e.msg

nbNote """
- **Why one try more.** The first error is the one reported, with its line and column in the
  text: the retry only rescues texts, it never changes a message.
- **What is left out.** Pele also builds a *semantic model* of the diagram (what each node means,
  without the drawing), records where each statement sits for editors, and collects warnings.
  Nothing it draws reads them, so the port leaves them out and says so in `types.nim`.
- **One graph per model.** Pele keeps the graph it builds in a `WeakMap` keyed by the model, so
  that measuring and drawing build it once. The port keeps it in a field of the model.
- **Keys from a string.** Pele spreads a metadata block into an object whatever it parsed to, so a
  block that is a plain string adds one key per character. Nothing drawn reads those keys; the
  port adds them too.
""", nkNim, "What changed in translation"

nbText: """
## The fuzzer

`tools/fuzz.nim` learned agentflow: nodes with every kind of shape, including removed, unknown and
capitalised ones; flows, bare flows and `global` blocks, nested; connectors; metadata on one line
and on several, with and without commas, valid and broken; folded flows; lines inside and across
flows and lines to the flow around them; labels, ids on edges, self-loops; `classDef`, `class`,
`style`, `linkStyle`, `click`, comments, accessibility lines and front matter with agentflow and
flowchart settings. Mermaid's agentflow lexer takes fewer arrows than the flowchart's (`-.->` and
`==>` are errors here), so the generator mostly writes the three it takes, and the others on
purpose. CI runs 5,000 cases on every pull request:
"""

nbCode:
  echo "fuzz: agentflow, seed ", fuzz["seed"].getInt, ", ", fuzz["cases"].getInt, " cases: ",
    fuzz["identical"].getInt, " identical, ", fuzz["different"].getInt, " different"

nbNote """
The agentflow corpus, 5,000 generated diagrams on seed 1 and 9,000 more on seeds 2 to 4:
identical. The whole corpus, every ported type: no difference.
""", nkDone, "Checked"

nbNote """
- Every file is `draft` until a second reading against the TypeScript
  ([decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)).
- Few generated diagrams fold a flow (about one in a hundred of those that draw), so folding is
  the part the fuzzer checks least.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Agentflow is done** on the [roadmap](../../roadmap/) and the
  [coverage map](../../coverage/), and with it every type that draws through the compound layout.
- This thread takes the next unclaimed step of the roadmap.

## Sources

- Pele at the pin: [`src/diagrams/agentflow/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/agentflow),
  read for this step.
- The code of this step: [`src/nimaki/diagrams/agentflow/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/agentflow),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
- The earlier post on the layout it uses: [Layered layout and flowchart](../layered-layout-and-flowchart/).
"""

nbSave
