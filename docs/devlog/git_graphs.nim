## devlog: 12 Nov 2026 V | Branches on a page: git graphs | nimaki draws Mermaid's git graphs byte for byte as Pele does: a history replayed into commits and branches, lanes in their order, and connectors that look for a free strip between lanes.
## kind: port
import std/[strformat, strutils, json, tables, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
for r in difftest["types"]: cases[r["type"].getStr] = r["cases"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]

nbText: &"""
## The findings, first

- **Git graphs are done.** The {cases["gitGraph"]} corpus cases of `gitGraph` come out of nimaki
  identical to Pele's, byte for byte, and so do {fuzz["gitGraph"]["cases"].getInt.thousands}
  generated ones that CI now writes on every pull request.
- **No layout engine needed.** A git graph is a timeline with lanes: each commit takes the next
  place along the history and the lane of its branch. The work is in the rules of git itself,
  which the model replays, and in drawing connectors that do not run through other commits.
- **Pele makes Mermaid's random ids repeatable.** Mermaid gives a commit without an id a random
  suffix; Pele derives the suffix from the commit's number with a multiplicative hash, so the
  same text always draws the same graph. The port uses the same 32-bit arithmetic.
- **Four files, about 900 lines,** on the Langium-style tokenizer that pie, packet and radar
  already use. It matched on the first run.

## What a git graph is

Git keeps a project's history as *commits*, snapshots that each point back to the one before.
A *branch* is a line of work that starts from some commit; a *merge* joins two lines again; a
*cherry-pick* copies one commit onto another line. Mermaid's `gitGraph` writes such a history as
the commands that make it:
"""

let gitText = """gitGraph
  commit id: "init"
  commit tag: "v1.0"
  branch develop
  commit id: "feature"
  checkout main
  commit id: "hotfix" type: HIGHLIGHT
  checkout develop
  merge main
  commit
  checkout main
  merge develop tag: "v1.1"
"""

nbText: &"""
```mermaid
{gitText.strip}
```
"""

nbCode:
  let gitSvg = render(gitText).svg
  echo "identical to Pele's: ", gitSvg == peleSvg(gitText)

nbSvg gitSvg, "A small history, drawn by nimaki; Pele draws the same bytes."

nbText: """
## Replaying the history

The parser reads the commands into a list of statements, and `buildGit` replays them as git
would, keeping the current branch and the latest commit of each one. That is also where the
errors come from: a merge of a branch into itself, a checkout of a branch that does not exist,
a cherry-pick of a commit already on the current branch. Mermaid's messages are kept word for
word, odd spacing included (`Current branch (main)has no commits`), because they are part of
the output the referee compares:
"""

nbCode:
  for text in ["gitGraph\n  commit\n  merge main", "gitGraph\n  checkout nowhere",
               "gitGraph\n  commit id: \"a\"\n  cherry-pick id: \"a\""]:
    try:
      discard render(text)
    except PeleError as e:
      echo e.msg

nbText: """
## Drawing it

Each branch is a lane, in the order of its `order:` and then of its creation. Each commit is
placed one step after the one before, or, with `parallelCommits`, one step after its furthest
parent, and the step grows where a commit's tags or its id need more room. A connector between
two lanes leaves its parent at once when the child's lane is free from there on; when it is not,
it turns in just before the child; and when neither lane is free, it runs along the empty strip
between two lanes, past the ids of one and before the tags of the next.

A history that runs across is too wide for a phone, so, as flowcharts do, it turns to run down:
"""

nbCode:
  let narrow = render(gitText, RenderOptions(maxWidth: some(390.0)))
  echo "width ", narrow.width, ", identical to Pele's: ",
    narrow.svg == peleSvg(gitText, %*{"maxWidth": 390})

nbSvg narrow.svg, "The same history for a phone."

nbNote """
`Math.imul(salt, 0x9e3779b1) >>> 0` multiplies as 32-bit integers and keeps the low 32 bits;
in Nim that is plain `uint32` multiplication, which wraps the same way. The salt grows by the
same constant when an id is taken, and JavaScript's conversion to a 32-bit integer drops the
same high bits that `uint32` addition does.
""", nkNim, "In the port"

nbNote &"""
The {cases["gitGraph"]} corpus cases: identical. Generated inputs before merging: 3,000 and then
three times 5,000 histories on three seeds, identical. The generator tracks branches and commit
ids so that most histories are valid, then breaks a rule now and then; a little under half draw
a graph and the rest check Mermaid's error messages. CI runs
{fuzz["gitGraph"]["cases"].getInt.thousands} on every pull request.
""", nkDone, "Checked"

nbNote """
- Pele's compat specs for git (`tests/compat/git/`, ported from Mermaid) check the model; they
  are not ported, the corpus and the fuzzer check the drawing.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Git is done** on the [coverage map](../../coverage/) and the [roadmap](../../roadmap/).
- **Next, in this thread:** railroad, then gantt.

## Sources

- Pele at the pin: [`src/diagrams/git/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/git),
  read for this step.
- Mermaid's syntax: [gitGraph diagrams](https://mermaid.js.org/syntax/gitgraph.html).
- The code of this step: [`src/nimaki/diagrams/git/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/git),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
