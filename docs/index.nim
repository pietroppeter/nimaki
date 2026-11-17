## The home page, docs/index.html.
import std/[strformat, json]
import nimib
import blocks, site, pele
import nimaki

let cov = loadCoverage()
let posts = devlogPosts()
let corpusCount = parseFile(repoDir / "corpus" / "cases.json")["count"].getInt

nbInit
nb.doc.filename = docsDir / "index.html"
nb.usePage(title = "nimaki", cadence = "kept up to date",
           description = "An engine that turns Mermaid text into SVG diagrams, in JavaScript and as native code: Pele, ported to Nim.")

nbTitle "Mermaid diagrams for Nim", "nimaki: diagrams from text, in Nim", """
nimaki is an engine that draws diagrams. You give it a few lines of
[Mermaid](https://mermaid.js.org), a small language for describing a diagram in text (a
flowchart, a pie chart, a sequence of messages...), and it gives back the drawing as SVG, the
picture format that every browser shows and that stays sharp at any size.
"""

nbText: "## What it gives a Nim developer\n\nOne call turns text into a drawing:"

nbCode:
  let text = "pie\n \"Dogs\": 386\n \"Cats\": 85"
  let pets = render(text)
  echo pets.width, " x ", pets.height
nbSvg pets.svg, "The drawing that call returns."

nbText: &"""
- **A plain Nim function.** `render(text)` returns the SVG text and its size, at once: no
  browser, no Node, no other program to start. It fits a command line tool, a static site
  generator, a nimib page, a web server.
- **Every Mermaid diagram type**: all {cov.diagrams.len} of Mermaid {pin.mermaid}, from
  flowcharts and sequence diagrams to gantt charts, class diagrams and mind maps.
- **Native and JavaScript from the same code.** `nim c` gives a native program, `nim js` a
  script for web pages and Node, with Pele's browser functions (`nimaki.mount` fits a drawing to
  its box, with zoom).
- **More than a picture.** `parse(text)` gives the diagram as data (its nodes, edges, labels) in
  Pele's model, as JSON; `detectType` and `supports` say what a text is. The drawing's colours
  are CSS variables, so a page's theme restyles it, and `maxWidth` fits it to a phone.
- **Small to depend on**: `requires "nimaki == 0.2.0"`, and its only dependency is nitely's pure
  Nim `regex` (with its Unicode tables). From other languages, a C interface (`nimaki_render`) does the same through a
  shared library.
- **Exact.** Each build draws the same bytes as [Pele](https://github.com/obsidianmd/pele) on all
  {corpusCount.thousands} test diagrams of the corpus, and every diagram on this site is checked
  against Pele when the site is built.

## How it is made

nimaki is a port of Pele, the Mermaid renderer that Steph Ango made for Obsidian, from
TypeScript to [Nim](https://nim-lang.org), made one explained step at a time. Pele is the
original and nimaki follows it: when the two disagree, nimaki is wrong. The same Nim code is
then built two ways, and the native build is what Nim adds to Pele.
"""

nbMermaid """
flowchart TD
  T[Mermaid text] --> N[nimaki, in Nim]
  N -->|nim c| C[native build]
  N -->|nim js| J[JavaScript build]
  C --> P[Nim programs]
  C --> A[other languages, through C]
  J --> W[web pages and Node]
  P --> S[the same SVG as Pele]
  A --> S
  W --> S
""", "One Nim code, two builds, one drawing: the same bytes as Pele's."

nbCards "the two builds":
  nbCard("In a native program", "devlog/a-c-abi/", "the native build", nkNim):
    nbText "`import nimaki` and `render(text).svg` in Nim, or `nimaki_render` from C, Python or any language that can call C."
  nbCard("In a web page", "playground/", "the JavaScript build", nkInfo):
    nbText "Load `nimaki.js` and call `nimaki.render` or `nimaki.mount`, the same functions as Pele's. The playground draws with it in your browser."

nbText: &"""
## Where it stands

The snapshot of Pele is {pin.link}, which draws every diagram type of Mermaid {pin.mermaid}:
{cov.tsCode.thousands} lines of TypeScript, tests not counted. Ported so far: {cov.portedCode.thousands}.
Each island is a shared part of Pele or a diagram type; it glows like lava when its port starts
and cools to olivine when the Nim draws, byte for byte, the same SVG as Pele.
"""

nbModules(cov, "modules/")

nbText: """
## Why

To learn how diagrams are drawn from text (parsing, graph layout, measuring text, writing SVG)
by porting a renderer that does all of it in a small, readable codebase; to give
[diagrammari](https://github.com/pietroppeter/diagrammari) an engine that needs no JavaScript
runtime (the native build); to see how far an AI model can carry a long port when each step is small, checked byte
for byte against the original, and explained to a person who reviews it; and for the fun of it.

## The name

In Hawaiian stories, Nāmaka is a goddess of the sea and Pele's older sister. The two quarrelled,
and wherever Pele dug a fire pit down the island chain, Nāmaka's sea followed. nimaki is Nim
plus Nāmaka: the sea once more, after Mermaid, Pele and mari. It is a port, not a rival: every
line here exists because Pele was written first, and written well.

## Where to go
"""

nbCards "the pages of the site":
  nbCard("Devlog", "devlog/", "dated posts", nkInfo):
    nbText "Every step, explained: research, plans and the port itself."
  nbCard("Roadmap", "roadmap/", "kept up to date", nkInfo):
    nbText "The phases and their steps, who is on each, and where each one stands."
  nbCard("Coverage map", "coverage/", "kept up to date", nkInfo):
    nbText "Pele part by part and diagram type by type (parse, layout, render), and how much is in Nim."
  nbCard("Decisions", "decisions/", "kept up to date", nkInfo):
    nbText "The choices of the port, each a short dated record, and the wanted divergences from Pele."
  nbCard("Porting guide", "porting/", "kept up to date", nkInfo):
    nbText "How Pele's TypeScript is written in Nim here: rules, idiom map, traps."
  nbCard("Playground", "playground/", "kept up to date", nkInfo):
    nbText "Diagrams drawn by nimaki in your browser, and a box to try your own Mermaid text."
  nbCard("Benchmark", "benchmark/", "kept up to date", nkInfo):
    nbText "How fast nimaki draws in C, in JavaScript and in WebAssembly, next to Pele, and how it is measured."
  nbCard("For coding agents", "agents/", "kept up to date", nkInfo):
    nbText "The working rules of the repository: how a step, a post and a pull request are made."

if posts.len > 0:
  nbText: "## Latest posts"
  nbCards "the latest posts":
    for i, p in posts:
      if i >= 6: break
      nbCard(p.title, "devlog/" & p.slug & "/", &"{p.stamp} · {p.kind}", (if p.kind == "port": nkPele elif p.kind == "research": nkNim else: nkInfo)):
        nbText p.lede
nbSave
