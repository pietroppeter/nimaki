## devlog: 12 Nov 2026 A | A stage for a port | Where nimaki starts: Pele pinned at 1.13.0, the shape borrowed from gleam-in-nim, and the pages, data and rules every later step builds on.
## kind: tooling
import std/[strutils, strformat, json, os]
import nimib
import ../blocks, ../site

nbInit
nb.usePost()

let cov = loadCoverage()
let roadmap = loadRoadmap()
let portmap = parseFile(docsDir / "data" / "portmap.json")

nbText: &"""
Pietro asked for [Pele](https://github.com/obsidianmd/pele), the Mermaid renderer Steph Ango
made for Obsidian, to be ported to Nim, step by step, with an explainer at every step and a
referee that checks the port byte for byte. The reference is {cov.tsCode.thousands} lines of
TypeScript, so this will take many steps and many sessions, by several threads working at once,
reviewed from a phone. Before the first line of renderer, the port needs a place to happen.
This post is about that place.

## The findings, first

- **The pin is Pele 1.13.0**, commit `{pin.shortCommit}` of {pin.date}. It is still the newest
  release on 12 November 2026, both as a git tag and on npm. It is written once, in
  `reference/PIN`, and every page of this site shows it in the footer.
- **The oracle is Pele's own npm package**, run in Node. Its `dist/pele.js` is byte-identical
  to what `npm run build` makes from the source at the pinned commit, so what we compare
  against is exactly what we read.
- **The shape is gleam-in-nim's**, Pietro's port of the Gleam compiler that started the same
  day: working rules for agents, a setup script, pages built by CI, a devlog, decision records,
  a roadmap and a coverage map, the review mode. Almost everything was copied and renamed: the
  port should spend its imagination on the renderer.
- **Two things are new**: the coverage map is a grid (every diagram type in three stages:
  parse, layout, render), and every roadmap step has an **owner**, so threads working in
  parallel claim a step before they start and nothing is ported twice.
"""

nbText: """
## The pin

A port of a moving target needs one fixed version to be right about. Pele moves fast: 1.0.1 came
out on 6 October 2026 and 1.13.0 on 31 October. The pin is one small file that the tools, the
fetch script and the footer of every page read:
"""

nbCode:
  for line in readFile(repoDir / "reference" / "PIN").splitLines:
    if line.len > 0 and not line.startsWith("#"): echo line

nbText: """
`reference/fetch.sh` clones the source at that commit (and fails if the tag points elsewhere)
and unpacks the npm package after checking its integrity hash. The source is what we read and
translate; the package is what we run to ask "what should the SVG be?". Before trusting the
package, it was compared with a build from source:
"""

nbNote """
`npm ci && npm run build` in a clone at `3a2f075` writes a `dist/pele.js` with SHA-256
`37bea500…ba15a51`, the same bytes as the `dist/pele.js` of the published `pele-1.13.0.tgz`.
Same for `dist/pele.global.js`, which is the file diagrammari vendors today. Checked on
12 November 2026, by hand, in the session that wrote this post.
""", nkDone, "Package and source agree"

nbText: """
## What there is to port

Pele keeps every diagram type in its own folder (`src/diagrams/<type>/`, with a parser, a model,
a renderer, and sometimes a layout), on top of a shared core: text measurement, an SVG builder,
the shared graph layouts, and the API. `tools/portmap.nim` lists every TypeScript file with its
lines of code (blank lines and comments not counted), and `tools/coverage_seed.nim` groups them
for the coverage map. The core, as this page is built:
"""

nbCode:
  for p in cov.core:
    echo p.id.alignLeft(9), align(p.code.thousands, 6), "  ", "▇".repeat(max(1, p.code div 150))

nbText: &"""
and the {cov.diagrams.len} diagram types, smallest first (lines for parse / layout / render):
"""

nbFold "Show the 33 diagram types":
  nbCode:
    for d in cov.diagrams:
      echo d.id.alignLeft(14), align(d.code.thousands, 6), "   ", align($d.parse.code, 5), " /",
        align($d.layout.code, 5), " /", align($d.render.code, 5), "   corpus ", d.corpus

nbText: &"""
{portmap["files"].len} TypeScript files, {portmap["code"].getInt.thousands} lines of code. The
split into stages goes by file name and is a first guess: most types have no layout file and lay
themselves out inside `render.ts`. The thread that explains how Pele is built will correct it.
Each lamp below is a part of the core or a diagram type; it turns yellow when its port starts
and lights up when the Nim draws the same bytes as Pele:
"""

nbPipeline cov.pipeline

nbText: """
## Where the shape comes from

gleam-in-nim had already worked out, the same morning, how a long port is run with nimib and an
AI agent, and its first post, [A stage for a long port](https://pietroppeter.github.io/gleam-in-nim/devlog/workflow/),
traces that to five earlier projects of Pietro's (tabelline, nanuq, parloku, cicak, cadero) and
to *Operetta*, his sketch of the parts such a project picks. A port of a reference picks all of
them. Here is what was taken, and what changed on the way:

| Part | From gleam-in-nim | What changed for nimaki |
| --- | --- | --- |
| `AGENTS.md`, also a page | the rules, nearly as they were | TypeScript instead of Rust; claim a step before starting; Start and Stop |
| `tools/setup.sh` | Nim nightly, PCRE, `deps.lock` | also fetches the pinned Pele and checks Node |
| Pages built by CI | `docs/all.nim`, links and drift checks | Node in CI, for the referee |
| Devlog with letters | unchanged | |
| Decision records | the first eight, adapted | Pele as oracle, byte for byte with the same text measurer, MIT, merging, pie first |
| Roadmap | phases and milestones | an `owner` per step, steps for every diagram type |
| Coverage map | stages × modules | diagram types × parse, layout, render, plus the core |
| The look | Lucciola, as a placeholder | the theme thread is designing nimaki's own |
| Review mode | tabelline's, copied unchanged | |
| Blocks | `nbNote`, `nbCards`, `nbFold`, `nbPipeline` | `nbSvg` for drawings, `nkPele` notes, a Mermaid highlighter |

## A tour of the pieces

**The devlog.** One step, one post, one notebook, and a post says who it is in its first two
lines. Adding a post is adding a file and one import in `docs/all.nim`. The devlog as this page
is built:
"""

nbCode:
  for p in devlogPosts():
    echo p.date, " ", p.letter, "  ", p.kind.alignLeft(9), p.title

nbText: """
**The living pages** read their data from `docs/data/` and change in the pull request that
changes the facts: the [roadmap](../../roadmap/), the [coverage map](../../coverage/), the
[porting guide](../../porting/) and [the rules for agents](../../agents/).

**The decisions.** Every choice a later session could make differently is a short dated record
on the [Decisions](../../decisions/) page, with the wanted divergences from Pele underneath
(none yet). The ones that shape everything else: Pele at the pin is the specification and its
package the oracle (0003); a part is done when the SVG is identical byte for byte, with the
same text measurer (0004); threads merge their own pull requests and Pietro steers with Start
and Stop (0009); pie first, then flowchart (0010).

**Notes** come in kinds, so a reader skimming a port step can find what they are after:
"""

nbNote "How Pele (or Mermaid) does it: a quote of the TypeScript, a behaviour, a test.", nkPele, "nkPele"
nbNote "How the port does it, and why it differs where it does.", nkNim, "nkNim"
nbNote "What was verified, and against what.", nkDone, "nkDone"
nbNote "Something to watch out for.", nkWarning, "nkWarning"
nbNote "An open question, for Pietro or for a later step.", nkQuestion, "nkQuestion"

nbText: """
**Code** is highlighted when the page is built, with no script and no CDN. Mermaid joined the
languages, since every post will be full of it:

```mermaid
%% the smallest diagram type, and the first one to port
pie title What a pie needs
  "text measurer" : 675
  "SVG builder" : 1751
  "pie itself" : 328
```

```ts
// src/text/measurer.ts: what the referee and the port must agree on
export interface TextMeasurer {
  width(text: string, size: number, style: number): number;
}
```

## The roadmap, and claiming a step

Several threads start today: one designing the look, two doing research, and this one. Soon a
thread will port the core and pie. To keep them off each other's work, every step of the roadmap
has an `owner`: a thread claims a step by writing its title there, in a small pull request
merged before it starts. The roadmap as this page is built:
"""

nbCode:
  for phase in roadmap:
    var owned = 0
    for s in phase.steps:
      if s.owner.len > 0: inc owned
    echo "Phase ", phase.id, ": ", phase.title, " (", phase.steps.len, " steps, ", owned, " claimed)"

nbText: """
## What was checked, and what was not

- The site builds from a clean clone with `sh tools/setup.sh` and `nim r docs/all.nim`, in CI
  too; links inside the site and the drift check pass.
- The pin was checked against GitHub's tags and npm's versions; the package against a build
  from source.
- The line counts come from the pinned checkout and are recomputed by tools; the split into
  stages is a guess by file name.
- The look is borrowed and will change. The referee, `tools/difftest.nim`, comes in the next
  step of this thread, with its own post.

## What this changes for the port

- Every thread has one way to explain a step, and Pietro one way to review it.
- A session that starts cold runs the setup, reads `AGENTS.md` and the roadmap, and knows what
  is done, what is next and who is on it.
- The pin is one file. Moving it later is a step of its own, with a post.

## Sources

- [Pele](https://github.com/obsidianmd/pele) at the pin: `AGENTS.md`, `package.json`,
  `src/`, `tests/corpus/`; and the npm package [pele](https://www.npmjs.com/package/pele).
- [gleam-in-nim](https://github.com/pietroppeter/gleam-in-nim): `AGENTS.md`, `docs/`, `tools/`,
  `.github/workflows/pages.yml`, its decision records, and its first post.
- [tabelline](https://github.com/pietroppeter/tabelline), where the review mode and the tables
  come from, and [nimib](https://github.com/pietroppeter/nimib), which makes every page.
"""

nbSave
