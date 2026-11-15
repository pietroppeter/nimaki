## devlog: 15 Nov 2026 O | nimaki 0.2.0 | The second release: Pele's browser side, and Pele's models as JSON from every way in. With it, each thing the proposal for diagrammari listed as missing is done, or put off on purpose.
## kind: tooling
import std/[json, os, sequtils, strformat, strutils]
import nimib
import ../blocks
import nimaki, nimaki/modeljson

nbInit
nb.usePost()

const docs = currentSourcePath().parentDir.parentDir
proc data(name: string): JsonNode = parseJson(readFile(docs / "data" / name))
proc thousands(n: int): string = insertSep($n, ',')

let
  difftest = data("difftest.json")
  peleTests = data("peletests.json")
  counts = peleTests["counts"]
  cabi = data("cabi.json")
  install = data("installcheck.json")
  parsed = data("parsediff.json")
  portmap = data("portmap.json")
  cases = difftest["cases"].getInt + difftest["diagrammari"]["cases"].getInt
  identical = difftest["identical"].getInt + difftest["diagrammari"]["identical"].getInt
  conformant = portmap["totals"]["conformant"]["files"].getInt
  ported = conformant + portmap["totals"]["draft"]["files"].getInt
  sizes = parseJson(readFile(docs / "devlog" / "data" / "a_type_at_a_time" / "sizes.json"))
  peleGzip = sizes["peleBundle"]["gzip"].getInt

proc gzipOf(name: string): int =
  for f in sizes["files"]:
    if f["name"].getStr == name: return f["gzip"].getInt
  raise newException(KeyError, name)

proc kb(n: int): string = $(int(n.float / 1000 + 0.5)) & " KB"

let
  allGzip = gzipOf("danger, in a function, minified")
  fourGzip = gzipOf("flowchart, sequence, pie, timeline")

nbText: &"""
## The findings, first

- **nimaki 0.2.0** is ready to tag, after waiting for a smaller JavaScript build: see the note
  below. It draws as Pele {peleVersion}, the same drawings as 0.1.0: {identical.thousands} of
  {cases.thousands} cases identical to Pele.
- **New in it: Pele's browser side** (`mount`, zoom, the canvas measurer), told in
  [A drawing that fits its box](../a-drawing-that-fits-its-box/), and **Pele's models as JSON**:
  `modelJson` in Nim, `nimaki_parse` in the C ABI, and Pele's model objects from `nimaki.parse`
  in a page.
- **Pele's own tests**: {counts["passed"].getInt.thousands} of {peleTests["tests"].getInt.thousands}
  pass on the JavaScript build, {counts["failed"].getInt} fail; none is counted apart any more for
  calling what nimaki lacks. Every one of the {ported} ported files is conformant.
- **For diagrammari**, every item the [proposal](../a-proposal-for-diagrammari/) listed as
  missing is now done: the table below. The last was the size of the JavaScript file, done in
  [A type at a time](../a-type-at-a-time/): nimaki.js is {allGzip.kb} compressed with every
  type, and a build of the four types diagrammari writes is {fourGzip.kb}, against
  {peleGzip.kb} for Pele's bundle.
- **The minor number moves** because the API grew and the page's `nimaki.render` changed shape
  (it throws now, as Pele's does): decision 0020's rule for 0.x.
"""

nbNote """
**Pietro's answer, 15 November 2026:** not yet. nimaki is not ready for diagrammari while
nimaki.js weighs about ten times Pele's bundle, so the size comes first: the roadmap step
[A smaller JavaScript build](../../roadmap/), with research into why a Nim build for JavaScript
is large and how others make it smaller, and then the reduction. 0.2.0 is tagged after that,
from a later commit, and the look back at the whole port waits too. Carried out the same day:
[Why nimaki.js is big](../why-nimaki-js-is-big/) and [A type at a time](../a-type-at-a-time/)
(decision 0022); 0.2.0 now holds that work, and is tagged from a commit that includes it.
""", nkQuestion, "Tag it now?"

nbText: &"""
## What the proposal needed

The post *A proposal for diagrammari* (14 November) ended with a list of what nimaki still
lacked before diagrammari could draw with it instead of Pele in Node. Each item, as it stands at
this release:

| What diagrammari needs | Where it stands |
|---|---|
| A tag to pin | 0.1.0 shipped in the morning; 0.2.0 is this release. |
| Pele's `parse`, with the model in a form that crosses the C ABI | Done here: `nimaki_parse`, below. |
| `mount`, zoom and lazy loading, for client mode | `mount` and zoom done ([A drawing that fits its box](../a-drawing-that-fits-its-box/)); lazy loading done with one file per type: `nimaki.load(type)` adds `nimaki-<type>.js` to the page ([A type at a time](../a-type-at-a-time/)). |
| A second reading of the port | Not needed: tests and fuzzing make a file conformant (decision 0014), and every file is. |
| A text measurer of the page's font | Done in a browser (the canvas measurer); at build time both Pele and nimaki measure with Arial's widths, as before. |
| A small JavaScript file, for client mode | Done: minified, and one build per set of types (`-d:nimakiTypes`); diagrammari's four types are {fourGzip.kb} compressed, Pele's bundle {peleGzip.kb} ([A type at a time](../a-type-at-a-time/)). |
"""

nbText: """
## A model as JSON

Pele's `parse(text)` gives the *model* of a diagram, what the text says before anything is
placed or drawn: for a flowchart, its nodes and its edges. diagrammari's Python experiment reads
it to know the two ends of each edge. nimaki's `parse` gives a Nim object, which Python cannot
read; `modelJson` writes it as JSON in the shape of Pele's model, the same keys, with a JavaScript
*Map* (a table of named entries) as a JSON object and a *Set* (a list without repeats) as a JSON
array. The writer was already there, as the referee for models (`tools/parsediff.nim`, decision
0018) compares nimaki's models with Pele's through it; this release moves it into the package as
`nimaki/modeljson`.
"""

nbCode:
  let model = modelJson(parse("flowchart LR\n  A[Text] --> B[Model] --> C[Drawing]\n"))
  echo model["type"].getStr, ", ", model["nodes"].len, " nodes"
  for edge in model["edges"]:
    echo edge["start"].getStr, " -> ", edge["end"].getStr, " (", model["nodes"][edge["end"].getStr]["text"].getStr, ")"

nbText: """
The C ABI gains a function, `nimaki_parse`, with the same request as `nimaki_render` and the
model in the answer. From Python, through ctypes, as the C ABI's smoke test calls it:

```python
p = lib.nimaki_parse(json.dumps({"source": "flowchart LR\n  A --> B\n"}).encode())
answer = json.loads(ctypes.string_at(p).decode())
lib.nimaki_free(p)
[(e["start"], e["end"]) for e in answer["model"]["edges"]]   # [('A', 'B')]
```

In a page, `nimaki.parse(text)` now returns the model object itself, Maps and Sets included, as
Pele's `parse` does, and `nimaki.render(model)` draws it.
"""

nbNote &"""
- **Models**: on the corpus, {parsed["same"].getInt.thousands} of nimaki's models are the same as
  Pele's, {parsed["different"].getInt} different (`tools/parsediff.nim`, the last run in
  `docs/data/parsediff.json`); `modelJson` is that writer.
- **The C ABI**, from Python: {cabi["identical"].getInt.thousands} of {cabi["cases"].getInt.thousands}
  cases drawn identical to Pele, {cabi["msPerCase"].getFloat} ms a case; the smoke test now also
  reads a flowchart's model with `nimaki_parse` and gets a syntax error back as an answer.
- **Pele's tests on the JavaScript build**: {counts["passed"].getInt.thousands} pass,
  {counts["speed"].getInt} only miss a time bound of Pele's, {counts["known"].getInt} known,
  {counts["api"].getInt} `api`, {counts["failed"].getInt} failed.
- **installcheck**: nimble installed {install["installed"].mapIt(it.getStr).join(", ")}; a program
  outside the repository drew {install["identical"].getInt.thousands} of
  {install["cases"].getInt.thousands} cases identical to Pele; {install["builds"].mapIt(it.getStr).join(" and ")}
  of the installed package compiled ({install["nim"].getStr}).
""", nkDone, "Checked for this release"

nbText: &"""
## What diagrammari can do with it

Nothing in diagrammari changes from here: these are proposals, for diagrammari's own thread.

- **Static mode, without Node**: `toSvg` calls nimaki's `render`, as the proposal sketched;
  `requires "nimaki == 0.2.0"`.
- **The Python package without QuickJS**: `mari_draw` calls `nimaki_render`, and the flowchart
  layer that needs each edge's ends calls `nimaki_parse`.
- **Client mode**: a page can load nimaki's JavaScript and call `nimaki.mount` where it called
  `pele.mount`, with the same options. A build of the four types diagrammari writes
  (`nim js -d:danger -d:nimakiTypes=flowchart,sequence,pie,timeline src/nimaki/web.nim`, then
  minified) is {fourGzip.kb} compressed, less than Pele's bundle; or `nimaki-core.js` with
  `nimaki.load`, as Pele's lazy entry point does (decision 0022).
"""

nbText: """
## What this changes for the port

- The roadmap step *nimaki 0.2.0* is done once Pietro tags it (threads cannot push tags).
- Then, by Pietro's plan: a last post that looks back at the whole port (the roadmap step
  *Looking back*), and then the automatic work stops, to start again when nimaki is needed.

## Sources

- The proposal: [A proposal for diagrammari](../a-proposal-for-diagrammari/), 14 November 2026.
- The release rules: [decision 0020](../../decisions/#0020-versions-and-releases); the previous
  release, [nimaki 0.1.0](../nimaki-0-1-0/).
- Pele at the pin: [`src/core.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/core.ts)
  (`parse`, `render`, `mount`) and [`src/models.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/models.ts).
- The code: `src/nimaki/modeljson.nim`, `src/nimaki/capi.nim` and `capi.h`, `tests/cabi/smoke.py`,
  `src/nimaki/web.nim`, `CHANGELOG.md`.
"""

nbSave
