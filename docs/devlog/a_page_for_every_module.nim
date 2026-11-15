## devlog: 15 Nov 2026 I | A page for every module | The islands of the coverage map are links now: each opens a page for its module, written from the port's own data. And five of them were orange for no reason.
## kind: tooling
import std/[json, strformat, sequtils]
import nimib
import ../blocks, ../site

nbInit
nb.usePost()

let cov = loadCoverage()
let portmap = parseFile(docsDir / "data" / "portmap.json")
let pages = cov.core.len + cov.diagrams.len

nbText: &"""
## The findings, first

- **Every island of the coverage map is now a link**, on the map and on the home page: {pages}
  pages, one for each part of the shared core ({cov.core.len}) and each diagram type
  ({cov.diagrams.len}). Try them here:
"""

nbModules(cov, "../../modules/")

nbText: &"""
- **Five islands were orange, and should not have been.** text, svg, layout, util and common were
  ported long ago, every file of them conformant. Their status on the map is written by hand in
  `docs/data/coverage.json`, and it still said *started*, as on the day of
  [First light](../first-light/). Pietro noticed it this morning. They are *done* now,
  with notes that say what is true today. Only *browser* stays grey: Pele's browser side, for later.
- **A module page is written from data**, like every living page: the files of the
  [port map](../where-the-port-stands/) with their status and links to both sources, what checks the
  module (the referee, the fuzzer, Pele's own tests), its three stages for a diagram type, and the
  posts that tell its story.

## What a module page holds

A *module* here is one island: a part of Pele that the coverage map counts on its own, such as
`text` (measuring text) or `flowchart`. Its page has:

- **its status and size**: how many of Pele's files it has, and how many lines are conformant,
  draft, not ported, or skipped on purpose;
- **the coverage map's notes** on it, the same words as in the map's tables;
- **what checks it**, for a diagram type: how many drawings of Pele's corpus and of diagrammari's
  come out identical, how many generated ones, and how many of Pele's tests for it pass;
- **its files**, one row each: Pele's file at the pin, its lines, its status, and the Nim file
  that ports it, both names linking to the source;
- **the posts about it**: the one the coverage map names, then the newest posts whose source
  names one of its Nim files.

Nothing on a page is typed by hand except the coverage map's notes, so the pages stay true as the
data changes: a file that becomes conformant changes its row the next time the site is built.
"""

nbNote """
- `docs/modules.nim` writes the pages, `docs/modules/<module>/index.html`, from `docs/data/`.
- `nbPipeline` takes a link for each island, and the whole island is the link (`docs/blocks.nim`,
  `docs/theme.nim`).
- `docs/data/coverage.json`: text, svg, layout, util, common and api are done, with new notes;
  browser names its plan.
""", nkNim, "In the port"

nbNote &"""
- The pages build, and `tools/links.nim` finds every link of the site leading somewhere.
- Seen at 390 pixels wide, in both modes: the files table fits a phone, with the names alone.
- The {portmap["files"].len} files of the port map each appear on exactly one module page:
  `docs/modules.nim` stops the build otherwise.
""", nkDone, "Checked"

nbText: """
## What this changes for the port

- The coverage map's islands lead somewhere: to the module, its files and its story.
- A pull request that changes a module's status in `coverage.json` changes its page too; nothing
  else to keep up to date.

## Sources

- The data: `docs/data/coverage.json`, `portmap.json`, `difftest.json`, `fuzz.json`,
  `peletests.json`, `roadmap.json`.
- The code: [`docs/modules.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/modules.nim).
"""

nbSave
