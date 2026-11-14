## The playground, docs/playground/index.html: diagrams drawn by nimaki in the reader's browser
## (nimaki compiled to JavaScript, src/nimaki/web.nim), and a text area to try Mermaid text in.
## Kept up to date: the list of types comes from the referee's last run (docs/data/difftest.json).
import std/[strformat, strutils, json, sequtils]
import nimib
import blocks, pele
import nimaki

let difftest = parseFile(docsDir / "data" / "difftest.json")
var drawn: seq[string]
for t in difftest["types"]:
  if t["identical"].getInt > 0 and t["unsupported"].getInt == 0: drawn.add t["type"].getStr

nbInit
nb.doc.filename = docsDir / "playground" / "index.html"
nb.usePage(section = "Playground", cadence = "kept up to date", title = "Playground · nimaki", homeHref = "../",
           description = "Mermaid diagrams drawn by nimaki in your browser, and a place to try your own.")

nbTitle "Playground · kept up to date", "Drawn in your browser", &"""
The diagrams on this page are drawn twice by nimaki: once when the page is built, and again
here, in your browser, by nimaki compiled to JavaScript. Below them is a box to write Mermaid
text in, which nimaki draws as you type. It draws {drawn.len} of Pele's 33 types so far.
"""

let options = """{"now": 1767225600000}"""   # the referee's fixed now, so that both drawings agree

proc live(source, caption: string) =
  let svg = mermaidSvg(source)   # nimaki's drawing, checked against Pele's at build time
  nbLive source, svg, caption, options

nbText: """
## Try it

Edit the text, or paste your own. The [coverage map](../coverage/) says which types are ported;
the others answer *not ported yet*.
"""

nbPlayground """flowchart LR
  text["Mermaid text"] --> nimaki{{"nimaki"}}
  nimaki -->|in the build| svg1(["SVG"])
  nimaki -->|in your browser| svg2(["SVG"])
""", options

nbText: """
## Drawn twice

Each drawing below came with the page, made by nimaki compiled to C when the site was built
(and checked then against Pele's, byte for byte).
When the page opens, nimaki compiled to JavaScript draws the same text again and puts its own
drawing in place. The line under each says whether the two are the same, byte for byte.
"""

live("""sequenceDiagram
  participant You
  participant Page
  participant nimaki
  You->>Page: open
  Page->>nimaki: render(text)
  nimaki-->>Page: SVG
  Page-->>You: the same drawing
""", "A sequence diagram.")

live(&"pie showData\n  title What nimaki draws\n  \"Ported types\" : {drawn.len}\n  \"Not yet\" : {33 - drawn.len}\n",
     "A pie chart, from the referee's last run.")

live("""stateDiagram-v2
  [*] --> Typed
  Typed --> Drawn : render
  Typed --> Error : syntax error
  Error --> Typed : fix it
  Drawn --> [*]
""", "A state diagram.")

live("""gantt
  title A small plan
  dateFormat YYYY-MM-DD
  excludes weekends
  section Design
    Research      :done, r1, 2025-12-22, 4d
    Sketches      :active, s1, after r1, 3d
  section Build
    Write code    :crit, c1, after s1, 5d
""", "A gantt chart, with the referee's fixed today, 1 January 2026.")

nbText: &"""
## What it is

`src/nimaki/web.nim` is the entry point: compiled with `nim js`, it defines
`nimaki.render(text, options)`, which returns the SVG text, as Pele's `render` does. The pages
build it into `assets/nimaki.js` and load it only where a page draws live. The types it draws
now: {drawn.mapIt("*" & it & "*").join(", ")}.
"""

nbSave
