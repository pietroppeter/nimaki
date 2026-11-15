## devlog: 15 Nov 2026 E | Where the port stands | Every diagram type is drawn as Pele draws it. A look at what is left: three files that only a browser runs, one half of a file, a few dozen of Pele's tests, and the decisions that wait for Pietro.
## kind: plan
import std/[json, sequtils, strformat, strutils, os, algorithm]
import nimib
import ../blocks

nbInit
nb.usePost()

const docs = currentSourcePath().parentDir.parentDir
proc data(name: string): JsonNode = parseJson(readFile(docs / "data" / name))
proc thousands(n: int): string = insertSep($n, ',')

let
  portmap = data("portmap.json")
  totals = portmap["totals"]
  pele = data("peletests.json")
  counts = pele["counts"]
  roadmap = data("roadmap.json")
  files = toSeq(portmap["files"])
  allCode = portmap["code"].getInt
proc part(status: string): int = totals[status]["files"].getInt
proc lines(status: string): int = totals[status]["code"].getInt
proc share(status: string): string = formatFloat(100 * lines(status) / allCode, ffDecimal, 1) & "%"

var steps, done, open: int
var openSteps: seq[JsonNode]
for phase in roadmap["phases"]:
  for step in phase["steps"]:
    inc steps
    if step["status"].getStr == "done": inc done
    else: openSteps.add step
let notPassed = pele["tests"].getInt - counts["passed"].getInt

nbText: &"""
## The findings, first

- **{part("conformant")} of Pele's {portmap["files"].len} TypeScript files are ported and conformant**:
  {share("conformant")} of its {thousands(allCode)} lines of code, each proven equal to Pele by the
  referee, the fuzzers and Pele's own tests
  ([decision 0014](../../decisions/#0014-tests-and-fuzzing-make-a-file-conformant-without-a-second-reading)).
- **{part("todo")} files are not ported, all of them Pele's browser side**: putting a drawing in a
  page and letting a reader zoom it ({thousands(lines("todo"))} lines). One more is half ported: the
  text measurer, whose other half measures with a browser's canvas. Pietro's answer, this morning:
  later, after a first release.
- **{part("skip")} files are skipped on purpose**, each with its reason, written down today: most
  are how Pele is *packaged* for JavaScript (one module per diagram type, loaded on demand), which
  Nim does at compile time.
- **Pele's {thousands(pele["tests"].getInt)} tests: {thousands(counts["passed"].getInt)} pass on
  nimaki, none fail**, and the {notPassed} others are of four known kinds, below.
- **The roadmap: {done} of {steps} steps done.** The open ones are owned by running threads, and two
  new steps are written down: a package that other Nim programs can depend on, and the browser side.

## A plan that became a roadmap

The roadmap had a step called *The port plan* from the first day: the order in which the parts and
the diagram types would be ported, and how each would be checked. It was never written as a
document. The order was settled one step at a time on the [roadmap](../../roadmap/) itself, as
threads claimed the next type, and the checks were built as tools (the referee, the fuzzers, Pele's
tests). The plan was the roadmap.

So this step is a revision instead: three days in, every type is drawn as Pele draws it, and the
useful question is what is *not* done, and why. Two words first. The *port map* lists every
TypeScript file of Pele and the Nim file that ports it, read from a header at the top of each Nim
file (`## port-of:`); it is the [coverage map](../../coverage/)'s source. A *divergence* is a
difference from Pele that is wanted, written down with its reason.

## What the port map says

Before today the port map listed {part("todo") + part("skip") + 4} files as not ported. Most of them were not
missing work, they were missing bookkeeping:

- `src/diagrams/block/types.ts` and `src/diagrams/c4/types.ts` hold only types, and were ported
  long ago inside each type's `db.nim`, which said so in a comment but not in its header. Now the
  header says it.
- `src/index.ts` and `src/diagrams/registry.ts` register every diagram type with the core. nimaki
  does the same in `src/nimaki.nim`, which now says it ports them, and registers the types in
  Pele's order.
- The rest are skipped, and `docs/data/portmap_skip.txt` says why:
"""

block:
  var t = "| Pele's file | Lines | Why it is not ported |\n| --- | ---: | --- |\n"
  var reasons: seq[(string, int, string)]
  for f in files:
    if f["status"].getStr == "skip":
      let path = f["path"].getStr
      let key = if path.startsWith("src/entries/"): "src/entries/ (" & $files.countIt(
        it["path"].getStr.startsWith("src/entries/")) & " files)" else: path
      var found = false
      for r in reasons.mitems:
        if r[0] == key:
          r[1] += f["code"].getInt
          found = true
      if not found: reasons.add (key, f["code"].getInt, f["reason"].getStr)
  for (path, code, reason) in reasons:
    t.add "| `" & path & "` | " & $code & " | " & reason & " |\n"
  nbText: t

nbText: """
What is left is Pele's browser side:
"""

block:
  var t = "| Pele's file | Lines | What it does |\n| --- | ---: | --- |\n"
  let what = {"src/mount.ts": "puts a drawing in a page, redraws it when the page changes size or colours",
              "src/zoom.ts": "lets a reader zoom and pan a drawing with a mouse, a finger or the keys",
              "src/window.ts": "finds the window an element is in (a pop-up has its own)",
              "src/text/measurer.ts": "measures text: the table half is ported, the half that asks a browser's canvas is not"}
  for f in files:
    let status = f["status"].getStr
    if status in ["todo", "draft"]:
      var line = ""
      for (k, v) in what:
        if k == f["path"].getStr: line = v
      t.add "| `" & f["path"].getStr & "` | " & $f["code"].getInt & " | " & line & " |\n"
  nbText: t

nbText: &"""
nimaki's drawings come out the same as Pele's without these: where no canvas is available, as in
Node, Pele measures with the table too, and that is what the referee compares. They matter only for a page
that shows a drawing and lets a reader move it, the way Obsidian does. The JavaScript build could
port them; the C build has no page to put a drawing in.

## Pele's tests that do not pass

[Pele's tests, on nimaki](../pele-tests-on-nimaki/) explains how Pele's own tests run on the
port. Of the {notPassed} that do not pass, none fails:

| Kind | Tests | Why |
| --- | ---: | --- |
| `api` | {counts["api"].getInt} | They call `mount()` or zoom: the browser side above. |
| `speed` | {counts["speed"].getInt} | They draw the same, in the JavaScript build, but slower than Pele's time bound. The thread *Speed up the JavaScript build* owns them. |
| `known` | {counts["known"].getInt} | They test a behaviour the [Decisions page](../../decisions/) lists as a divergence, such as half of an emoji in a sankey name (Pele refuses it, nimaki draws it). |
| `canvas` | {counts["canvas"].getInt} | It measures text with a browser's canvas. |

## What is left, and who has it
"""

block:
  var t = "| Step | Status | Owner |\n| --- | --- | --- |\n"
  for s in openSteps:
    let owner = if s["owner"].getStr == "": "unclaimed" else: s["owner"].getStr
    t.add "| " & s["title"].getStr & " | " & s["status"].getStr & " | " & owner & " |\n"
  nbText: t

nbText: """
Two steps recur by design: the articles on nimaki's code and on a domain drawn in diagrams. One
waits for Pele: *Following Pele* has its tool running every week, and moves the pin when Pele
publishes its next release. *A package to depend on* is the new one. The [proposal for
diagrammari](../a-proposal-for-diagrammari/) sketches a `mari.nimble` that requires nimaki, pinned
in `atlas.lock`; today nimaki has no `.nimble` file, so that line would have nothing to find. *Pele's browser side* is the other new one, for later: the three files and the half above, for
the JavaScript build, done when Pele's `api` and `canvas` tests pass on it.
"""

nbNote """
- **Pele's browser side** (mount, zoom, the canvas half of the measurer): later. Asked on 14
  November; Pietro answered while this post was being written, on 15 November. It is now the step
  *Pele's browser side* in the table above, unclaimed.
- **A first release**: now, Pietro said in the same message, since every diagram type is done. It
  is being prepared in a thread of its own, *Tag first nimaki release*; the package step may well
  be part of it.
""", nkInfo, "Pietro's answers"

nbNote """
- `docs/data/portmap_skip.txt`: what is not ported and why.
- `src/nimaki.nim` ports `src/index.ts` and `src/diagrams/registry.ts`, and registers the types in
  Pele's order; `block/db.nim` and `c4/db.nim` name the `types.ts` they hold.
- The roadmap: *The port plan* is done, a phase *After parity* holds the new steps.
""", nkNim, "In the port"

nbNote """
- `nim r tools/portmap.nim check`: every `port-of` names a file of Pele.
- `tests/all.nim` and difftest of the whole corpus, after the registration changed order.
- That no file of Pele's `src/` imports `src/diagrams/agentflow/diagnostics.ts` (a search).
""", nkDone, "Checked"

nbText: """
## What this changes for the port

- The coverage map and the port map now show every one of Pele's files as ported, skipped with a
  reason, or waiting for the browser-side decision.
- The roadmap has a phase for what comes after parity, with two unclaimed steps in it.

## Sources

- The numbers on this page: `docs/data/portmap.json` (`nim r tools/portmap.nim`),
  `docs/data/peletests.json` (`nim r tools/peletests.nim`), `docs/data/roadmap.json`.
- Pele's files named above, at the pin: [`src/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src).
"""

nbSave
