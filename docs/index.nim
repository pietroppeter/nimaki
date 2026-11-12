## The home page, docs/index.html.
import std/[strformat]
import nimib
import blocks, site

let cov = loadCoverage()
let posts = devlogPosts()

nbInit
nb.doc.filename = docsDir / "index.html"
nb.usePage(title = "nimaki", cadence = "kept up to date",
           description = "Pele, the Mermaid renderer, ported to Nim one explained step at a time.")

nbTitle "A port, built in public", "nimaki: Pele, in Nim", """
[Mermaid](https://mermaid.js.org) turns a few lines of text into a diagram.
[Pele](https://github.com/obsidianmd/pele) is a new renderer for it, made by Steph Ango for
Obsidian: Mermaid text in, themeable SVG out, synchronous, no browser, no dependencies. This
project ports a snapshot of Pele from TypeScript to [Nim](https://nim-lang.org), one well defined
step at a time, and explains every step.
"""

nbText: &"""
The snapshot is {pin.link}, which draws every diagram type of Mermaid {pin.mermaid}:
{cov.tsCode.thousands} lines of TypeScript, tests not counted. Ported so far: {cov.portedCode.thousands}.
Each lamp is a shared part of Pele or a diagram type; it turns yellow when its port starts and
lights up when the Nim draws, byte for byte, the same SVG as Pele.
"""

nbPipeline cov.pipeline

nbText: """
## Why

To learn how diagrams are drawn from text (parsing, graph layout, measuring text, writing SVG)
by porting a renderer that does all of it in a small, readable codebase; to give
[diagrammari](https://github.com/pietroppeter/diagrammari) an engine that needs no JavaScript
runtime; to see how far an AI model can carry a long port when each step is small, checked byte
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
