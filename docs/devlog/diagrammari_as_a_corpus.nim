## devlog: 13 Nov 2026 F | What diagrammari writes | nimaki's referee now also checks the Mermaid text that diagrammari, its first user, writes: 34 texts from its specs, pages and tests, collected without running its code.
## kind: tooling
import std/[strformat, strutils, json, tables, algorithm]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../pele
import nimaki
import ../../tools/corpus_diagrammari

nbInit
nb.usePost()

let corpus = parseFile(docsDir / ".." / "corpus" / "diagrammari.json")
let difftest = parseFile(docsDir / "data" / "difftest.json")
let d = difftest["diagrammari"]
var collected: seq[string]
for l in readFile(docsDir / ".." / "reference" / "DIAGRAMMARI").splitLines:
  if l.startsWith("COMMIT="): collected.add l[7 .. ^1]
let commit = collected[0]
var waiting: seq[string]   # the types of diagrammari's text that nimaki does not draw yet
for t in difftest["types"]:
  if t.hasKey("diagrammari") and t["diagrammari"]["unsupported"].getInt > 0: waiting.add t["type"].getStr

nbText: &"""
## The findings, first

- **A second corpus.** Until today the referee checked nimaki only on Pele's own cases, the 2,118
  texts of `corpus/cases.json`. It now also checks the Mermaid text of
  [diagrammari](https://github.com/pietroppeter/diagrammari), the Nim library that nimaki is meant
  to become the engine of: **{corpus["count"].getInt}** texts of {corpus["byType"].len} diagram
  types, in `corpus/diagrammari.json`.
- **All the ported ones match.** {d["identical"].getInt} of the {d["cases"].getInt} come out of
  nimaki identical to Pele's, byte for byte, and {d["different"].getInt} differ. The other
  {d["unsupported"].getInt} are of types not ported yet ({waiting.join(", ")}).
- **Read, not run.** The texts are collected from diagrammari's files without running any of its
  code: the outputs its specs record, its ```` ```mermaid ```` blocks, and the strings its pages
  and tests give to `diagram` and `nbDiagram`. The diagrams its pages build with Nim verbs, and
  do not write down, are not in the corpus yet.
- **Pinned, like Pele.** `reference/DIAGRAMMARI` names the commit read
  (`{commit[0 ..< 7]}`); the corpus is rebuilt when it moves.

## Why diagrammari's text

A *corpus* is a fixed set of inputs that a program is run on, so that two versions, or two
programs, can be compared on the same things. Pele's corpus is made of the examples in its own
tests and in Mermaid's documentation. They are written to reach every corner of each diagram
type, which is what a port needs first.

diagrammari asks a different question. It makes diagrams in Nim (with verbs such as `node` and
`link`, or with Mermaid text) and today has Pele draw them, through Node. The plan is that one day
it draws them with nimaki, with no Node at all. For that, what matters is not every corner of
Mermaid but the text diagrammari actually writes. So its text is now a corpus too, and the
referee counts it apart, so that the coverage map can say how much of what diagrammari writes
nimaki already draws.

## Where the text is

diagrammari keeps Mermaid text in three kinds of places, and the tool,
`tools/corpus_diagrammari.nim`, reads all three.

**The examples of its specs.** diagrammari describes its behaviour with
[OpenSpec](https://github.com/Fission-AI/OpenSpec): each requirement has an example in Nim and,
below it, what the example prints. diagrammari's CI runs every example and checks the print. When
the example prints a diagram, the print is exactly what its builders write, so it can be taken
without running the builders here. The tool keeps an output only when the example has a single
`echo`, of a diagram:
"""

nbCode:
  for code in ["echo f", "echo sequence().message(\"a\", \"b\", \"hi\")", "echo d.kind",
               "echo s.svg.startsWith(\"<svg\")"]:
    echo code.alignLeft(42), if printsADiagram(code): "a diagram" else: "something else"

nbText: """
**Mermaid blocks** in its Markdown files, such as the README, which GitHub draws.

**String literals** that its Nim files give to `diagram`, `mermaid` or `nbDiagram`, in its pages
and its tests. A Nim string written with three quotes can be indented with the code around it;
diagrammari's `diagram` then removes the indentation common to all lines. The tool does the same,
so the text in the corpus is the text Pele receives:
"""

nbCode:
  echo asDiagram("\n    flowchart LR\n      a --> b\n  ")

nbText: &"""
A literal built with `&` or `fmt` is skipped, because its text is only known when the page runs.
A text is a case when Pele's type detection, as ported to nimaki, finds a diagram in it, and each
distinct text is one case. At `{commit[0 ..< 7]}` that gives {corpus["count"].getInt} cases:
"""

block:
  type Row = object
    `type`: string
    cases, identical: int
  var rows: seq[Row]
  for t in difftest["types"]:
    if t.hasKey("diagrammari"):
      rows.add Row(`type`: t["type"].getStr, cases: t["diagrammari"]["cases"].getInt,
                   identical: t["diagrammari"]["identical"].getInt)
  rows.sort(proc (a, b: Row): int = cmp(b.cases, a.cases))
  let t = tabella(rows, rownameCol = "type"):
    tabHeader "diagrammari's Mermaid text", "cases per diagram type, and how many nimaki draws as Pele does"
    colsLabel {"identical": "same SVG"}
    fmtInteger ["cases", "identical"]
    optCssTheme()
  nbTable t

nbText: """
Flowcharts lead, as they do in diagrammari, whose builders write flowcharts, sequence diagrams,
pie charts and timelines. The other types come from its explainer, which shows one diagram of each
kind it talks about. One of them is a state diagram of diagrammari itself, drawn here by nimaki:
"""

var stateCase = ""
for c in corpus["cases"]:
  if c["type"].getStr == "state": stateCase = c["source"].getStr

nbText: &"""
```mermaid
{stateCase}
```
"""

nbCode:
  let svg = render(stateCase, RenderOptions(now: some(fixedNow))).svg
  echo "identical to Pele's: ", svg == peleSvg(stateCase)

nbSvg svg, "A diagram's life in diagrammari, from its explainer: drawn by nimaki, the same bytes as Pele's."

nbFold "Every case, and where it was found":
  var lines: seq[string]
  for c in corpus["cases"]:
    lines.add &"- `{c[\"from\"].getStr}`: {c[\"type\"].getStr}"
  nbText: lines.join("\n")

nbText: """
## How the referee counts them

`tools/difftest.nim` now reads both corpora and runs them in one pass, with the same oracle (Pele
1.13.0 in Node). Its summary, `docs/data/difftest.json`, keeps the two apart: a type's `cases`
are still Pele's, so that the numbers earlier posts quote do not move, and a field `diagrammari`
beside them counts the others. `--corpus:diagrammari` runs only these. A type marked done on the
coverage map must be identical on both, or `--check-done` fails.
"""

nbNote """
- `tools/corpus_diagrammari.nim` writes `corpus/diagrammari.json` in the format of
  `corpus/cases.json`, with the file and line each text comes from.
- `reference/fetch.sh diagrammari` fetches the pinned commit into `reference/diagrammari/`
  (ignored by git, as Pele's checkout is). It is not part of `fetch.sh` with no argument: only a
  new pin needs it.
- The coverage map has a new column, *diagrammari*, beside *same SVG*, and a line with the total.
""", nkNim, "In the port"

nbNote &"""
- `difftest`: {d["identical"].getInt} of {d["cases"].getInt} diagrammari cases identical,
  {d["different"].getInt} different, {d["unsupported"].getInt} of types not ported yet. Pele's corpus is unchanged.
- Every case was read by hand once, to check that it is a diagram diagrammari writes (two spec
  outputs that print a diagram's kind, not its text, were found that way and are now skipped).
""", nkDone, "Checked"

nbNote """
- The diagrams diagrammari's pages build with Nim verbs and never write down (its explainer and
  its *Diagrams* series have many). Collecting them means running diagrammari's code, with its
  `$MARI_NODE` pointing at a small script that copies every text it sends to Pele. That needs
  Pietro's go-ahead, so it is a later step.
- The examples of diagrammari's open changes (`openspec/changes/`) are proposals and are not read.
- diagrammari draws with options of its own (an id prefix, a theme); the corpus checks the text
  with Pele's defaults, as for Pele's corpus.
""", nkWarning, "Not checked yet"

nbText: &"""
## What this changes for the port

- **The coverage map counts diagrammari's text** in its own column, and the referee checks it on
  every pull request.
- **An order for what is left.** diagrammari's explainer also writes {waiting.join(", ")}: those
  are the types it is waiting for.

## Sources

- diagrammari at [`{commit[0 ..< 7]}`](https://github.com/pietroppeter/diagrammari/tree/{commit}),
  read for this step: its specs (`openspec/specs/`), its pages (`docs/`), its tests, and
  `src/mari/core.nim` for what `diagram` does to a text.
- The code of this step: [`tools/corpus_diagrammari.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/corpus_diagrammari.nim),
  [`tools/difftest.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/difftest.nim),
  [`corpus/diagrammari.json`](https://github.com/pietroppeter/nimaki/blob/main/corpus/diagrammari.json).
"""

nbSave
