## devlog: 12 Nov 2026 R | States and regions: the state diagram | nimaki draws Mermaid's state diagrams byte for byte as Pele does: composite states, concurrent regions, forks, choices and notes, on the compound layout that flowchart brought.
## kind: port
import std/[os, strformat, strutils, json, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/diagrams/state/[db, parser, types]

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var row: JsonNode
for r in difftest["types"]:
  if r["type"].getStr == "state": row = r
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["state"]

proc nimLines(dir: string): int =
  for path in walkDirRec(repoDir / dir):
    if path.endsWith(".nim"): result += readFile(path).countLines

let stateLines = nimLines("src/nimaki/diagrams/state")

nbText: &"""
## The findings, first

- **nimaki draws state diagrams.** All {row["cases"].getInt} state cases of the corpus come out
  identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} generated ones
  ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages), on every run of CI. Before merging, 9,000 more on three other seeds agreed too.
- **It is {stateLines} lines of Nim**, in eight files, one for each TypeScript file of
  `src/diagrams/state/`. Nothing shared had to change: the compound layout, the edges and the
  labels ported with flowchart were enough.
- **It matched on the first run.** Once it compiled, the referee found no difference, and the new
  state fuzzer found none either. The care went into the places where Pele's JavaScript shares and
  changes objects in place, which the port has to share and change in the same way.

## What a state diagram is

A state diagram describes something that is always in exactly one *state*, and the *transitions*
that move it from one state to another: a door is open or closed, an order is new, paid, shipped.
Mermaid writes a transition as an arrow, with an optional label after a colon. `[*]` is the start
when an arrow leaves it and the end when one arrives. A state can hold a diagram of its own (a
*composite* state), and a composite can be cut by `--` into *regions* that run side by side, each in
a state of its own at the same time. `<<fork>>` and `<<join>>` split and merge the flow, `<<choice>>`
picks one way, and notes sit beside a state:
"""

let stateText = """stateDiagram-v2
  [*] --> Idle
  Idle --> Working : start
  state Working {
    [*] --> Fetch
    Fetch --> Parse
    --
    [*] --> Measure
  }
  state check <<choice>>
  Working --> check
  check --> Done : ok
  check --> Idle : retry
  note right of Idle : waiting for input
  Done --> [*]
"""

nbText: &"""
```mermaid
{stateText.strip}
```

Pele draws it, in Node, while this page is built:
"""

let fromPele = peleSvg(stateText)
nbSvg fromPele, "Pele 1.13.0, in Node."

nbText: "And nimaki, in the program that builds this page:"

nbCode:
  let fromNimaki = render(stateText).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "nimaki, in Nim. The same bytes."

nbText: """
## Four passes, from text to drawing

Pele draws a state diagram in four passes, and the port keeps them apart in the same files.

1. **Parse** (`lexer.ts`, `parser.ts`). The text becomes a tree of *statements*: a state, a
   relation between two states, a class, a style, a direction, a click. A composite state holds
   the statements between its braces, its *document*. Pele's lexer and parser follow Mermaid's
   Jison grammar, token for token, as flowchart's do, and the port follows them.
2. **Translate** (`db.ts`, Mermaid's *docTranslator*). Each `[*]` gets a name of its own, made from
   the composite or region it is in and whether it starts or ends a transition (`Working_start`),
   and each document split by `--` becomes one region per part.
3. **Gather** (`graph.ts`, Mermaid's *dataFetcher*). The tree is walked, and every state that is
   named anywhere becomes one node, whatever the number of times it is named; descriptions add
   up, classes and styles are applied, notes become nodes of their own with a dashed edge to their
   state.
4. **Draw** (`render.ts`). Each node gets a size and a kind (a box, a box with a description, the
   start dot, the end ring, a diamond, a bar, a note, a composite, a region), and the whole goes
   to the compound layout.

Here are the first two passes on a small diagram, run on this page with the port's parser. The
statements inside the composite come out as two regions, named after the dividers, and each `[*]`
inside has taken the name of its region:
"""

nbCode:
  let small = "stateDiagram-v2\n  [*] --> On\n  state On {\n    [*] --> A\n    --\n    [*] --> B\n  }\n"
  let sdb = newStateDb()
  discard parseState(small, sdb)
  proc show(doc: seq[Stmt], depth: int) =
    for s in doc:
      let pad = repeat("  ", depth)
      case s.stmt
      of skState:
        echo pad, "state ", s.id, (if s.kind != "default": " (" & s.kind & ")" else: "")
        if s.hasDoc: show(s.doc, depth + 1)
      of skRelation: echo pad, s.state1.id, " --> ", s.state2.id
      else: echo pad, s.stmt
  show(sdb.rootDoc, 0)

nbText: """
## What the layout is asked to do

The compound layout lays out groups inside groups, each in its own direction: that is what
composite states and regions are. Pele's renderer asks a few more things of it, with tricks that
are worth knowing because they decide where everything lands:

- **The order of appearance.** States are numbered in the order the transitions first mention
  them, not the order they are declared, and start states come first at every level. A state
  declared at the top of the text, and used last, does not end up at the top of the drawing.
- **Unseen groups.** A note goes beside its state, across the flow. Pele puts the state and its
  notes in an invisible group that runs across, so the note never disturbs the state's
  transitions. A composite with transitions to itself gets one too, which leaves room for the
  loops and their labels.
- **Anchors.** A transition from a composite to a state inside it cannot be an edge of the layout
  between a group and its own member. Pele adds an invisible point just inside the composite,
  lays out the edge from there, and draws the last stretch on to the composite's border.
- **Rings.** A composite can be named inside another that is named inside it. Mermaid accepts
  that, and the parents then form a ring with no way in from the top. Pele moves one member of
  each ring to the top, which leaves a tree; so does the port.
- **Titles out of the way.** A composite's title sits in the middle of its title bar, or to the
  left or right of it if an edge comes in from above at that point.

## How it was ported

The rule of the port is to translate, not to improve
([decision 0002](../../decisions/#0002-this-is-a-port-not-a-rewrite)). The state type is
JavaScript at its most JavaScript: the statements are plain objects that the parser, the
translator and the gatherer all hold and change. The port had to keep every one of those changes.
"""

nbNote """
- **Shared, changing statements.** The parser adds a composite to its parent's document and only
  then fills its own; the translator renames `[*]` in place, and the gatherer reads the new name
  through every relation that holds the statement. In the port a statement is one `ref object`
  with a tag (`Stmt`), so every holder sees each change, as in JavaScript.
- **Keys that are there, and keys that are not.** When a state is named twice, Pele merges the
  second node into the first with `Object.assign`, which copies only the keys the second object
  has. A missing key and a key set to `undefined` are different things there. The port keeps a
  flag where that matters (`hasColorIndex`), and an `Option` where a value can be absent.
- **A description is a string or a list.** Mermaid's statements keep a description as one string,
  and turn it into a list when a second one comes. The port keeps the two forms apart
  (`dkText`, `dkList`), so the drawing knows which it had, as Pele's does with `Array.isArray`.
- **Regular expressions** became small scanners, each with the pattern beside it; the one that
  strips Mermaid's class names (`statediagram-state`, `-cluster`, `-cluster-alt`, `-note`) has to
  try `cluster-alt` before `cluster`, as the pattern does.
""", nkNim, "What changed in translation"

nbText: """
A state diagram that runs across turns to run down a narrow screen, as flowcharts do. Here it is
for a phone 390 pixels wide:
"""

let across = """stateDiagram-v2
  direction LR
  [*] --> Draft
  Draft --> Review : submit
  Review --> Draft : changes
  Review --> Merged : approve
  Merged --> [*]
"""

nbCode:
  var phone: RenderOptions
  phone.maxWidth = some(390.0)
  let down = render(across, phone)
  echo "width ", down.width, ", identical to Pele's: ", down.svg == peleSvg(across, %*{"maxWidth": 390})

nbSvg down.svg, "A state diagram that runs across, turned to run down a phone."

nbText: """
## The fuzzer, for state diagrams

`tools/fuzz.nim` learned the state grammar: transitions with and without labels, `[*]` on either
side, composites three deep with their own directions and `--` regions, forks, joins and choices,
descriptions given with `state "..." as X` and with `X : ...`, notes on one line and on several,
floating notes, `classDef`, `class`, `:::` on a transition, `style`, `click` with quoted and doubly
quoted strings, transitions to the same state, accessibility lines, `hide empty description`,
`scale`, front matter with the spacing and curve options, and broken lines on purpose. About a
quarter of its inputs are errors. CI runs 5,000 on every pull request:
"""

nbCode:
  echo "fuzz: state, seed ", fuzz["seed"].getInt, ", ", fuzz["cases"].getInt, " cases: ",
    fuzz["identical"].getInt, " identical, ", fuzz["different"].getInt, " different"

nbNote """
The state corpus, 5,000 generated state diagrams on seed 1, and 9,000 more on seeds 2 to 4:
identical. The whole corpus, every ported type: no difference.
""", nkDone, "Checked"

nbNote """
- Mermaid's older state database, which numbers each `[*]` instead of naming it after its
  composite, is not ported: Pele uses the newer one for both `stateDiagram` and
  `stateDiagram-v2`, and so does nimaki.
- Every file is `draft` until a second reading against the TypeScript
  ([decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)).
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **State is done** on the [roadmap](../../roadmap/) and the [coverage map](../../coverage/).
- **The compound layout has its second user**, and it needed no change. ER, requirement, use case
  and agentflow use it too, and come next in the same thread.

## Sources

- Pele at the pin: [`src/diagrams/state/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/state)
  (`lexer.ts`, `parser.ts`, `tokens.ts`, `types.ts`, `db.ts`, `graph.ts`, `render.ts`, `index.ts`), read for this step.
- [Mermaid's state diagram syntax](https://mermaid.js.org/syntax/stateDiagram.html).
- The code of this step: [`src/nimaki/diagrams/state/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/state),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
