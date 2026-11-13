## devlog: 12 Nov 2026 S | Lifelines and messages: the sequence diagram | nimaki draws Mermaid's sequence diagrams byte for byte as Pele does: who talks to whom and in what order, laid out with no layout engine at all, and a JSON.parse as strict as JavaScript's.
## kind: port
import std/[os, strformat, strutils, json, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/js
import nimaki/diagrams/sequence/[lexer, tokens, db, parser, types, colors]

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var row: JsonNode
for r in difftest["types"]:
  if r["type"].getStr == "sequence": row = r
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["sequence"]

proc nimLines(dir: string): int =
  for path in walkDirRec(repoDir / dir):
    if path.endsWith(".nim"): result += readFile(path).countLines
proc tsLines(dir: string): int =
  for path in walkDirRec(repoDir / "reference" / "pele" / dir):
    if path.endsWith(".ts"): result += readFile(path).countLines

let seqNim = nimLines("src/nimaki/diagrams/sequence")
let seqTs = tsLines("src/diagrams/sequence")

nbText: &"""
## The findings, first

- **nimaki draws sequence diagrams.** All {row["cases"].getInt} sequence cases of the corpus come
  out identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} generated ones
  ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages) on every run of CI. Before merging, 10,000 more on four other seeds agreed too.
- **No layout engine.** A sequence diagram puts its participants in a row and its messages in
  the order they are written, so Pele lays it out by itself, in two passes: across, then down.
  The {seqTs} lines of TypeScript in `src/diagrams/sequence/` became {seqNim} lines of Nim, and
  nothing new was needed below them.
- **A strict `JSON.parse`.** A participant can carry JSON (`properties A: {{"class": "x"}}`).
  Nim's `parseJson` reads text JavaScript rejects (comments, trailing commas, `01`), so a
  diagram Pele draws one way nimaki would have drawn another. `js.nim` now has `jsonParse`, as
  strict as JavaScript's and checked against Node; the `%%{{init}}%%` directive uses it too.
- **The lexer counts in UTF-16 where it matters.** A participant named with an emoji, or a title
  after an ideographic space, is read as JavaScript reads it.

## What a sequence diagram is

A *sequence diagram* shows a conversation: who talks to whom, and in what order. Each participant
gets a column and a vertical *lifeline*; time runs down the page; each message is an arrow from
one lifeline to another. They come from UML, where they describe how the objects of a program
call each other, and they are the second most common diagram in the corpus after flowcharts.
"""

let firstText = """sequenceDiagram
  participant B as Browser
  participant S as Server
  actor U as You
  U->>B: Open the page
  B->>+S: GET /page
  S-->>-B: 200 OK
  B-->>U: Show it
"""

nbText: &"""
```mermaid
{firstText.strip}
```
"""

nbCode:
  let fromPele = peleSvg(firstText)
  let fromNimaki = render(firstText).svg
  echo "identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "A first sequence diagram, drawn by nimaki; Pele draws the same bytes."

nbText: """
The `+` after an arrow *activates* the participant it points at (the thin box on the server's
lifeline: it is busy), and the `-` ends it. `->>` is a solid line with an arrowhead, `-->>` a
dotted one. Mermaid has 26 kinds of arrow, and Pele draws them all.

## Reading the text

The port follows the path every diagram takes ([*Drawing a diagram from scratch*](../drawing-a-diagram/)
explains it): a *lexer* cuts the text into tokens, a *parser* checks their order and builds a
model, and a renderer draws the model. Sequence's lexer is one hand-written loop that ports the
rules of Mermaid's Jison grammar, like [timeline's](../timeline/), with a twist: it changes
*state*. After `participant` comes a name; after `as`, the rest of the line is a label, spaces
and all; after `loop`, it is a text; after `@{`, a block of YAML. Here is what it makes of two
lines:
"""

nbCode:
  let line = "sequenceDiagram\nparticipant API as Our API server\nAPI->>+DB: query\n"
  let toks = tokenize(line)
  for k in 0 ..< toks.types.len:
    echo TOKEN_NAMES[toks.types[k]].alignLeft(14), " ", escapeJson(toks.texts[k])

nbText: """
After `participant` the lexer is in its *name* state: it reads `API`, sees ` as `, and switches
to its *rest of the line* state, so `Our API server` is one token, spaces and all. In the message
line, `API` and `DB` are actors, `->>` is `SOLID_ARROW`, `+` is a token of its own, and the text after the
colon is `TXT`.

The parser then builds the nested lists of statements Mermaid's grammar builds, one list per
block (`loop`, `alt`, `par`...), and `apply` walks them in order, filling the model: the
participants, and a single list of *messages*, where the start and end of every block, every
activation and every note is a message too. The model of the diagram above:
"""

nbCode:
  let model = newSeqDb()
  parseSequence(firstText, model)
  for m in model.messages:
    echo m.id.alignLeft(3), " kind ", ($m.kind).alignLeft(3), m.start.get("-").alignLeft(3),
      "→ ", m.to.get("-").alignLeft(3), " ", escapeJson(m.message)

nbText: """
Kind 0 is a solid arrow, 1 a dotted one, 17 and 18 the start and end of an activation (the
numbers are Mermaid's, kept by Pele so its tests can compare with Mermaid's). The renderer reads
this list from top to bottom.

## A layout with no layout engine

[Flowcharts](../layered-layout-and-flowchart/) need a layout engine, because nothing in the text
says where a box goes. A sequence diagram says it all: participants go left to right in the
order they appear, messages top to bottom in the order they are written. What is left to decide
is *how far apart*, and Pele answers it in two passes.

**Across.** Every message and note says how far apart the lifelines it touches must be: wide
enough for its text, plus some padding. Pele collects these *needs*, then sets the gap between
each pair of neighbours to the largest need of that pair (and at least the width of the two
participant boxes and a margin). A message that jumps over a participant spreads what it still
lacks equally across the gaps it crosses. Here a long message from A to C widens both gaps:
"""

let spreadText = """sequenceDiagram
  participant A
  participant B
  participant C
  A->>B: hi
  A->>C: a message that is long enough to need more room than two boxes
"""

nbCode:
  proc lifelines(svg: string): seq[string] =
    ## The x of each lifeline, read back from the SVG.
    var at = svg.find("class=\"pele-lifeline\"")
    while at >= 0:
      let d = svg.find("d=\"M", at) + 4
      result.add svg[d ..< svg.find(',', d)]
      at = svg.find("class=\"pele-lifeline\"", d)
  let spread = render(spreadText).svg
  echo "lifelines at x = ", lifelines(spread).join(", ")
  echo "identical to Pele's: ", spread == peleSvg(spreadText)

nbSvg spread, "The long message needs more room than the boxes; its two gaps share what it lacks."

nbText: """
The gaps come out equal: the one message that needed more than the boxes gave each gap half of
what it lacked. Pele handles the short spans first, so that a long span only adds what is still
missing after its inner gaps have grown.

**Down.** The second pass walks the messages from top to bottom with a pen, `y`, and draws as it
goes: each arrow moves the pen down by its text's height and a gap; a block (`loop`, `alt`) opens
a frame with a tab for its name and closes it further down; an activation remembers where it
started and becomes a box when it ends; a participant that is *created* by a message has its box
drawn where the message arrives, and one that is *destroyed* gets a cross where its lifeline
stops. The frames are wide enough for what they hold, so their width is known only after the
first pass has placed everything inside; the two passes are why.
"""

let richText = """sequenceDiagram
  autonumber
  participant C as Client
  participant S as Server
  C->>S: Log in
  alt password is right
    S-->>C: Welcome
    create participant D as Session
    S->>D: Open
  else wrong password
    S-->>C: Try again
  end
  loop every minute
    C-)S: Ping
  end
  Note over C,S: The session is kept alive
  destroy D
  S-xD: Close
"""

nbText: &"""
```mermaid
{richText.strip}
```
"""

nbCode:
  let rich = render(richText).svg
  echo "identical to Pele's: ", rich == peleSvg(richText)

nbSvg rich, "Blocks, a note, numbers, and a participant created and destroyed: drawn by nimaki."

nbText: """
## On a phone

When the host says how much room it has (`maxWidth`) and the diagram does not fit, Pele draws it
again *tightly*: smaller margins, messages wrapped to the room each column can have, and long
words broken. If some message still wraps, it tries giving the columns that carry wrapped
messages the room that is left, first in equal shares, then in shares by need, and keeps the
spread only if fewer lines wrap. It is the longest function of the port (Pele's `draw`, about
550 lines), and the fuzzer gives it a `maxWidth` in a third of its cases.
"""

nbCode:
  let narrow = render(richText, RenderOptions(maxWidth: some(320.0)))
  echo "width at 320: ", narrow.width, " (natural: ", render(richText).width, ")"
  echo "identical to Pele's: ", narrow.svg == peleSvg(richText, %*{"maxWidth": 320})

nbSvg narrow.svg, "The same diagram, drawn for a host 320 pixels wide."

nbText: """
## What JavaScript hid this time

Three small things, each found by reading the TypeScript closely rather than by the referee, and
each now checked.
"""

nbNote """
`JSON.parse` is strict: no comments, no trailing comma, no leading zero, no `1.`, only the
escapes JSON defines. Nim's `std/json` accepts all of these. Sequence reads JSON in its actor
menus (`links`, `properties`; a `class` property becomes a CSS class of the participant), and the
core reads it in `%%{init: ...}%%`. Both now call `jsonParse` of `js.nim`, which a test compares
with Node on 42 texts. It keeps its containers on a stack, so a deeply nested value cannot
overflow Nim's call stack.
""", nkNim, "A strict JSON.parse"

nbCode:
  for text in ["{\"class\": \"warn\"}", "{\"class\": \"warn\",}", "{\"class\": \"warn\"} // note"]:
    let verdict = try: $jsonParse(text) except JsSyntaxError: "not JSON"
    echo text.alignLeft(28), " → ", verdict

nbNote """
A box's first word is a colour when it is one (`box Aqua Backend`). Pele checks the word against
the CSS colour names after `toLowerCase()`, which lowers more than ASCII: the Kelvin sign `K`
(U+212A) becomes a plain `k`, so `blac`+`K` is black. The port lowers with Nim's Unicode tables,
which agree.
""", nkNim, "toLowerCase is Unicode"

nbCode:
  echo isCssColor("blacK"), " ", isCssColor("Aqua"), " ", isCssColor("rgb(1 2 3 / 50%)"), " ", isCssColor("calc(1)")

nbNote """
The lexer reads with `charCodeAt`, one UTF-16 code unit at a time. Nim's strings are bytes, so the
port reads a whole character where the TypeScript's test can pass on one that is not ASCII (a
name, a space), and treats a character beyond U+FFFF as its first surrogate, which is what
`charCodeAt` sees. The `title` keyword drops six code units (`title` and its space) with
`substring(6)`; after an ideographic space that is six characters but eight bytes, so the port
uses `substringFrom`, which counts code units. The fuzzer writes both.
""", nkNim, "UTF-16 in the lexer"

nbText: &"""
## What this changes for the port

- **Sequence is done** on the [roadmap](../../roadmap/) and the [coverage map](../../coverage/).
  With flowchart, two of the four types diagrammari uses most are now in Nim.
- **`jsonParse` is the one `JSON.parse`.** The porting guide says so; the use case diagram, which
  Pele reads with its own JSON walker, will need it too.
- **Next, from the same thread:** block, C4, architecture, Wardley, Ishikawa and Cynefin, the
  types that need the shared shapes and edges but no layered layout. They are claimed on the
  roadmap.

## Sources

- Pele at the pin: [`src/diagrams/sequence/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/sequence)
  (`lexer.ts`, `parser.ts`, `db.ts`, `render.ts`, `actors.ts`, `colors.ts`, `types.ts`,
  `tokens.ts`), read whole for this step.
- [Mermaid's sequence diagram syntax](https://mermaid.js.org/syntax/sequenceDiagram.html), for
  what the arrows, blocks and actor menus mean.
- [ECMA-404, the JSON data interchange syntax](https://ecma-international.org/publications-and-standards/standards/ecma-404/),
  the grammar `jsonParse` follows. The test checks it against Node's `JSON.parse`, not against
  the standard's text.
- The code of this step: [`src/nimaki/diagrams/sequence/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/sequence),
  `jsonParse` in [`src/nimaki/js.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/js.nim),
  its test in [`tests/test_js.nim`](https://github.com/pietroppeter/nimaki/blob/main/tests/test_js.nim),
  and the sequence generator of [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
