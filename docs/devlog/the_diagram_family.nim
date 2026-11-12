## devlog: 12 Nov 2026 F | The family of diagram tools | Pele's siblings and ancestors: other Mermaid renderers, Graphviz, PlantUML, D2, Pikchr, ELK and dagre, and what we can borrow from each.
## kind: research
import std/[os, strformat, strutils, sequtils, algorithm]
import nimib
import ../blocks

nbInit
nb.usePost()

const dataDir = currentSourcePath().parentDir / "data" / "the_diagram_family"

proc readTsv(name: string): seq[seq[string]] =
  ## Rows of a tab separated file, header dropped.
  for line in lines(dataDir / name):
    if line.len > 0: result.add line.split('\t')
  result.delete 0

proc thousands(s: string): string = insertSep(s, ',')

let
  ports = readTsv("ports.tsv")   # name, repo, language, licence, created, stars, types, approach
  tools = readTsv("tools.tsv")   # name, kind, language, licence, layout, what it gets right, source
  rustPorts = ports.filterIt(it[2] == "Rust")
  born2026 = ports.filterIt(it[4].startsWith("2026"))

nbText: &"""
## The short version

Pele is not alone. It has older relatives that are not Mermaid at all, and a crowd of siblings
that, like it, re-implement Mermaid without a browser.

- **{born2026.len} of the {ports.len} Mermaid re-implementations we looked at were started in
  2026**, {rustPorts.len} of them in Rust and two in C#. All are MIT licensed (merman also
  Apache-2.0), so we may read them; none of them is our reference.
- **They differ in what they promise.** Some match Mermaid's look (merman, ariel-rs), some
  invent their own (Pele, beautiful-mermaid), some add terminal output (beautiful-mermaid,
  mmdflux). Pele is the one with all 33 types and its own look.
- **The ancestors set the ideas.** Graphviz's `dot` (layered layout, 1990s Bell Labs) is the
  grandparent of dagre, which Mermaid used for a decade; ELK replaced it in Mermaid 12.0. Pele
  uses neither, but its layout belongs to the same family, explained in the next research post.
- **Some test inputs are reusable**, licences permitting: merman's fixture tree and
  mermaid-rs-renderer's `.mmd` files are MIT. Pele's own corpus remains the first choice,
  because our referee is Pele's output, not anyone else's.
"""

proc portsTable(): string =
  result = "| Project | Language | Licence | Stars |\n|---|---|---|---|\n"
  for r in ports:
    result.add "| [" & r[0] & "](https://github.com/" & r[1] & ") | " & r[2] & " | " &
      r[3] & " | " & thousands(r[5]) & " |\n"

proc portsList(): string =
  for r in ports:
    let types = if r[6] == "-": "" else: r[6] & " types; "
    result.add "- **" & r[0] & "** (started " & r[4] & "): " & types & r[7] & ".\n"

nbText: &"""
## The siblings: Mermaid without a browser

Here is every re-implementation of Mermaid named in our brief, with Pele first. Stars and
dates come from GitHub on 12 November 2026; *types*, in the list below the table, is the number of
Mermaid diagram types the README claims, where it gives a number.

{portsTable()}

{portsList()}

A few stories are worth telling.

**beautiful-mermaid** is the closest relative. [Craft](https://craft.do) built it in January
2026 to draw diagrams in its AI agents, in chat and in the terminal, and its README lists the
same complaints Pele has: aesthetics, theming, no terminal output, heavy dependencies. It
renders six types, synchronously, themed with CSS variables, and its ASCII mode is a port of
Alexander Grooff's Go program [mermaid-ascii](https://github.com/AlexanderGrooff/mermaid-ascii).
Pele's own benchmark script (`scripts/bench.mjs`, flag `--compare`) times Pele against
beautiful-mermaid on the same inputs, and `beautiful-mermaid` is a dev dependency of Pele.

**merman** aims at the opposite: it "targets Mermaid 12.3.0 syntax, behavior, and SVG
structure", with Mermaid's own themes. It is the most used of the Rust ports
(crates.io counts about 256,000 downloads of
[the crate](https://docs.rs/crate/merman/latest)) and the editor
[Zed](https://zed.dev) uses it to preview Mermaid. Its `THIRD_PARTY_NOTICES.md` records, file
by file, what was translated, copied or used only as a behaviour reference: a model for our
own port headers.

**Selkie** says it "has been built entirely with coding agents, mostly Claude Code", guided by
an evaluation system that compares its output to mermaid-js. That is close to what we do, with
one difference: Selkie scores similarity, we demand identity.

**mmdflux** adds a third output besides SVG and text: MMDS, a JSON description of the laid out
diagram, "designed for tooling, adapters, and LLM/agent pipelines".

**Naiad** and **Mermaider** bring Mermaid to .NET without a JavaScript engine. Naiad's source
is MIT, but its binaries come with an
[Open Source Maintenance Fee](https://opensourcemaintenancefee.org) agreement: a reminder to
read the whole licence folder, not just `LICENSE`.
"""

nbNote("""
Pele says it targets Mermaid 12.1.0 "with its own layout and visual style". merman, ariel-rs,
Naiad and Mermaider try to look like Mermaid. Their output and Pele's are not comparable, so
none of them can be a referee for us. They are useful as readings of the Mermaid grammar, and
as other people's answers to the same porting problems.
""", nkInfo, "Why none of them is our reference")

proc toolsTable(): string =
  result = "| Tool | Kind | Licence | Layout |\n|---|---|---|---|\n"
  for r in tools:
    result.add "| [" & r[0] & "](" & r[6] & ") | " & r[1] & " (" & r[2] & ") | " & r[3] &
      " | " & r[4] & " |\n"

nbText: &"""
## The ancestors and the neighbours

Mermaid was not the first language for diagrams as text, and it is not the only one today.
These are the tools our brief asked about:

{toolsTable()}

**Graphviz** is where layered layout comes from in practice. Its `dot` program, by Emden
Gansner, Stephen North and colleagues at AT&T Bell Labs, draws directed graphs in four passes:
assign ranks, order nodes in each rank to reduce crossings, compute coordinates, draw splines.
The [paper](https://graphviz.org/documentation/TSE93.pdf) says it builds "on the approach of
Warfield, Sugiyama et al.", the method now called Sugiyama layout.

**dagre** took the same skeleton to JavaScript: its
[wiki](https://github.com/dagrejs/dagre/wiki) says "the general skeleton for Dagre comes from
Gansner, et al.", with crossing reduction after Jünger and Mutzel and coordinates after Brandes
and Köpf. Mermaid drew with it for ten years.

**ELK**, the Eclipse Layout Kernel, is a collection of layout algorithms that "doesn't render
the drawing but only computes positions". Its JavaScript build, `elkjs`, lives under the
[KIELER](https://github.com/kieler) organisation of Kiel University on GitHub, and is Mermaid's default layout since 12.0.

**PlantUML** is the older text-to-UML tool (Java, GPL with LGPL, Apache, EPL and MIT builds),
which by default hands layout to Graphviz. **D2** is a modern diagram language in Go; its
README offers three engines, dagre, ELK and TALA, and TALA, once Terrastruct's commercial
engine, now ships with D2 under the MPL-2.0. **Pikchr**, from the author of SQLite, is a "PIC-like
markup language" after the PIC language of Unix: no automatic layout at all, the author says where things go, and it is
"safe for use in internet-facing applications". **Kroki** is not a renderer but a service that
puts about thirty of these tools behind one HTTP API.
"""

nbNote("""
Graphviz and ELK are EPL-2.0, PlantUML is GPL, D2 is MPL-2.0: these are copyleft or weak
copyleft licences, different from Pele's MIT. Reading their papers and documentation to
understand an idea is fine; copying their code into nimaki is not, and nothing here needs it,
because Pele has its own layout. The MIT projects (dagre, mermaid-ascii, the Mermaid ports) may
be read closely, with credit.
""", nkWarning, "Licences before reading closely")

nbText: """
## What we can borrow

| From | What | Why it helps |
|---|---|---|
| merman | the habit of a notices file that says per file what was translated, copied or referenced | our `port-of` headers say the same for Pele |
| Selkie | an evaluation loop run by coding agents | we have the same loop, with identity as the bar |
| mermaid-rs-renderer, merman | `.mmd` inputs (MIT) for a fuzzing corpus beyond Pele's | inputs only; the expected output still comes from Pele |
| mmdflux | a JSON dump of the laid out diagram | a debugging aid: compare layouts before comparing SVG bytes |
| dagre wiki, Graphviz paper | readable accounts of layered layout | background for the layout post |
| Pikchr | a renderer meant to be safe on hostile input | the same stance as Pele's security page |

What we do not borrow is any layout code: Pele has its own, and the port follows Pele.
"""

nbText: """
## What this changes for the port

1. **The bar is higher than the family's.** The other ports compare pictures or score
   similarity; we compare bytes. That needs Pele in Node beside the Nim build, and it is the
   only way to know a port is done.
2. **A corpus can grow from the family.** MIT `.mmd` files from merman and
   mermaid-rs-renderer can feed differential fuzzing later, with Pele as the oracle.
3. **Licences are mixed.** The porting guide should list which projects are MIT (read freely,
   credit) and which are copyleft (read docs and papers, no code).
4. **A Nim Pele has a place.** No port in the family targets Pele, and none is in Nim. A Nim
   Pele compiled to C and to JavaScript would serve diagrammari, nimib and Python wheels from
   one source.

## Sources

- The repositories of [Pele](https://github.com/obsidianmd/pele),
  [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid),
  [merman](https://github.com/Latias94/merman),
  [mermaid-rs-renderer](https://github.com/1jehuang/mermaid-rs-renderer),
  [mmdflux](https://github.com/kevinswiber/mmdflux),
  [Selkie](https://github.com/btucker/selkie),
  [ariel-rs](https://github.com/rinfimate/ariel-rs),
  [Mermaider](https://github.com/nullean/mermaider) and
  [Naiad](https://github.com/Papyrine/Naiad): README and licence files of a shallow clone,
  12 November 2026; stars and creation dates from the GitHub search API; downloads from
  crates.io.
- [Graphviz about](https://graphviz.org/about/), [licence](https://graphviz.org/license/) and
  [dot](https://graphviz.org/docs/layouts/dot/) pages, and the
  [dot paper](https://graphviz.org/documentation/TSE93.pdf).
- [PlantUML FAQ](https://plantuml.com/faq), [D2](https://d2lang.com) and its
  [README](https://github.com/terrastruct/d2), [Pikchr](https://pikchr.org/home/doc/trunk/homepage.md),
  [ELK](https://eclipse.dev/elk/), [dagre wiki](https://github.com/dagrejs/dagre/wiki),
  [Kroki](https://kroki.io/), [mermaid-ascii](https://github.com/AlexanderGrooff/mermaid-ascii).
- The data behind the tables is in `docs/devlog/data/the_diagram_family/`.
"""

nbSave
