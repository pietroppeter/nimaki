## devlog: 14 Nov 2026 F | A proposal for diagrammari | Now that nimaki draws every type as Pele does, diagrammari could draw at build time with a Nim call instead of a Node process: what would change, for whom, and what is still missing.
## kind: plan
import std/[strformat, strutils, json, monotimes, times, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
let cabi = parseFile(docsDir / "data" / "cabi.json")
let corpus = parseFile(repoDir / "corpus" / "diagrammari.json")
let shortCommit = corpus["commit"].getStr[0 ..< 7]
let libMegabytes = formatFloat(cabi["bytes"].getInt / 1_000_000, ffDecimal, 1)
let msCabi = formatFloat(cabi["msPerCase"].getFloat, ffDecimal, 2)

nbText: &"""
## The findings, first

- **The engine is ready for diagrammari's diagrams.** Every diagram type of Pele 1.13.0 is
  ported, and nimaki draws the same bytes as Pele on all {difftest["identical"].getInt.thousands}
  cases of Pele's corpus and on all {difftest["diagrammari"]["identical"].getInt} Mermaid texts found
  in diagrammari (at commit `{shortCommit}`), in C and in JavaScript.
- **The proposal:** diagrammari draws at build time by calling nimaki, a Nim library, instead of
  sending each text to a Node process that runs Pele's bundle. `import mari` stays the same for
  its users; what goes away is Node, a temporary directory, a subprocess, and the `no-node` error.
- **Python gets the same engine** through nimaki's C ABI: no Node and no QuickJS in the wheel,
  about {msCabi} ms a diagram, from a library of {libMegabytes} MB.
- **Still missing**, and listed below: Pele's `parse` as a public function (the flowchart layer
  of diagrammari's Python experiment uses it), `mount` and zoom for drawing in the browser,
  a tag of nimaki to pin, and the second reading that would mark the port's files conformant.
- **Nothing is changed in diagrammari from here.** This post is the proposal, with the text of
  an OpenSpec change at the end for diagrammari's own thread to take, adapt or drop.
"""

nbText: """
## How diagrammari draws today

diagrammari (`import mari`) writes Mermaid text, from Nim builders or as text, and has Pele draw
it. Pele is JavaScript, so diagrammari ships Pele's browser bundle (`src/mari/vendor/pele.global.js`,
about 730 kB) and uses it in two ways:

- **At build time** (`toSvg`, *static* mode): the first diagram starts one Node process, which
  loads the bundle and answers one JSON request per line. The page holds the SVG and needs no
  JavaScript. Without Node, `toSvg` raises a `DiagramError` with code `no-node`.
- **In the browser** (*client* mode): the page carries the bundle, and Pele's `mount` draws each
  diagram when the page opens, at the width of the page.

`rmAuto`, the default, is static when Node can be found and client otherwise. In Python, a proof
of concept (`experiments/python/`) compiles QuickJS, a small JavaScript engine, into the library,
so that Pele runs without Node.
"""

nbText: """
## The same drawings, from Nim

diagrammari's static mode asks Pele for a drawing with a few options: `autoDirection` and
`responsive` on, an id prefix, and, for the narrow drawing that phones see, `maxWidth: 420`.
Here are all of diagrammari's Mermaid texts drawn both ways, by Pele in Node and by nimaki, with
those options:
"""

nbCode:
  let sources = block:
    var s: seq[string]
    for c in corpus["cases"]: s.add c["source"].getStr
    s
  proc nimakiSvg(source: string, narrow: bool): string =
    var o = RenderOptions(autoDirection: some(true), responsive: some(true),
                          idPrefix: some("dg-"),
                          now: fixedNow)  # the same "now" as Pele's run, for the gantt chart
    if narrow: o.maxWidth = some(420.0)
    try: render(source, o).svg except PeleError as e: "error " & e.code
  for narrow in [false, true]:
    var pele = %*{"autoDirection": true, "responsive": true, "idPrefix": "dg-"}
    if narrow: pele["maxWidth"] = %420
    let answers = peleRenders(sources, pele)
    var same = 0
    for i, s in sources:
      let theirs = if answers[i]["ok"].getBool: answers[i]["svg"].getStr
                   else: "error " & answers[i]["code"].getStr
      if nimakiSvg(s, narrow) == theirs: inc same
    echo (if narrow: "narrow: " else: "wide:   "), same, " of ", sources.len, " identical"

nbText: """
And how long nimaki takes for all of them, in this page's build (compiled without `-d:release`,
so slower than a release build):
"""

nbCode:
  let start = getMonoTime()
  for s in sources: discard nimakiSvg(s, false)
  let ms = (getMonoTime() - start).inMicroseconds.float / 1000
  echo &"{sources.len} diagrams in {ms:.1f} ms"

nbText: """
## What would change in diagrammari

The change is small because diagrammari already keeps Pele behind one function. In
`src/mari/pele.nim`, `toSvg` today writes a request, sends it to Node and reads the answer; it
would call nimaki instead:
"""

nbText: """
```nim
import nimaki except RenderOptions   # diagrammari has a RenderOptions of its own

proc toSvg*(d: Diagram, options = defaultOptions): Svg =
  ## The diagram drawn by nimaki, Pele in Nim: the same SVG as Pele, without Node.
  var o = nimaki.RenderOptions(autoDirection: some(options.autoDirection),
                               responsive: some(options.responsive),
                               idPrefix: some(if options.idPrefix.len > 0: options.idPrefix
                                              else: idFor(d.source)))
  if options.fontFamily.len > 0: o.fontFamily = options.fontFamily
  if options.fontSize > 0: o.fontSize = some(options.fontSize)
  if options.maxWidth > 0: o.maxWidth = some(options.maxWidth)
  if options.padding > 0: o.padding = some(options.padding)
  if options.config != nil: o.config = fromJson(options.config)
  try:
    let r = render(d.source, o)
    Svg(svg: r.svg, width: r.width, height: r.height,
        kind: r.diagramType, mermaidType: r.mermaidType)
  except PeleError as e:
    raise (ref DiagramError)(code: e.code, msg: e.msg, line: e.line,
                             column: e.column, snippet: e.snippet)
```
"""

nbText: """
The sketch is not compiled on this page, because diagrammari is not a dependency of nimaki;
its calls to nimaki are the same as in the cell above. Around it:

- **`mari.nimble`** requires nimaki, pinned in `atlas.lock` like nimib. nimaki's renderer needs
  only Nim's standard library, so diagrammari's core would still need nothing else.
- **`rmAuto`** is always static, and `nodeAvailable`, `MARI_NODE` and the `no-node` error can
  go, after a release that keeps them as a fallback (`MARI_ENGINE=node`), so that a page can be
  drawn both ways while people check.
- **Client mode stays as it is**: it still needs Pele's bundle in the page, for `mount`.
- **Pages build without Node**, in CI and on a laptop; `tools/setup.sh` and the
  `setup-node` step of the workflow can drop it once client mode is the only user of the bundle.
- **Updating Pele** becomes updating nimaki: a new pin there, followed by the port (the roadmap
  step *follow-pele*), instead of a new bundle here.

## What changes for people who `import mari`

For a Nim user, nothing in the API. `f.save "flow.svg"` and `nbDiagram f` draw the same SVG, byte
for byte, as before, with no Node to install. Two things are new: drawing works at any time in a
program, not only where Node is, and errors come from the same place with the same code, line,
column and snippet.

For the Python package, the C ABI of nimaki answers with the same JSON as the Node runner that
diagrammari's experiment reads (`ok`, `svg`, `width`, `height`, `type`, `mermaidType`, or
`code`, `message`, `line`, `column`, `snippet`). The experiment's `mari_draw` could call nimaki in
the same library instead of QuickJS:
"""

nbNote &"""
- Through the C ABI, from Python, nimaki draws {cabi["identical"].getInt.thousands} of
  {cabi["cases"].getInt.thousands} cases as Pele does (Pele's corpus and diagrammari's), in
  {msCabi} ms a case ({cabi["platform"].getStr}, Python {cabi["python"].getStr}).
- diagrammari's experiment reports about 0.8 ms a diagram for Pele in QuickJS, after 100 ms to
  load it, and a wheel of 1.3 MB (its README, read for this post, not measured here).
- nimaki's library is {libMegabytes} MB before compression; the size of a wheel holding it
  (compressed, as the experiment's 1.3 MB is) was not measured for this post.
""", nkDone, "Measured"

nbText: """
## What is still missing

Before diagrammari could switch, and in the order it would meet them:

1. **A tag of nimaki to pin.** Tags and releases wait for Pietro; until then, a commit.
2. **`parse`.** Pele's `parse(text)` gives the model of a diagram without drawing it.
   diagrammari's Python experiment uses it to know each flowchart edge's two ends for its
   personal layer. nimaki parses every type, but its `parse` is not public yet, and a model would
   need a JSON form to cross the C ABI.
3. **`mount`, `enableZoom` and lazy loading**, Pele's browser side. Client mode needs them, so
   it keeps Pele's bundle until nimaki's JavaScript build grows them.
4. **The second reading.** All of nimaki's ported files are still marked `draft`: they are
   identical to Pele on the corpus and the fuzzer, but have not been read a second time against
   Pele's source (decision 0005). That is a question for Pietro already: whether tests and
   fuzzing are enough.
5. **A text measurer of the page's font.** At build time, Pele in Node and nimaki both measure
   with Arial's widths, so nothing changes there; diagrammari's backlog item *Text measurement in
   Node* would become a nimaki option instead.

## The change, as diagrammari would write it

diagrammari starts work as an OpenSpec change. This is the text of one, for its own thread to
take, adapt or drop; it is not in diagrammari's repository.
"""

nbFold "The change, openspec/changes/use-nimaki/proposal.md":
  nbText: """
```markdown
## Why

diagrammari draws at build time by running Pele's bundle in one Node process. nimaki, a port of
Pele 1.13.0 to Nim, now draws every diagram type identical to Pele, byte for byte, on Pele's
corpus and on every Mermaid text of diagrammari. Drawing with nimaki removes Node from building
pages and from the Python package, and makes `rmAuto` always static.

## What Changes

- `toSvg` calls nimaki's `render` instead of the Node server; options map one to one.
- `mari.nimble` requires nimaki (pinned in `atlas.lock`); the core stays standard library only.
- For one release, `MARI_ENGINE=node` keeps the Node server, for comparison; then `nodeExe`,
  `nodeAvailable`, `MARI_NODE` and the `no-node` error are removed.
- `rmAuto` resolves to static. Client mode keeps the bundle and `mount`.
- The Python proof of concept calls nimaki in-process instead of QuickJS.

## Differences from Mermaid and Pele

- None in the drawings: nimaki's referee is Pele's npm package, byte for byte.

## Capabilities

### Modified Capabilities
- `rendering`: build-time drawing without Node.

## Impact

`src/mari/pele.nim`, `render_html.nim` (`resolve`), tests that set `MARI_NODE`, the setup script
and the pages workflow (no Node), the explainer's "How it is built", and the Python experiment.
```
"""

nbText: """
## What this changes for the port

- **The proposal is written**: the roadmap step *A proposal for diagrammari* is done. The
  decision, and any change in diagrammari, belong to diagrammari's own thread.
- **Two steps it points to**, not claimed here: a public `parse` with a JSON form of each model,
  and Pele's browser side (`mount`, zoom) in nimaki's JavaScript build.

## Sources

- diagrammari at the commit of nimaki's second corpus (`reference/DIAGRAMMARI`): `README.md`,
  `AGENTS.md`, `BACKLOG.md`, `src/mari/pele.nim`, `src/mari/render_html.nim`,
  `experiments/python/README.md`, `experiments/python/nim/capi.nim` and
  `openspec/changes/add-python-package/proposal.md`, read for this post, on
  [GitHub](https://github.com/pietroppeter/diagrammari).
- Pele at the pin: [`src/core.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/core.ts),
  for `parse`, `render` and `mount`.
- nimaki: [`src/nimaki/capi.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/capi.nim)
  and the post [A C ABI](../a-c-abi/); the data on this page is `docs/data/difftest.json`,
  `docs/data/cabi.json` and `corpus/diagrammari.json`.
"""

nbSave
