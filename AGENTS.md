# Working on nimaki

Notes for coding agents (and people) changing this repository: a port of
[Pele](https://github.com/obsidianmd/pele), the Mermaid renderer, from TypeScript to Nim, made one
explained step at a time. This file holds the working rules. It is rendered on the site as *For
coding agents*, so a change here is reviewed like any page. It is adapted from
[gleam-in-nim](https://github.com/pietroppeter/gleam-in-nim)'s.

## The goal, and the reference

- Port a snapshot of Pele to Nim. The snapshot is pinned in `reference/PIN`: Pele `1.13.0`,
  commit `3a2f075ee0c3d914f0fad3545fc0f193693975ac` (30 October 2026), npm package
  `pele@1.13.0`, which draws the diagram types of Mermaid 12.1.0. Every page shows the pin in its
  footer, read from that file. `reference/fetch.sh` fetches the source and the package.
- Pele at the pin is the specification, and its npm package run in Node is the oracle. When the
  Nim and Pele disagree, the Nim is wrong, unless `docs/divergences.md` says the difference is
  wanted (decisions 0003, 0004).
- Pele is MIT, and so is this repository (`LICENSE`, `NOTICE`). A file ported from it starts with
  a header naming the TypeScript file it comes from (`## port-of:`). Check the licence of
  anything else before reading it closely or reusing it, and keep copyright notices.
- Everything outside this repository is read only: no issues, comments or pull requests on Pele,
  Mermaid, diagrammari or any other project. Changes to diagrammari are proposed in a post.

## Steps

- The work goes in steps. A step is a well defined task (research, a plan, a piece of the port,
  tooling), small enough to verify, and it ships with an explainer: a devlog post.
- **Every big task gets a devlog post** (Pietro's standing rule, 12 November 2026): a step, a tool,
  a piece of infrastructure, a research finding, a replan. If a pull request does something a
  reader would want explained, it carries the post that explains it; small fixes do not need one.
- **Claim before you start.** The roadmap (`docs/data/roadmap.json`, page *Roadmap*) lists the
  steps with an `owner` field. A thread claims a step by setting `owner` to its thread title and
  `status` to `started`, in a small pull request merged first, so no step is done twice. A step
  that is not on the roadmap is added there the same way.
- One branch and one pull request per step, with the code and the post together. A thread may
  review and merge its own pull request when CI is green; rebase on `main` first (decision 0009).
  Tags and releases wait for Pietro.
- The pull request that ships a step sets its `status` to `done`, `post` and `pr` in the roadmap;
  the one that ports a part updates its row in `docs/data/coverage.json`. Both are living pages
  (Roadmap, Coverage map), so the site always says where the port stands.
- The work must survive a session reset. What a later session needs is in the repository (this
  file, the roadmap, the coverage map, the devlog, decision records), not in a chat (decision 0008).

## Start and Stop

- Pietro pauses and resumes the project with "Stop" and "Start". On Stop: finish the smallest
  safe unit, commit and push, open or update a draft pull request, write in the roadmap where the
  step stands (its `what` or a note in the post), and stop. On Start: `sh tools/setup.sh`, read
  the roadmap, continue the step you own.

## Porting

- Read the porting guide (`docs/porting.nim`, the page *Porting guide*) before porting a file,
  and the decision records (`docs/decisions/`, the page *Decisions*) before choosing anything a
  later session could choose differently. A new choice of that kind is a new record
  (`docs/decisions/NNNN-slug.md`: front matter with title, status, date; then Context, Decision,
  Consequences); a record is not rewritten, a new one supersedes it.
- A ported Nim file (in `src/` or `tests/`) starts with `## port-of: <path of the TypeScript
  file in the Pele repository>` and `## port-status: draft`, then `conformant` once difftest,
  the fuzzer and Pele's own tests agree (decision 0014; a second reading, `verified`, is
  optional). A file that ports only a part of a TypeScript file says `## port-part-of:`.
  `nim r tools/portmap.nim` builds the port map from these headers (`docs/data/portmap.json`);
  run it in the pull request that ports or advances a file.
- `src/` must also compile with `nim js` (decision 0013): `nim r tools/difftest.nim --js` compares
  the JavaScript build with Pele, and CI runs it. The porting guide lists the Nim that only C runs.
- `src/diagrams/pie/parser.ts` becomes `src/nimaki/diagrams/pie/parser.nim`. The public entry
  point is `src/nimaki.nim` (`render(text, options)`), as Pele's `src/core.ts` is.
- A part is done when `nim r tools/difftest.nim <type>` finds the Nim SVG identical, byte for
  byte, to Pele's run in Node, with the same text measurer (Pele's `metricsMeasurer`), a fixed
  `now` and `TZ=UTC`. A wanted difference is an entry in `docs/divergences.md`.
- The tools find the Pele checkout in `reference/pele` or `$PELE_REF`, and the npm package in
  `reference/npm/package` or `$PELE_PACKAGE`. They print a few lines, one `ERROR ...` line per
  problem, and a summary last; anything slow takes `--fast:N` (decision 0006).

## Setup

- In a fresh checkout or sandbox, run `sh tools/setup.sh` first. It installs what is missing
  (Nim from GitHub nightlies, PCRE for the pages), clones the dependencies at the commits
  of `deps.lock` into `deps/` (not committed; `nim.cfg` puts them on the path) and fetches the
  pinned Pele (`reference/fetch.sh`; Node 20 or later must be installed). Safe to rerun.
- `nim r tests/all.nim` runs the tests. `nim r docs/all.nim` builds every page. The HTML is not
  committed: CI builds it and deploys `docs/` to GitHub Pages from `main`.
- The renderer (`src/`) needs Nim's standard library and one dependency, nitely's pure Nim
  `regex` (with its tables, `unicodedb`), pinned in `deps.lock` (decision 0015). nimib and
  tabelline are for the pages.
- To change a dependency, change its commit in `deps.lock` (and `nim.cfg` for a new one), rerun
  the setup, build the pages.
- Network: GitHub, registry.npmjs.org and the Nim nightlies are enough. If a step needs another
  host, list it for Pietro and carry on without it.

## Layout

```
src/nimaki.nim          the entry point: render(text, options)
src/nimaki/             the port, paths after Pele's src/ (diagrams/<type>/, layout/, svg/, text/)
tests/                  tests; tests/all.nim runs them all
corpus/cases.json       the referee's inputs, built from Pele by tools/corpus.mjs (rebuilt only when the pin moves)
corpus/diagrammari.json the Mermaid text of diagrammari, by tools/corpus_diagrammari.nim (pin: reference/DIAGRAMMARI)
reference/              PIN (the snapshot), DIAGRAMMARI, fetch.sh; pele/, npm/, diagrammari/ are fetched, not committed
tools/                  setup.sh and the tools of the port (difftest, oracle.mjs, portmap...)
docs/                   the site: every page is a nimib notebook
  all.nim               builds every page in one program; a new page adds its import here
  theme.nim             the look: fonts, colours, every CSS rule
  blocks.nim            the blocks of the pages, the pin, and usePage / usePost
  site.nim              the data the living pages share
  review.nim            the review mode (tabelline's, copied unchanged), assets/review.js
  data/                 roadmap.json, coverage.json, portmap.json
  decisions/NNNN-*.md   the decision records; decisions.nim is their page
  divergences.md        the wanted differences from Pele (shown on the Decisions page)
  porting.nim           the porting guide: how TypeScript is written in Nim here
  devlog/<slug>.nim     a post; devlog/data/<slug>/ its data, images and reference code
```

## A devlog post

- One notebook, `docs/devlog/<slug>.nim` (snake_case; `a_stage_for_a_port.nim` is served at
  `devlog/a-stage-for-a-port/`), and one line for it in `docs/all.nim`.
- Its first line is `## devlog: 12 Nov 2026 A | Title | One-sentence lede.` The letter orders
  the posts of one day (A, B, C, in the order they were written, which is the order to read
  them in): take the next free one, also counting the posts of open pull requests. Two posts of
  one day with the same letter fail the build.
- Its second line is `## kind: research` (or `plan`, `port`, `tooling`).
- After `nbInit`, call `nb.usePost()`: it sets the output file, the look, the title, the
  contents and the review mode. Then Markdown and blocks, then `nbSave`.

```nim
## devlog: 12 Nov 2026 C | Pie, explained | How Pele draws a pie, and how the port does.
## kind: port
import nimib
import ../blocks

nbInit
nb.usePost()

nbText: """
## First section
Markdown here.
"""

nbSave
```

- A post tells one step as it happened. It is dated and not rewritten afterwards; typos, links
  and small corrections are fine. What must stay true goes in a living page or in this file.
- Lead with the findings. Readable on a phone in ten to fifteen minutes; long listings and raw
  data go in `nbFold`. End with `## What this changes for the port` and `## Sources`.
- Pietro has never written a parser or a layout engine: explain each concept from scratch, with
  a small example that runs on the page.
- Nim code that can run, runs (`nbCode`), so the page proves itself. Numbers in the text come
  from code or a data file, not typed by hand. Code in other languages is a fence with its
  language (`ts`, `js`, `mermaid`, `sh`, `json`, `rust`, `python`), highlighted at build time.
- Diagrams in a post can be drawn by Pele itself, run in Node at build time (`peleSvg` in
  `docs/pele.nim`), and, once ported,
  by nimaki: `nbSvg(svgText, caption)` shows SVG text inline.
- Say what was checked and what was not. A claim about Pele, Mermaid, a tool or a person links
  its source. If a source could not be read, say so.

## Pages

- **Blocks, not HTML.** A page is Markdown in `nbText`, nimib's blocks, tabelline's `nbTable`
  and the blocks of `docs/blocks.nim`: `nbTitle`, `nbToc`, `nbNote(text, kind, title)`,
  `nbCards`/`nbCard`, `nbFold`, `nbSvg`, `nbPipeline`, `status`. No HTML tags in `nbText`, no CSS
  and no colours in a page. What is needed a second time becomes a block in `docs/blocks.nim`,
  and its CSS goes in `docs/theme.nim`, from the tokens. `nbRawHtml` is a last resort, with a
  comment saying why.
- Notes have kinds: `nkPele` for how Pele (or Mermaid) does it (primary colour), `nkNim` for how
  the port does it and why it differs (secondary), `nkDone` for what was verified, `nkWarning`,
  `nkQuestion` for what is open (for Pietro or a later step), `nkInfo`, `nkPlain`.
- Tables: a Markdown table for a few rows of text; tabelline (`tabella(rows): ...` with
  `optCssTheme()`, then `nbTable t`) for data.
- The look is Pomice (`docs/theme.nim`; the post *Pomice, the look of nimaki* explains it), in
  two modes, giorno and notte, from six colour tokens per mode: paper (pumice), ink (basalt),
  primary (lava: Pele, and what is being ported now), secondary (the sea: nimaki, Nim, links),
  warning (sulphur, never text), success (olivine: done). Pele's diagrams read the same tokens
  through `--pele-*` (`.pele`). Check a new block in both modes and at 390px wide.
- Every page shows its own notebook, folded in the footer (*Show the nimib source of this
  page*), and the Pele pin: nothing to do in a page, `usePage` does it.
- No remote assets: fonts, scripts and styles are in `docs/assets/`. `-d:singleFile` inlines
  them, for a page that must work alone.
- A living page (home, roadmap, coverage map, porting guide, this one) is kept up to date and
  reads its data from `docs/data/`. A new living page gets a card on the home page.
- Every link leads somewhere. Pages are served as `<name>/index.html`, so a post links the
  roadmap as `../../roadmap/` and another post as `../<slug>/`. After building the pages,
  `nim r tools/links.nim` checks every link inside the site (files and `#anchors`) and to files
  of this repository; `nim r -d:ssl tools/links.nim --external` asks other sites too (404 and
  410 fail). CI runs the first on every run and the second once a week.
- `nim r tools/drift.nim --fail --allow:docs/theme.nim --allow:docs/blocks.nim
  --allow:docs/review.nim docs/` (in CI) fails when a page holds HTML, a style, a script or a
  hex colour.

## Review mode

- Every page has it (`usePage`, `usePost`): *Version N · updated D* under the lede, and
  **✎ Review** beside it. The version is the number of commits that changed the page's source,
  so CI checks out the whole history.
- Pietro selects text, comments, and exports the comments as Markdown with a YAML block
  (`format: nimib-review/5`). When such an export is pasted in a chat, follow the skill
  `.claude/skills/nimib-review/`.
- `docs/review.nim` and `docs/assets/review.js` are tabelline's, copied unchanged
  (`docs/assets/REVIEW_VERSION` has the commit). Do not edit them here: change the review mode
  in tabelline, then `sh tools/sync_review.sh`.

## Tone and privacy

- This is built in public. Professional, playful, kind to every project and person named;
  credit sources and people for their work. nimaki is Pele's older sister in the story, not her
  rival: never frame the port as competing with Pele.
- The site says in its footer that the project is independent and not affiliated with Obsidian,
  Pele or Mermaid. Do not use their logos.
- Nothing personal about Pietro goes in the repository or on the site, beyond his being the
  author and reviewer.

## Handing work to Pietro

- He reviews on his phone. A reply that delivers a page links it rendered (the GitHub Pages
  URL after merge; before, a published preview), and links the pull request.
- A visual change comes with a phone-width screenshot.
