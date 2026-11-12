## devlog: 12 Nov 2026 D | What Mermaid is | The language Pele reads: where it came from, its 33 diagram types, its grammars, and why it needs a browser.
## kind: research
import std/[json, os, strformat, strutils, sequtils]
import nimib
import ../blocks

nbInit
nb.usePost()

const dataDir = currentSourcePath().parentDir / "data" / "what_mermaid_is"
let facts = parseFile(dataDir / "facts.json")

proc readTsv(name: string): seq[seq[string]] =
  ## Rows of a tab separated file, header dropped.
  for line in lines(dataDir / name):
    if line.len > 0: result.add line.split('\t')
  result.delete 0

proc thousands(n: int): string = insertSep($n, ',')

let
  firsts = readTsv("diagram_firsts.tsv")   # release, date, folder
  grammars = readTsv("grammars.tsv")       # diagram, grammar, file
  jison = grammars.filterIt(it[1] == "Jison")
  langium = grammars.filterIt(it[1] == "Langium")
  langiumTypes = deduplicate(langium.mapIt(it[0].split('-')[0]))

proc yearCount(y: string): int = firsts.countIt(it[1].startsWith(y))

nbText: &"""
## The short version

Mermaid is the language Pele reads. To port Pele we need to know the language, not the
program that made it famous, but the program explains a lot about the language.

- **Mermaid is a text language for diagrams**, made by Knut Sveidqvist in 2014 so that
  documentation could be written, diffed and kept up to date like code. The first commit is
  dated {facts["first_commit"]["date"].getStr}.
- **It grew one diagram type at a time**, from flowcharts and sequence diagrams in 2014 to
  {firsts.len} types in Mermaid 12.1.0. {yearCount("2026")} of them arrived in 2026 alone.
- **Every type has its own grammar.** In 12.1.0, {jison.len} types are parsed by
  [Jison](https://github.com/zaach/jison) grammars, {langiumTypes.len} by
  [Langium](https://langium.org) grammars, and one by hand. There is no single Mermaid grammar.
- **mermaid.js draws in a browser.** It measures text through the DOM ({facts["getbbox_calls_12_1_0"].getInt}
  calls to `getBBox()` in 12.1.0) and lays out graphs with dagre or, since 12.0, ELK. Without a
  browser you need a headless one, which is why so many people have rewritten it.
- **It is everywhere.** GitHub, GitLab, Notion, Obsidian, Azure DevOps and dozens more render
  Mermaid blocks; the repository has {thousands(facts["stars_2026_11_12"].getInt)} stars and
  {facts["authors_at_12_1_0"].getInt} authors.
"""

nbText: """
## A lost Visio file

Mermaid started with a loss. Knut Sveidqvist, a Swedish software architect, told
[TechCrunch](https://techcrunch.com/2024/03/20/mermaid-chart-a-markdown-like-tool-for-creating-diagrams-raises-5-5m/)
that he lost a Microsoft Visio file and "had to redraw everything", and asked himself: "Can't
we have this as text?" It was, he said, "the time when markdown was starting to kick in". The
name comes from *The Little Mermaid*, which his children were watching at the time.

The idea has a name in Mermaid's [introduction](https://mermaid.js.org/intro/): *doc-rot*.
Diagrams drawn in a separate tool go stale because updating them is a chore. "The main purpose
of Mermaid is to help documentation catch up with development." A diagram written as text
lives next to the code, goes through the same review, and shows its changes in a diff.

Here is the whole idea in four lines. The text on the left is Mermaid; the drawing is what a
renderer makes of it.

```text
flowchart LR
  A[Mermaid text] --> B{Flowchart?}
  B -- Yes --> C[Pele]
  B -- No --> D[Mermaid]
```

From there, the milestones:

| When | What | Source |
|---|---|---|
| Nov 2014 | First commit, by Knut Sveidqvist | [e26c2a2](https://github.com/mermaid-js/mermaid/commit/e26c2a252789a456a30f1f150f1c513b49454363) |
| 2019 | Wins the JS Open Source Award for "the most exciting use of technology" | [Mermaid intro](https://mermaid.js.org/intro/) |
| Feb 2022 | GitHub renders Mermaid code blocks in Markdown | [GitHub blog](https://github.blog/2022-02-14-include-diagrams-markdown-files-mermaid/) |
| 2022 | Knut co-founds Mermaid Chart with Open Core Ventures | [Mermaid Chart page](https://mermaid.ai/open-source/ecosystem/mermaid-chart.html) |
| Mar 2024 | Mermaid Chart raises a 7.5 million dollar seed round (OCV, Sequoia, M12) | [TechCrunch](https://techcrunch.com/2024/03/20/mermaid-chart-a-markdown-like-tool-for-creating-diagrams-raises-5-5m/) |
| Sep 2026 | Mermaid 12.0: ELK becomes the default layout | [Layouts](https://mermaid.js.org/config/layouts.html) |
| Oct 2026 | Mermaid 12.1.0, the version Pele targets | [releases](https://github.com/mermaid-js/mermaid/releases) |
"""

nbNote("""
Mermaid the language and library stays MIT licensed. Mermaid Chart, the company, sells a
hosted editor and collaboration on top of it, and its page says the lead developers of Mermaid
have joined the company. Pele's specs and grammars in `tests/compat` come from the MIT library.
""", nkInfo, "Library and company")

proc firstsTable(): string =
  result = "| Year | Release | Folder in the source |\n|---|---|---|\n"
  for r in firsts:
    result.add &"| {r[1][0 .. 3]} | {r[0]} | `{r[2]}` |\n"

nbText: &"""
## Thirty-three diagram types, one at a time

Mermaid did not start with a plan for thirty-three languages. Each type was added when someone
needed it, often by a contributor, with its own syntax and its own folder in
`packages/mermaid/src/diagrams/`. We listed the folders of every release tag to find when each
one first appears:

{firstsTable()}

Three things stand out. The first eight years brought about a dozen types; the last three
brought twenty. Many of the new ones are not UML at all: business tools like Wardley maps and
Cynefin, data charts like Sankey, XY, radar and treemap, and in 12.0 `agentflow`, which
[describes](https://mermaid.js.org/syntax/agentflow.html) "the agents that do the work, the
flows they run, the tasks and tools inside those flows". And because each type was designed on its own, they share less than you
might expect: keywords, comments and the `%%{{init}}%%` directive are common, almost everything
else is not.
"""

nbNote("""
The dates are the release that first contains the folder, from git tags. A type often existed
as a beta in a pull request or under another name before that. `swimlanes` reuses the
flowchart; `info` is a tiny diagram that prints the version.
""", nkWarning, "How to read the dates")

proc grammarTable(): string =
  result = "| Grammar | Diagram types |\n|---|---|\n"
  result.add "| Jison | " & jison.mapIt(it[0]).join(", ") & " |\n"
  result.add "| Langium | " & langiumTypes.join(", ") & " |\n"
  for r in grammars:
    if r[1] notin ["Jison", "Langium"]:
      result.add "| " & r[1] & " | " & r[0] & " |\n"

nbText: &"""
## Two grammar machines, and a third

A *grammar* is a precise description of what valid text looks like: which words may follow
which. A *parser generator* reads a grammar and writes a parser for you. Mermaid uses two of
them, from two eras.

- **[Jison](https://github.com/zaach/jison)** is a JavaScript version of Bison, the classic
  Unix parser generator. A `.jison` file holds a lexer (rules that cut text into tokens) and a
  grammar of LALR rules, each with a bit of JavaScript that runs when the rule matches. The old
  diagram types use it.
- **[Langium](https://langium.org)** is a newer TypeScript toolkit for languages, built on the
  Chevrotain parser library. Since 2023 Mermaid has a separate package,
  [`@mermaid-js/parser`](https://www.npmjs.com/package/@mermaid-js/parser), and new diagram
  types write their grammar in `.langium` files there.
- One type, `usecase`, has a parser written by hand on top of Chevrotain.

In Mermaid 12.1.0:

{grammarTable()}

For us this matters in two ways. First, Pele does not use any of these: it has a hand-written
parser per type (the topic of the next research post). Second, Pele's tests use the Jison
grammars as an *oracle*: they generate Mermaid's parser and check that Pele's parser agrees
with it. A Nim port that wants the same safety net needs either those generated parsers in
Node, or Pele's own answers, which is what our byte-for-byte referee gives.
"""

nbText: &"""
## How mermaid.js draws, and why it needs a browser

A Mermaid diagram goes through four stages, and Pele has the same four, so they are worth
naming now:

1. **Parse** the text into a model: nodes, edges, labels, styles.
2. **Measure** every label: how wide and tall will this text be in this font?
3. **Lay out**: give every node a position and every edge a path.
4. **Draw**: write the SVG.

Stage 2 is the catch. mermaid.js measures text by putting it in the page and asking the
browser: in 12.1.0 there are {facts["getbbox_calls_12_1_0"].getInt} calls to `getBBox()` in
{facts["getbbox_files_12_1_0"].getInt} files, and `createText.ts` calls
`getComputedTextLength()`. That is exact for the fonts on that page, and impossible without a
browser. The official command line tool,
[mermaid-cli](https://github.com/mermaid-js/mermaid-cli), solves it by starting a headless
Chrome through Puppeteer for every run.

Stage 3 is borrowed. Mermaid has drawn its graphs with
[dagre](https://github.com/dagrejs/dagre) (through `dagre-d3-es`) for most of its life; since
12.0 the default is [ELK](https://eclipse.dev/elk/), the Eclipse Layout Kernel, compiled to
JavaScript as `elkjs`, and mindmaps use `cytoscape`. Mermaid 12.1.0 has
{facts["runtime_dependencies_12_1_0"].getInt} runtime dependencies in all.
"""

nbNote("""
Pele replaces both borrowed parts. Text is measured from font metric tables, so the same input
gives the same width everywhere, and layout is Pele's own layered, compound and lane code. That
is what makes Pele portable to Nim at all: there is no browser to emulate and no layout library
to port first.
""", nkNim, "For the port")

nbText: """
## Why so many people rewrite it

Search for "Mermaid in Rust" and you find half a dozen projects started in 2026 alone; the
companion post *The family of diagram tools* lists them. They all start from the same
complaints, which Pele's own story repeats:

- **A browser is heavy.** Rendering in CI, in a static site generator, in a terminal or in a
  native editor means shipping Chrome. mermaid-rs-renderer measures its speed against
  mermaid-cli in seconds, not milliseconds.
- **Asynchronous by design.** mermaid.js renders with promises because it waits for the page;
  an editor wants a function that returns an SVG.
- **Hard to theme.** Mermaid themes are configuration objects; apps want CSS variables that
  follow their own light and dark modes.
- **Security.** HTML labels in SVG are a door for script injection, and Mermaid's advisory
  history (in *Pele, a volcano in four weeks*) shows the door was used.
- **Size.** A bundle of 1.6 MB gzip, by Pele's measurement, is a lot for a note-taking app on
  a phone.

Mermaid's answer to some of this is the
[tiny build](https://mermaid.js.org/config/layouts.html) without ELK, and the `sandbox`
security level, which renders in an iframe. The rewriters' answer is to keep the language and
replace the program. Pele is the most complete of these in diagram types; a Nim Pele would be
another member of the family, with a stricter promise than most: byte for byte the same.
"""

nbText: """
## What this changes for the port

1. **The language is a set of languages.** The port goes one diagram type at a time because
   Mermaid itself is built that way; the shared parts are small (front matter, directives,
   comments, accessibility lines).
2. **The grammars are documentation, not code to port.** Pele's parsers are hand written; the
   Jison and Langium files explain the syntax and serve as an oracle in Pele's tests.
3. **No browser, no layout library.** The four stages (parse, measure, lay out, draw) are all
   Pele's own code, so the port has no dependency to replace.
4. **Mermaid keeps moving.** Mermaid is at 12.3.0 (3 November 2026), Pele targets 12.1.0. Our
   pin follows Pele, not Mermaid.

## Sources

- [mermaid-js/mermaid](https://github.com/mermaid-js/mermaid), cloned on 12 November 2026:
  release tags from 0.2.16 to `mermaid@12.3.0`, `packages/mermaid/package.json` and
  `packages/parser/` at `mermaid@12.1.0`, and the first commits of November 2014.
- [Mermaid's introduction](https://mermaid.js.org/intro/) and
  [layouts page](https://mermaid.js.org/config/layouts.html).
- [Mermaid (software)](https://en.wikipedia.org/wiki/Mermaid_(software)) on Wikipedia.
- [TechCrunch, 20 March 2024](https://techcrunch.com/2024/03/20/mermaid-chart-a-markdown-like-tool-for-creating-diagrams-raises-5-5m/).
- [The Mermaid Chart page](https://mermaid.ai/open-source/ecosystem/mermaid-chart.html) and
  [The Evolution of Mermaid](https://mermaid.ai/blog/posts/mermaid-chart-the-evolution-of-mermaid).
- [GitHub blog, 14 February 2022](https://github.blog/2022-02-14-include-diagrams-markdown-files-mermaid/).
- [mermaid-cli on npm](https://www.npmjs.com/package/@mermaid-js/mermaid-cli) (its peer
  dependency on Puppeteer).
- The data behind every number on this page is in `docs/devlog/data/what_mermaid_is/`.
"""

nbSave
