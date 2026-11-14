## devlog: 14 Nov 2026 J | Every drawing a test | A block for the pages, nbMermaid, draws Mermaid text with nimaki, asks Pele for the same drawing, and fails the build when the two differ: every diagram on the site is now also a check of the port.
## kind: tooling
import std/[strformat, strutils, json]
import nimib
import ../blocks, ../pele
import nimaki

nbInit
nb.usePost()

const cafe = """flowchart LR
  A[Café] --> B[Menu]
  click A href "https://café.example/menu"
"""
var caught = ""
try: discard mermaidSvg(cafe)
except AssertionDefect as e: caught = e.msg
let firstLine = if caught.len > 0: caught.splitLines[0] else: ""

nbText: """
## The findings, first

- **One block to draw with.** `nbMermaid(text, caption, options)` in `docs/pele.nim` draws Mermaid
  text with nimaki, shows the drawing with its caption, and folds the text under it. A page needs
  one line per diagram, where the domain articles each wrote their own few.
- **Checked against Pele, every time.** The block also asks Pele, the pinned npm package run in
  Node, for the same drawing with the same options, and the build fails when the two are not the
  same bytes. A diagram on the site is a small test of the port.
- **In use** in the two domain articles, *What happens when you open a web page* and *A kitchen on
  a Friday night*, and under the live diagrams of the [Playground](../../playground/).
- **Free when nothing changes.** Pele's answers are kept for the run of the pages, so a page that
  already asked Pele for its diagrams (the domain articles compare them in a table) does not ask
  twice.

## Why a block

The first domain article, [*What happens when you open a web page*](../opening-a-web-page/),
drew ten diagrams. For each, the page called nimaki's `render`, showed the SVG, and wrote a fold
with the Mermaid text, in a little procedure of its own. The second article,
[*A kitchen on a Friday night*](../a-kitchen-on-friday-night/), copied that procedure. Both
articles said, in their lessons for the port, that the pages wanted a block for it. The rule of
these pages is that what is needed a second time becomes a block (the rule of
[AGENTS.md](../../agents/)).

The block could just draw. But each of those articles also asked Pele for the same drawings,
and counted how many were the same bytes. That count is what makes a diagram on the site worth
more than a picture: it says that the port, used for real, still draws exactly what Pele draws.
So the block does it every time, for every diagram, and a difference stops the build instead of
lowering a count.

## How a page uses it

A diagram is one line. The text is drawn for a phone-wide column, as the articles do:

```nim
nbMermaid "flowchart LR\n  A[Mermaid text] --> B[nimaki] --> C[SVG]\n",
  "Drawn by nimaki with nbMermaid...", %*{"maxWidth": 390}
```

and the page shows:
"""

nbMermaid "flowchart LR\n  A[Mermaid text] --> B[nimaki] --> C[SVG]\n",
  "Drawn by nimaki with nbMermaid, and the same bytes as Pele's: the build checked.",
  %*{"maxWidth": 390}

nbText: """
Under the drawing is the fold with its text, which every diagram of the domain articles has.

## When the two differ

`nbMermaid` is `mermaidSvg`, which draws and compares, and two blocks the pages had already:
`nbSvg` and `nbFold`. When the drawings differ, `mermaidSvg` stops the build with the first byte
where they part, and a few bytes of each. Here is a text it refuses today: a link to a host
written with an accent.
"""

nbCode:
  echo cafe
  echo firstLine

if caught.len > 0:
  nbText: &"""
The rest of the message shows the two drawings from that byte:

```
{caught.splitLines[1 .. 2].join("\n").strip}
```

Pele writes the host as the browser's `new URL()` does, in *punycode*: `café` becomes
`xn--caf-dma`, the form of a name outside ASCII that the domain name system accepts. nimaki keeps
the host as written. It is one of the differences that slipping odd characters into the corpus
found (the article *How nimaki reads text*); the roadmap's step *reading-fixes* is about them. A
page that drew this link would not build, which is the point.
"""
else:
  nbText: """
When this page was built, nimaki and Pele already drew it the same: the step *reading-fixes* of
the roadmap made nimaki write the host as Pele does.
"""

nbNote """
- `nbMermaid(text, caption, options)` and `mermaidSvg(text, options)` live in `docs/pele.nim`,
  beside `peleSvg`, because they need Pele at build time; the options are Pele's, as JSON
  (`tools/answers.nim` turns them into nimaki's).
- `now` is fixed, as in the referee, so that a gantt chart's line for today is the same on both
  sides.
- The posts that port a type keep their own code: they show Pele's drawing and nimaki's side by
  side, which is their subject.
""", nkNim, "In the port"

nbNote """
- The two domain articles and the Playground build with the block, every diagram identical.
- The café link above stops `mermaidSvg` with the bytes where the drawings part.
""", nkDone, "Checked"

nbNote """
- A diagram nimaki draws differently on purpose (an entry of the divergences) cannot be drawn
  with the block yet: it would need a way to say so.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- A post or a page that draws Mermaid text uses `nbMermaid`, and so checks the port while it
  explains something else. AGENTS.md says so, in *A devlog post*.
- The more the site draws, the larger this second, hand-written corpus grows.

## Sources

- The block: [`docs/pele.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/pele.nim).
- The articles that asked for it: [What happens when you open a web page](../opening-a-web-page/)
  and [A kitchen on a Friday night](../a-kitchen-on-friday-night/).
- Punycode, the ASCII form of a name outside ASCII: [RFC 3492](https://www.rfc-editor.org/rfc/rfc3492).
"""

nbSave
