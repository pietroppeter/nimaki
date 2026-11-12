## devlog: 12 Nov 2026 B | The referee | How the port is checked: the same Mermaid text goes to Pele in Node and to nimaki, and the two SVGs must match byte for byte, on 2,118 cases.
## kind: tooling
import std/[strutils, strformat, json, tables, algorithm]
import nimib
import ../blocks, ../site, ../pele
import ../../tools/verdict

nbInit
nb.usePost()

let corpus = parseFile(repoDir / "corpus" / "cases.json")
let summary = parseFile(docsDir / "data" / "difftest.json")

nbText: &"""
A port needs a judge that is not the porter. Here the judge is Pele itself: every input goes to
Pele, run in Node, and to nimaki, and the two answers are compared one byte at a time. This post
is about that judge, the **referee**: what it compares, on which inputs, and how we know it can
say no.

## The findings, first

- **{corpus["count"].getInt.thousands} inputs**, of all {corpus["byType"].len} diagram types,
  taken from Pele's own tests: the documentation examples of its corpus and every diagram written
  in the specs Pele ported from Mermaid. Today nimaki draws none of them, so the referee reports
  {summary["unsupported"].getInt.thousands} cases as *unsupported*, and that is the starting line.
- **Pele is fast enough to ask every time.** All the cases go through Pele in well under a
  second, so the referee asks the real thing on every run instead of keeping stored answers.
- **Pele is deterministic**, as its rules promise, with one catch: gantt charts read the clock
  and the time zone. With the same `now` but another time zone, two gantt examples change. The
  referee fixes both.
- **The referee can fail**: a self test shows that it finds Pele identical to itself on every
  case, and finds a one-byte change on every case.
"""

nbText: """
## What "byte for byte" means

An SVG is text. Two drawings can look the same and still be different text: a number written
`10` or `10.0`, attributes in another order, a space. The referee does not look at pictures; it
compares the two texts character by character and reports the first place where they part.
That is harsh on purpose. Pele promises that the same input and the same *text measurer* give
the same SVG, so any difference is a bug in the port, found by a machine, with a small input
that shows it.

The text measurer matters because a diagram's layout depends on how wide its labels are: a box
grows to fit its text, and everything moves with it. A browser measures text with the fonts it
has, which differ between machines. Pele, when no browser is there, uses its own measurer, built
from tables of letter widths. Both sides of the referee use that one: the oracle by default (Node
has no canvas), nimaki by porting it.

Here is Pele drawing a pie, at the moment this page was built:
"""

let pieText = "pie title What a pie needs\n  \"text measurer\" : 675\n  \"SVG builder\" : 1751\n  \"pie itself\" : 328\n"
let pieSvg = peleSvg(pieText)

nbText: &"""
```mermaid
{pieText.strip}
```
"""

nbSvg pieSvg, &"Drawn by Pele {pin.tag} in Node when this page was built: {pieSvg.len} bytes of SVG."

nbText: """
And here is what the referee says when one number in that SVG changes, the kind of slip a port
makes when it rounds differently:
"""

nbCode:
  let fromPele = Answer(ok: true, svg: pieSvg)
  let at = pieSvg.find("viewBox=\"") + "viewBox=\"0 0 ".len
  var port = pieSvg
  port[at] = (if port[at] == '9': '8' else: succ(port[at]))
  echo compare("demo", "pie", fromPele, Answer(ok: true, svg: port)).detail

nbText: """
## The inputs: the corpus

`tools/corpus.mjs` builds `corpus/cases.json` from the pinned Pele, the way Pele's own fuzz tests
gather their seeds (`tests/support/corpus.ts`):

1. every case of the 34 files of `tests/corpus/` (Mermaid's documentation examples, and Pele's
   own agentflow references);
2. every string in the compat specs (`tests/compat/<type>/*.spec.ts`, Mermaid's tests ported by
   Pele) that Pele recognises as a diagram.

Duplicates are dropped, and each case gets a stable id, like `corpus/pie-docs/0` or
`compat/flowchart/flow-text/12`. The file is committed, so the list of what is checked is
visible and reviewable; CI rebuilds it and fails if it drifts. This script is JavaScript, not
Nim, for one reason: the spec strings are JavaScript string literals, with escapes and template
syntax, and only JavaScript reads them exactly as Pele's tests do. Cases per type:
"""

nbFold "Show the cases per diagram type":
  nbCode:
    var counts: seq[(int, string)]
    for t, n in corpus["byType"]: counts.add (n.getInt, t)
    counts.sort(Descending)
    for (n, t) in counts: echo t.alignLeft(14), align($n, 5)

nbText: """
Not every case is a valid diagram: some are in the specs to check that Pele rejects them. Those
count too. When Pele throws, nimaki must throw the same error code with the same message, and the
referee compares those as it compares SVGs.

## The oracle

`tools/oracle.mjs` is twenty lines of JavaScript around Pele's `render`: one case in per line,
one answer out per line (the SVG, or the error code and message). It loads the npm package
`pele@1.13.0` that `reference/fetch.sh` downloads and checks against the integrity hash in
`reference/PIN`; the [first post](../a-stage-for-a-port/) showed that this package is
byte-identical to a build of the source at the pin.

Both sides get the same options: `now` fixed at 1 January 2026, midnight UTC, and the oracle
runs with `TZ=UTC`.
"""

nbNote """
Gantt charts compute dates in the local time zone and default `now` to the current time. Run
on the same inputs with `TZ=America/New_York` instead of `TZ=UTC`, the oracle drew two gantt
examples (`corpus/gantt-docs/2` and `/3`) differently and every other case the same. Two runs
with the same settings gave the same 2,118 answers, byte for byte. Checked by hand on
12 November 2026.
""", nkPele, "Deterministic, once the clock is fixed"

nbText: """
## The referee

`tools/difftest.nim` puts it together. It reads the corpus, asks the oracle (once per corpus and
package: the answers are cached in `build/oracle/`), renders each case with nimaki, and gives a
verdict per case: *identical*, *different*, or *unsupported* (nimaki raises it for a type it does
not draw yet). Following [decision 0006](../../decisions/#0006-tools-and-tests-are-written-for-a-reader-with-a-small-context)
it prints little: one `ERROR` line per difference (the first ten; all of them in
`build/difftest/report.json`), one line per type that has started, and a summary.

```sh
nim r tools/difftest.nim                 # everything
nim r tools/difftest.nim pie             # one type
nim r tools/difftest.nim --fast:10       # a 10% sample, for a quick check while porting
nim r tools/difftest.nim --self-test     # prove it can fail
```

In CI it runs with `--check-done`: a type the [coverage map](../../coverage/) marks done must be
identical on every case, so a later change cannot quietly break it. A full run also writes
`docs/data/difftest.json`, and the coverage map shows, for every type, how many of its cases
are identical. The summary as this page was built:
"""

nbCode:
  echo summary["cases"].getInt, " cases: ", summary["identical"].getInt, " identical, ",
    summary["different"].getInt, " different, ", summary["unsupported"].getInt, " unsupported"

nbText: """
## How we know it can say no

A referee that always says "identical" is worse than none. `--self-test` runs two checks on
every case: Pele against itself must be identical, and Pele against itself with one byte changed
(in the middle of the SVG, or a dot added to an error message) must be different. CI runs it
before the real comparison. The verdicts themselves have unit tests in
`tests/test_difftest.nim`: equal texts, a `10` against a `10.0`, the same error with another
line number, an error against a drawing.

## What was checked, and what was not

- Checked: the oracle is deterministic with `TZ` and `now` fixed; the self test passes on all
  cases; the unit tests pass; CI runs the corpus check, the self test and the full comparison.
- Not yet: inputs from diagrammari (its examples are Nim builders that write Mermaid; collecting
  them is a later step), and differential fuzzing (mutated inputs, as Pele's `mutator` does).
  Both are on the [roadmap](../../roadmap/).
- nimaki's `render` is only the shape of the API: it raises *unsupported* for everything. The
  port of the core and pie replaces it.

## What this changes for the port

- A port step is done when `nim r tools/difftest.nim <type>` reports every case identical, and
  then the coverage map marks it done and CI keeps it so.
- Every difference arrives as a case id, a byte offset and the two texts around it: a small,
  exact bug report.
- Pages can show diagrams drawn by Pele itself: `nbSvg peleSvg(text), caption` (in
  `docs/pele.nim`), run when the page is built.

## Sources

- Pele at the pin: [AGENTS.md](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/AGENTS.md)
  (the promise of identical SVG), [src/core.ts](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/core.ts)
  (`render`), [src/text/measurer.ts](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/text/measurer.ts)
  (the metrics measurer), [tests/support/corpus.ts](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/support/corpus.ts)
  (how Pele gathers its corpus).
- The tools of this step: `tools/corpus.mjs`, `tools/oracle.mjs`, `tools/difftest.nim`,
  `tests/test_difftest.nim`, `docs/pele.nim`.
"""

nbSave
