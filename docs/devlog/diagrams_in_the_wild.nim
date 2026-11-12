## devlog: 12 Nov 2026 G | Diagrams in the wild | What the 33 kinds of diagram Pele draws are for, where they come from, and where Mermaid text is written today.
## kind: research
import std/[os, strformat, strutils, sequtils]
import nimib
import ../blocks

nbInit
nb.usePost()

const dataDir = currentSourcePath().parentDir / "data" / "diagrams_in_the_wild"

proc readTsv(name: string): seq[seq[string]] =
  ## Rows of a tab separated file, header dropped.
  for line in lines(dataDir / name):
    if line.len > 0: result.add line.split('\t')
  result.delete 0

let
  roots = readTsv("roots.tsv")                  # pele_type, ancestor, who, when, first_use, source
  native = readTsv("native_integrations.tsv")   # name, url
  dated = roots.filterIt(it[3] != "-")

nbText: &"""
## The short version

A port is easier to care about when you know what it will draw. This post asks what Mermaid
diagrams are used for, by whom, and where the kinds of diagram come from.

- **Most kinds are older than computers.** Of the {roots.len} kinds of diagram we traced, the
  oldest is Priestley's timeline of 1765; Playfair's pie chart (1801), Venn's diagrams (1880)
  and Gantt's charts (1910s) followed. Mermaid gave them a text syntax, not a purpose.
- **Software is the main user.** Flowcharts, sequence, class, state and ER diagrams, C4 and
  architecture diagrams document systems; they are what people draw in READMEs, design docs and
  pull requests.
- **The rest of the list is the rest of work**: Gantt charts and kanban boards for projects,
  Wardley maps, Cynefin and quadrants for strategy, Ishikawa for quality, Sankey, pie, XY and
  radar for data, railroad diagrams for grammars, packet diagrams for protocols.
- **Mermaid is written where text is written.** Mermaid's own list names {native.len} platforms
  that render it natively, among them GitHub, GitLab, Azure DevOps, Notion, Obsidian,
  Docusaurus and Quarto.
- **The newest writers are machines.** Language models write Mermaid because it is text. That
  is why beautiful-mermaid exists, why mmdflux has a JSON output for agents, why Mermaid 12
  added `agentflow`, and part of why a diagram renderer must be safe on text nobody reviewed.
"""

proc rootsTable(): string =
  result = "| Pele type | Ancestor | Who, when |\n|---|---|---|\n"
  for r in roots:
    let w = if r[3] == "-": r[2] else: r[2] & ", " & r[3]
    result.add "| `" & r[0] & "` | [" & r[1] & "](" & r[5] & ") | " & w & " |\n"

proc usesList(): string =
  for r in roots:
    result.add "- `" & r[0] & "`: " & r[4] & ".\n"

nbText: &"""
## Where each kind comes from

For every diagram type of Pele we looked for the drawing it descends from, using Wikipedia
(linked in each row) and, for event modeling, its author's site. A dash means the source names
no inventor or date, and we did not fill the gap from memory.

{rootsTable()}
"""

nbFold("What each was first used for"):
  nbText: usesList()

nbText: &"""
{dated.len} of the {roots.len} rows have a date. Read them in order and a pattern appears:
statistics and engineering in the nineteenth century (timeline, pie, star plot, Venn,
Sankey), management in the early twentieth (Gantt, the Gilbreths' process charts), computing
from the 1940s (program flowcharts, state machines), databases and software design in the
1970s to 1990s (ER, message sequence charts, UML), and since 2000 strategy and architecture
(C4, Wardley maps, Cynefin, event modeling).
"""

nbNote("""
Pietro's diagrammari already tells this story at length, with pictures: its
[explainer](https://pietroppeter.github.io/diagrammari/explainer/) has a chapter on where each
kind of diagram comes from, from Priestley to Sugiyama, and the
[Diagrams series](https://pietroppeter.github.io/diagrammari/devlog/diagrams-series/) goes
further. This post keeps to what the port needs: which kinds exist and what they are used for.
""", nkInfo, "Read more")

nbText: """
## Five families of use

Grouping Pele's types by what people do with them:

| Use | Pele types | A typical place |
|---|---|---|
| Explaining software | flowchart, sequence, class, state, er, c4, architecture, block, requirement, usecase, packet, git, treeview, swimlane | a README, a design document, a pull request description |
| Planning work | gantt, kanban, timeline, journey, eventmodeling | a project wiki, a workshop |
| Deciding | quadrant, cynefin, wardley, ishikawa, mindmap, venn | a strategy memo, a retrospective |
| Showing data | pie, xychart, sankey, radar, treemap | a report, a notebook |
| Describing languages and agents | railroad, agentflow | language documentation, AI agent design |

`info` is the odd one out: it draws the version of the renderer, a test that Mermaid works.

Two of these places matter for our project directly. **Notebooks** are where nimib lives:
diagrammari draws Mermaid in nimib pages, and the explainers of this very site will draw their
diagrams with Pele, and later with nimaki. **Reports** are where data charts end up, and they
are often generated by a program: a natural use for a renderer that is a library, not a
browser.
"""

proc nativeList(): string =
  native.mapIt(&"[{it[0].split(':')[0]}]({it[1]})").join(", ")

nbText: &"""
## Where Mermaid is written today

Mermaid's documentation keeps a list of
[integrations](https://mermaid.js.org/ecosystem/integrations-community.html). At 12.1.0 it marks
{native.len} of them as rendering Mermaid natively:

{nativeList()}.

A few dates show how Mermaid spread:

- **GitHub** started rendering ` ```mermaid ` blocks in Markdown on
  [14 February 2022](https://github.blog/2022-02-14-include-diagrams-markdown-files-mermaid/).
  The diagram is drawn in an iframe by a GitHub rendering service, Viewscreen.
- **Obsidian** has rendered Mermaid since July 2020 and replaced it with Pele in
  [version 1.15](https://obsidian.md/changelog/2026-11-02-desktop-v1.15.0/), November 2026.
- **Zed**, the editor, previews Mermaid with merman, a Rust port
  ([merman's README](https://github.com/Latias94/merman)).
- Static site and documentation tools (Docusaurus, Quarto, Docsy, Slidev) render it at build
  time or in the page.

The list also has three entries under *LLM integrations*: tools and MCP servers that let a
language model create Mermaid diagrams.
"""

nbText: """
## The new authors: language models

Mermaid suits language models for the same reason it suited Knut Sveidqvist in 2014: it is
text. A model can write a sequence diagram in a chat answer, and the chat app draws it. This
is now a design goal of the tools in the family:

- beautiful-mermaid introduces itself as "built for the AI era": "Diagrams are essential for
  AI-assisted programming", in a terminal or a chat.
- mmdflux outputs MMDS, a JSON format "designed for tooling, adapters, and LLM/agent
  pipelines".
- Mermaid 12.0 added `agentflow`, a diagram type for "the agents that do the work, the flows
  they run, the tasks and tools inside those flows"
  ([docs](https://mermaid.js.org/syntax/agentflow.html)).
- Selkie and our own project are written by coding agents; Selkie's README says so plainly.

This changes the threat model. A diagram written by a model from a web page nobody read is
untrusted input, exactly the case Pele's security page is written for. A renderer that cannot
run code, escapes every label and limits the size of its input is the right tool for it.
"""

nbText: """
## What this changes for the port

1. **Software diagrams first.** Flowchart, sequence, class, state and ER are the diagrams most
   people write; the plan already puts flowchart right after pie, and these five should follow
   soon after.
2. **Docs and notebooks are the first users.** diagrammari and this site draw at build time in
   Nim: the first milestone that matters to a user is pie, flowchart, sequence and timeline,
   the four diagrammari builds today.
3. **Untrusted input is normal.** Fuzzing with model-written and mutated diagrams belongs in
   the verification plan, not only the corpus of documentation examples.
4. **Every type has a reader.** Even the odd ones (Cynefin, Wardley, railroad) have real users;
   the coverage map should treat all 33 the same.

## Sources

- Wikipedia, one article per row of the table above (linked there), read on 12 November 2026;
  [What is Event Modeling](https://eventmodeling.org/posts/what-is-event-modeling/) by Adam
  Dymitruk.
- [Mermaid's integrations list](https://mermaid.js.org/ecosystem/integrations-community.html),
  as `docs/ecosystem/integrations-community.md` at tag `mermaid@12.1.0`.
- [GitHub blog, 14 February 2022](https://github.blog/2022-02-14-include-diagrams-markdown-files-mermaid/).
- [Obsidian 1.15 changelog](https://obsidian.md/changelog/2026-11-02-desktop-v1.15.0/).
- The READMEs of [merman](https://github.com/Latias94/merman),
  [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid),
  [mmdflux](https://github.com/kevinswiber/mmdflux) and [Selkie](https://github.com/btucker/selkie).
- [Mermaid's agentflow syntax](https://mermaid.js.org/syntax/agentflow.html).
- [diagrammari](https://github.com/pietroppeter/diagrammari) and its
  [site](https://pietroppeter.github.io/diagrammari/).
- The data behind the tables is in `docs/devlog/data/diagrams_in_the_wild/`.
"""

nbSave
