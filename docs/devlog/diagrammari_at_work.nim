## devlog: 14 Nov 2026 H | diagrammari at work | The referee now also checks the text diagrammari writes when its tests, spec examples and pages run: listening to what it asks Pele to draw found three times as many diagrams as reading its files.
## kind: tooling
import std/[strformat, strutils, json, tables, sequtils]
import nimib
import ../blocks
import ../../tools/corpus_diagrammari

nbInit
nb.usePost()

let corpus = parseFile(docsDir / ".." / "corpus" / "diagrammari.json")
let difftest = parseFile(docsDir / "data" / "difftest.json")
let d = difftest["diagrammari"]
let total = corpus["count"].getInt
let fromRun = corpus["fromRun"].getInt
let readOnly = total - fromRun
var waiting: seq[string]   # the types of diagrammari's text that nimaki does not draw yet
for t in difftest["types"]:
  if t.hasKey("diagrammari") and t["diagrammari"]["unsupported"].getInt > 0: waiting.add t["type"].getStr
let notYet = if waiting.len == 0: ", and every type in them is ported"
             else: ", and " & $d["unsupported"].getInt & " are of types not ported yet (" & waiting.join(", ") & ")"
var ranCases: seq[JsonNode]
for c in corpus["cases"]:
  if c["from"].getStr.startsWith("run:"): ranCases.add c

nbText: &"""
## The findings, first

- **Three times as many diagrams.** The [previous post on diagrammari](../diagrammari-as-a-corpus/)
  read its files and found 34 Mermaid texts. Running it finds what its Nim builders write too:
  the corpus now holds **{total}** texts, **{fromRun}** of them found only by running it.
- **They all match.** {d["identical"].getInt} of the {d["cases"].getInt} come out of nimaki
  identical to Pele's, byte for byte, {d["different"].getInt} differ{notYet}.
- **Run, but not changed.** Pietro allowed running diagrammari's code in nimaki's sandbox (14
  November). The tool runs it in a copy of the pinned checkout, and listens through a door
  diagrammari already has: `$MARI_NODE`, the Node it draws with. Nothing in diagrammari changed.

## Why reading was not enough

diagrammari makes a diagram in one of two ways. You can give it Mermaid text, which is in its
files and can be read. Or you can build the diagram with Nim verbs, and diagrammari writes the
text:

```nim
let d = initSequence()
  .participant("You")
  .message("You", "Page", "open")
```

The text Pele gets is written only when that code runs. Reading the files finds the verbs, not
the text. The previous post took the text from one place where diagrammari had written it down,
the outputs that its specs record, and said that the diagrams its pages build with verbs were
still missing.

## Listening to the requests

diagrammari draws with Pele, in Node. It starts one Node process and sends it a request for each
diagram, one line of JSON: the text and the options. It finds Node on the `PATH`, or where
`$MARI_NODE` says (in `src/mari/pele.nim`). So the tool points `$MARI_NODE` at a small script of
its own, which writes each request down and then hands it to the real Node:
"""

nbCode:
  echo "#!/bin/sh"
  echo "tee -a \"$MARI_LOG\" | exec node \"$@\""

nbText: &"""
`tee` copies what it reads to a file and passes it on, so diagrammari gets its drawings as
before, and the log gets every request. The tool then runs, in a copy of the checkout:

{runs.mapIt("- `" & it[1] & "` (" & it[0] & ")").join("\n")}

after diagrammari's own `tools/setup.sh`, which fetches its dependencies. Each request becomes a
text of the corpus, named after the run it came from (`run:pages#12` is the twelfth request of
the pages). A text that was also read from a file keeps the file's name, so only {fromRun} carry
a `run:` name. Here are two, as diagrammari wrote them:
"""

for c in ranCases[0 ..< min(2, ranCases.len)]:
  nbText: "```mermaid\n" & c["source"].getStr & "\n```"

nbText: &"""
## What the referee says

By type, the corpus is now:
"""

var rows: seq[string]
for t, n in corpus["byType"]: rows.add &"| {t} | {n.getInt} |"
nbText: "| type | texts |\n|---|---|\n" & rows.join("\n")

nbNote &"""
- `tools/corpus_diagrammari.nim` reads, as before, and then runs diagrammari (`--static` reads
  only). One run takes about a minute.
- Only the text is kept, not the options of each request (diagrammari's pages ask for a
  `maxWidth` and a font): the referee draws every case with the same options.
""", nkNim, "In the port"

nbNote &"""
- `difftest --corpus:diagrammari`: {d["identical"].getInt} identical, {d["different"].getInt}
  different, {d["unsupported"].getInt} not ported yet, in C and in JavaScript (`--js`).
- diagrammari's tests, spec examples and pages all ran without an error at the pinned commit.
""", nkDone, "Checked"

nbNote """
- CI does not run diagrammari: the corpus is rebuilt by hand, when `reference/DIAGRAMMARI` moves.
- The requests are the ones diagrammari makes today. A page it adds later, or a builder no page
  uses, is not in them.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- The coverage map's *diagrammari* column now counts what diagrammari draws, not only what it
  writes down: it is the better measure of how close nimaki is to being its engine.
- Every type diagrammari draws today is ported, and draws the same bytes as Pele. What is left
  before nimaki can be its engine is the way in, which [a proposal for diagrammari](../a-proposal-for-diagrammari/) describes.

## Sources

- The tool: [`tools/corpus_diagrammari.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/corpus_diagrammari.nim);
  the corpus: [`corpus/diagrammari.json`](https://github.com/pietroppeter/nimaki/blob/main/corpus/diagrammari.json).
- diagrammari's Node server, which reads `$MARI_NODE`:
  [`src/mari/pele.nim`](https://github.com/pietroppeter/diagrammari/blob/eb7d1c5702de5d5ddb8e6047af0202936995a648/src/mari/pele.nim).
"""

nbSave
