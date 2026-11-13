## The coverage map, docs/coverage/index.html: Pele part by part, every diagram type in its three
## stages (parse, layout, render), and how much of it is ported. Kept up to date: the data is
## docs/data/coverage.json; the lines of TypeScript come from `tools/coverage_seed.nim`, the
## rest (status, the Nim module, the post) from the pull request that ports a part.
import std/[strformat, json, tables]
import nimib
import tabelline, tabelline/nimib
import blocks, site

let cov = loadCoverage()
# what the referee found on its last full run (tools/difftest.nim): coverage id -> (identical, cases),
# on Pele's corpus and on diagrammari's
var matched, matchedD: Table[string, (int, int)]
let difftest = parseFile(docsDir / "data" / "difftest.json")
for t in difftest["types"]:
  matched[t["coverage"].getStr] = (t["identical"].getInt, t["cases"].getInt)
  if t.hasKey("diagrammari"):
    matchedD[t["coverage"].getStr] = (t["diagrammari"]["identical"].getInt, t["diagrammari"]["cases"].getInt)
let dCorpus = difftest{"diagrammari"}

nbInit
nb.doc.filename = docsDir / "coverage" / "index.html"
nb.usePage(section = "Coverage map", cadence = "kept up to date", title = "Coverage map · nimaki", homeHref = "../",
           description = "Pele part by part and diagram type by type, and how much of it is ported to Nim.")

nbTitle "Coverage map · kept up to date", "The coverage map", &"""
What there is to port, and what is ported. The reference is {pin.link}.
A part is done when `tools/difftest.nim` finds the SVG of the Nim identical, byte for byte, to
the SVG of Pele run in Node, on that part's corpus.
"""

nbPipeline cov.pipeline

nbText: &"The referee's last full run: **{difftest[\"identical\"].getInt}** of {difftest[\"cases\"].getInt} cases identical to Pele, {difftest[\"unsupported\"].getInt} not drawn yet, {difftest[\"different\"].getInt} different.\n"
if dCorpus != nil:
  nbText: &"On the Mermaid text of [diagrammari](https://github.com/pietroppeter/diagrammari), nimaki's first user: **{dCorpus[\"identical\"].getInt}** of {dCorpus[\"cases\"].getInt} cases identical, {dCorpus[\"unsupported\"].getInt} not drawn yet, {dCorpus[\"different\"].getInt} different.\n"

nbToc

nbText: &"""
## The shared core

What every diagram type stands on. Ported so far: **{cov.portedCode.thousands}** of
{cov.tsCode.thousands} lines of TypeScript.
"""

block:
  type Row = object
    part: string
    ts: int
    status: string
  var rows: seq[Row]
  for p in cov.core:
    let nim = if p.nim.len > 0: &"<br>`{p.nim}`" else: ""
    let notes = if p.notes.len > 0: &"<br>*{p.notes}*" else: ""
    rows.add Row(part: &"**{p.id}**: {p.what}{nim}{notes}", ts: p.code, status: status(p.status))
  let t = tabella(rows):
    tabHeader "The shared core", "lines of TypeScript in Pele"
    colsLabel {"part": "part", "ts": "TypeScript"}
    fmtInteger ["ts"]
    fmtMarkdown "part"
    fmtPassthrough "status", escape = false
    colsWidth {"ts": "6em", "status": "5.5em"}
    optCssTheme()
  nbTable t

nbText: """
## Diagram types × stages

Every diagram type is parsed (Mermaid text to a model), laid out (positions and sizes) and
rendered (SVG text). The split of a type's lines into stages goes by file name: most types keep
their layout inside `render.ts`, so a `0` under layout means "no file of its own", not "no
layout". Smallest first, which is roughly the order of the port. *Tests* are the lines of
Pele's tests for the type (compat specs from Mermaid, render and layout tests). *Same SVG* is
what the referee found on its last full run: of the type's cases in `corpus/cases.json`, how
many nimaki draws byte for byte as Pele does. *diagrammari* is the same on the Mermaid text of
diagrammari (`corpus/diagrammari.json`), for the types it writes.
"""

block:
  type Row = object
    diagram: string
    parse, layout, render: string
    tests: int
    identical, diagrammari: string
  var rows: seq[Row]
  proc cell(p: Part): string = &"{p.code}<br>{status(p.status)}"
  for d in cov.diagrams:
    let nim = if d.nim.len > 0: &"<br>`{d.nim}`" else: ""
    let notes = if d.notes.len > 0: &"<br>*{d.notes}*" else: ""
    rows.add Row(diagram: &"**{d.id}** · {d.code}{nim}{notes}", parse: cell(d.parse), layout: cell(d.layout),
                 render: cell(d.render), tests: d.tests,
                 identical: (let m = matched.getOrDefault(d.id); &"{m[0]} of {m[1]}"),
                 diagrammari: (if d.id in matchedD: (let m = matchedD[d.id]; &"{m[0]} of {m[1]}") else: ""))
  let t = tabella(rows):
    tabHeader "Diagram types", "lines of TypeScript per stage, and the status of each"
    colsLabel {"diagram": "type · lines"}
    fmtMarkdown "diagram"
    fmtPassthrough ["parse", "layout", "render"], escape = false
    colsLabel {"identical": "same SVG"}
    fmtInteger ["tests"]
    optCssTheme()
  nbTable t

nbText: """
## How the map changes

- The pull request that ports a part or a stage sets its `status` in `docs/data/coverage.json`
  (`started`, then `done`), its `nim` module, and the `post` that explains it.
- `done` means: difftest finds the Nim output identical to Pele's on the part's corpus. A
  wanted difference is a [divergence](../decisions/#divergences), not a `done`.
- When the pin moves, `nim r tools/coverage_seed.nim` recounts the TypeScript and keeps what
  people wrote.
"""

nbSave
