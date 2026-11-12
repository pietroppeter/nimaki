## devlog: 12 Nov 2026 C | Pele, a volcano in four weeks | Why kepano built a new Mermaid renderer for Obsidian, how fast it moved, and how it is tested.
## kind: research
import std/[json, os, strformat, strutils, sequtils, algorithm]
import nimib
import ../blocks

nbInit
nb.usePost()

const dataDir = currentSourcePath().parentDir / "data" / "pele_origins"
let facts = parseFile(dataDir / "facts.json")

proc readTsv(name: string): seq[seq[string]] =
  ## Rows of a tab separated file, header dropped.
  for line in lines(dataDir / name):
    if line.len > 0: result.add line.split('\t')
  result.delete 0

let
  releases = readTsv("npm_releases.tsv")         # version, published (UTC)
  perDay = readTsv("commits_per_day.tsv")        # date, commits
  people = readTsv("contributors.tsv")           # commits, author
  cves = readTsv("mermaid_cves.tsv")             # cve, published, diagram, kind, fixed_in
  tests = facts["tests"]
  totalCommits = perDay.mapIt(parseInt(it[1])).foldl(a + b)
  kepanoCommits = parseInt(people[0][0])

nbText: &"""
## The short version

Pele is the program we are porting, so the first question is where it comes from. In short:

- **Steph Ango (kepano), CEO of Obsidian, wrote Pele** so that Obsidian could stop shipping
  Mermaid. His reasons, in his own words: Mermaid was "too big, too slow, and too hard to
  theme", and its diagrams had become a security worry for a notes app.
- **Pele shipped in Obsidian 1.15**, in early access on 22 October and for everyone on
  2 November 2026. Because Pele cannot run code, Obsidian removed the warning it had added
  three months earlier before showing a diagram.
- **It moved fast.** The public history starts on 5 October 2026 with all
  {facts["diagram_types"].getInt} diagram types, and {releases.len} npm releases followed in
  25 days, from {releases[0][0]} to {releases[^1][0]}. Our pin,
  **{facts["pin"]["version"].getStr}** (commit `{facts["pin"]["commit"].getStr}`), is still the
  latest release today.
- **It is tested against Mermaid itself.** Mermaid's own parser specs are copied into
  `tests/compat`, and {tests["oracle_tests"].getInt} *oracle* tests feed random inputs to both
  Pele's parser and the parser Mermaid generates from its grammar, and demand the same answer.
- **It is one person's project with a few helpers.** {kepanoCommits} of its {totalCommits}
  commits are kepano's. AI help is neither encouraged nor forbidden by its contribution policy;
  we read it and send nothing back.
"""

nbText: """
## Who made it, and why

Pele is by [Steph Ango](https://stephango.com), known online as kepano, the CEO of
[Obsidian](https://obsidian.md), the Markdown notes app. Obsidian had rendered Mermaid diagrams
for years: kepano wrote, in a reply quoted by
[GIGAZINE](https://gigazine.net/gsc_news/en/20261020-pele/), that Mermaid had been in Obsidian
"since July 2020 (0.7.6)" and that the team had upgraded it 15 times, from Mermaid 8.5.2 to
11.13.0.

He announced Pele on 17 October 2026
([Mastodon](https://mastodon.social/@kepano/117456888453951005),
[X](https://x.com/kepano/status/2111472054293913749)):

> This is Pele, my new rendering library for diagrams and charts, compatible with the latest
> Mermaid syntax. [...] In pursuit of making Obsidian insanely fast and cohesively designed, I
> always found the Mermaid library to be too big, too slow, and too hard to theme.

The post lists five promises: 100 to 500 times faster than mermaid.js, a bundle six times
smaller, no dependencies, easy theming, and layouts that respond to the width of the device.
Obsidian's own account [posted](https://x.com/obsdmd/status/2111476648784830943) that Pele
was made "for the next version of Obsidian".
"""

nbNote("""
The X posts could not be read from our sandbox (the site refuses automated readers). Their
text here comes from the Mastodon copy of the same post, from GIGAZINE, which reproduces
both the post and kepano's reply, and, for Obsidian's post, from the snippet a search engine
shows.
""", nkWarning, "What we could and could not read")

proc cveTable(): string =
  result = "| Published | Advisory | Diagram | What it allowed |\n|---|---|---|---|\n"
  for r in cves:
    result.add &"| {r[1]} | [{r[0]}](https://www.cve.org/CVERecord?id={r[0]}) | {r[2]} | {r[3]} |\n"

nbText: &"""
## The reason that is not in the headline: security

Speed got the headlines; the reply kepano wrote to a critic the same day says more. Quoted by
[GIGAZINE](https://gigazine.net/gsc_news/en/20261020-pele/), he wrote that Mermaid 12.1 "ships
with yet another layout engine (three now), and has a questionable safety record (see CVEs)",
and that "in Obsidian 1.13 we had to introduce a new toggle/warning because of potentially
unsafe Mermaid diagrams". His priorities: "performance, safety, theming, mobile-friendliness".

Why does a diagram need to be safe? Because in a notes app the diagram text comes from
anywhere: a shared vault, a pasted snippet, a plugin. Mermaid draws labels as HTML inside the
SVG, and over the years several diagram types let crafted text through.
[releasealert.dev](https://releasealert.dev/npmjs/_/mermaid/cves) lists {cves.len} advisories
for the `mermaid` package; {cves.countIt(it[1].startsWith("2026"))} of them are from 2026:

{cveTable()}

[Obsidian 1.13](https://obsidian.md/changelog/page/2/) (30 July 2026) answered with a one-time
banner asking you to confirm that Mermaid blocks should render, and turned diagrams off by
default. [Obsidian 1.15](https://obsidian.md/changelog/2026-11-02-desktop-v1.15.0/) removed that
again: "Diagrams are now shown without asking first, since Pele can't run code. The Show
Mermaid diagrams in notes setting has been removed." The developer notes add, plainly:
"Obsidian no longer includes Mermaid."

Pele's [security page](https://pele.run/security) says how: diagram text is escaped, links and
images are filtered by scheme (`javascript:`, `data:` and `vbscript:` are always blocked),
`click` callbacks are ignored, and there are limits on the size of the source (50,000
characters), of the SVG (4,000,000 characters) and on the edges of a flowchart (5,000).
"""

nbNote("""
Safety is a property the port must keep, not an extra. The escaping, the URL filters and the
limits are part of Pele's output, so the byte-for-byte check covers them; the limits also
belong in the porting guide, because a Nim string counts bytes where JavaScript counts UTF-16
code units.
""", nkNim, "For the port")

nbText: &"""
## What Pele promises

The [README](https://github.com/obsidianmd/pele) and the
[home page](https://pele.run) say it in a few lines: Pele "renders Mermaid diagrams to SVG. It
is small, synchronous, has no runtime dependencies, and uses CSS variables for colors and
fonts", and it "supports every diagram type built into Mermaid {facts["mermaid_target"].getStr}".

| | Pele | Mermaid.js |
|---|---|---|
| Bundle size, gzip | 230 kB | 1.6 MB |
| Render time | 0.05 to 0.3 ms | 6 to 82 ms |
| Direct dependencies | 0 | 23 |
| Small screens | adapts the layout | scales the diagram |
| Theming | CSS variables | theme configuration |

These are Pele's numbers, from its home page, not ours. One we can check: Mermaid
{facts["mermaid_target"].getStr} lists {facts["mermaid_runtime_dependencies_12_1_0"].getInt}
runtime dependencies in its `package.json` (d3, dagre-d3-es, elkjs, cytoscape, katex, dompurify
and more).

Three design choices matter most for us:

1. **Synchronous, no DOM.** Mermaid needs a browser to measure text. Pele measures text from
   tables of font metrics generated from TrueType files (`scripts/gen-metrics.mjs`), so it runs
   anywhere, including Node, and so will the port.
2. **Determinism.** Pele's `AGENTS.md`: "Identical inputs and text measurer must produce
   identical SVG." That one sentence is what makes a byte-for-byte referee possible.
3. **Its own look and its own layout.** The
   [compatibility page](https://pele.run/compatibility) says Pele "supports Mermaid syntax with
   its own layout engine and visual style": node positions, spacing and edge paths differ from
   Mermaid on purpose. So Pele, not Mermaid, is our specification.
"""

proc weekTable(): string =
  ## Commits per week since the first public commit.
  result = "| Week starting | Commits | npm releases |\n|---|---|---|\n"
  let days = ["2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"]
  for i, d in days:
    let next = if i + 1 < days.len: days[i + 1] else: "2026-11-02"
    let c = perDay.filterIt(it[0] >= d and it[0] < next).mapIt(parseInt(it[1])).foldl(a + b, 0)
    let r = releases.filterIt(it[1][0 .. 9] >= d and it[1][0 .. 9] < next).len
    result.add &"| {d} | {c} | {r} |\n"

nbText: &"""
## Four weeks of history

The git history begins on 5 October 2026 with an MIT licence and, in the same evening,
{perDay[0][1]} commits that add a flowchart parser with Mermaid's spec suite, the layout engine,
the SVG renderer, the website, and one by one all {facts["diagram_types"].getInt} diagram types.
The timestamps are minutes apart, which suggests the history was replayed from earlier private
work; that is our reading, not something the project says.

{weekTable()}

Every release is on [npm](https://www.npmjs.com/package/pele?activeTab=versions). There are
{releases.len} of them from {releases[0][0]} (6 October) to {releases[^1][0]} (31 October).
The brief that started this project counted 23: the npm page also lists a `1.0.0` from 2020,
but that is an unrelated earlier package that held the name `pele` before.
"""

nbFold("All npm releases"):
  nbText: "| Version | Published (UTC) |\n|---|---|\n" &
    releases.mapIt(&"| {it[0]} | {it[1]} |").join("\n")

proc peopleTable(): string =
  result = "| Commits | Author |\n|---|---|\n"
  for r in people: result.add &"| {r[0]} | {r[1]} |\n"

nbText: &"""
## Thirty-three, not thirty-four

Our first brief counted 34 diagram types and 43,711 lines in them. Pele's `src/diagrams/` has
34 folders, but one of them is `common/`, the helpers the types share (fitting text, scanning,
accessibility lines). The diagram types are 33, the same 33 rows as Pele's compatibility table,
and the same 33 folders Mermaid 12.1.0 has. The coverage map should have 33 rows plus one for
the shared code.

## People and policy

{people.len} people have commits in the snapshot:

{peopleTable()}

The [contribution guide](https://github.com/obsidianmd/pele/blob/main/CONTRIBUTING.md) has an
AI policy:

> Use of AI in contributions is neither encouraged nor prohibited. Code changes will be
> evaluated on their own merits. However, all PRs should be thoroughly human-tested and
> reviewed before submitting.

It would allow a human-reviewed pull request from us. We will not open one: Pietro's rule for
this project is that everything outside our repository is read only. Bugs we find in Pele go
in our divergences page, not in Pele's issue tracker.
"""

nbText: &"""
## How Pele is tested

This is the part that matters most for a port, because Pele's tests are our tests too.

- **Mermaid's specs, ported.** `scripts/sync-specs.mjs` copies Mermaid's parser specs from a
  Mermaid checkout at the pinned tag into `tests/compat/<type>/` and points their imports at
  small adapters, so Mermaid's own expectations run against Pele's parsers.
  {tests["compat_suites"].getInt} suites (one per type, plus a second one for the use case
  parser), {tests["compat_files"].getInt} files,
  {tests["compat_ts_lines"].getInt} lines. Cases Pele skips are listed with a reason in each
  `SKIPPED.md` ({tests["skipped_cases"].getInt} in all).
- **Differential fuzzing.** {tests["oracle_tests"].getInt} `oracle.test.ts` files build the
  parser Mermaid generates from its Jison grammar and compare it with Pele's on the corpus and
  on random mutations of it: the same tokens, the same accept or reject, the same calls into
  the model. `FUZZ` raises the number of mutations.
- **Render snapshots.** `tests/render/` holds {tests["render_files"].getInt} files
  ({tests["render_ts_lines"].getInt} lines) of SVG snapshots and checks. These are the closest
  thing to our referee.
- **Layout invariants.** `tests/layout/` checks properties instead of pixels: nodes do not
  overlap, edges end on their nodes.
- **A corpus.** `tests/corpus/` has {tests["corpus_files"].getInt} JSON files, one per type
  and one more of agentflow references, with {tests["corpus_diagrams"].getInt} diagrams taken from the examples of Mermaid's
  documentation.
"""

nbNote(&"""
Checked: the counts on this page come from the pinned commit and from npm, gathered on
12 November 2026 (the commands are in `docs/devlog/data/pele_origins/README.md`). Not
checked: Pele's speed and size claims, and the claim in kepano's reply as quoted secondhand.
""", nkDone, "What was verified")

nbText: """
## What this changes for the port

1. **The pin holds.** 1.13.0 (commit `3a2f075`, 30 October 2026) is still the latest npm
   release on 12 November. Pele moved fast in October and slowed down at the end of the month,
   so a later diff-and-port routine is worth planning but not urgent.
2. **The test suite is the plan.** The compat suites and the corpus come with Pele and are MIT,
   so the port can replay them per diagram type, and the corpus is the first input of the
   byte-for-byte difftest.
3. **Determinism is promised, so we can rely on it.** The text measurer is a pure function of
   metric tables, which the port can read from the same generated file.
4. **Safety is part of the output.** Escaping, filters and limits must match byte for byte;
   the limits count UTF-16 units, a pitfall for the porting guide.
5. **Pele is not Mermaid.** Where Pele and Mermaid differ, we follow Pele, and Mermaid's
   behaviour only matters through the specs that Pele chose to keep.

## Sources

- [obsidianmd/pele](https://github.com/obsidianmd/pele) at commit `3a2f075` (tag 1.13.0):
  `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `package.json`, `scripts/`,
  `tests/`, `website/src/content/`.
- [pele.run](https://pele.run): home, [compatibility](https://pele.run/compatibility) and
  [security](https://pele.run/security) pages.
- [The npm registry entry for pele](https://registry.npmjs.org/pele).
- kepano's announcement on [Mastodon](https://mastodon.social/@kepano/117456888453951005) and
  [X](https://x.com/kepano/status/2111472054293913749), his
  [reply](https://x.com/kepano/status/2111575190081847776), and Obsidian's
  [post](https://x.com/obsdmd/status/2111476648784830943) (the X posts read through the next
  source).
- [GIGAZINE, 20 October 2026](https://gigazine.net/gsc_news/en/20261020-pele/).
- Obsidian's changelog: [1.15 public](https://obsidian.md/changelog/2026-11-02-desktop-v1.15.0/),
  [1.15 early access](https://obsidian.md/changelog/2026-10-22-desktop-v1.15.0/),
  [1.13](https://obsidian.md/changelog/page/2/).
- Mermaid advisories: [releasealert.dev](https://releasealert.dev/npmjs/_/mermaid/cves), the
  GitLab advisory pages for
  [CVE-2025-54880](https://advisories.gitlab.com/npm/mermaid/CVE-2025-54880/) and
  [CVE-2025-54881](https://advisories.gitlab.com/npm/mermaid/CVE-2025-54881/).
- [mermaid-js/mermaid](https://github.com/mermaid-js/mermaid) at tag `mermaid@12.1.0`,
  `packages/mermaid/package.json`.
"""

nbSave
