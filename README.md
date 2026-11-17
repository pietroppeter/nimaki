# nimaki

nimaki is an engine that turns [Mermaid](https://mermaid.js.org) text (a few lines that
describe a flowchart, a pie chart, a sequence of messages...) into an SVG drawing, written in
[Nim](https://nim-lang.org).

```nim
requires "nimaki == 0.2.0"   # in your .nimble file
```

```nim
import nimaki
writeFile "pets.svg", render("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85").svg
```

## What it gives a Nim developer

- **A plain Nim function.** `render(text)` returns the SVG text and its size, at once: no
  browser, no Node, no other program to start. It fits a command line tool, a static site
  generator, a nimib page, a web server.
- **Every Mermaid diagram type**: all 33 of Mermaid 12.1.0, from flowcharts and sequence
  diagrams to gantt charts, class diagrams and mind maps.
- **Native and JavaScript from the same code.** `nim c` gives a native program; `nim js` gives
  a script for web pages and Node. `src/nimaki/web.nim` exposes `nimaki.render`, `nimaki.mount`
  (fits a drawing to its box, with zoom) and the rest of Pele's browser functions;
  `nim r tools/webbuild.nim` writes the minified files (`nimaki.js`, `nimaki-core.js` and one per
  type; `-d:nimakiTypes` picks a build's types).
- **More than a picture.** `parse(text)` gives the diagram as data (nodes, edges, labels) in
  Pele's model, as JSON; `detectType` and `supports` say what a text is. `maxWidth` fits a
  drawing to a phone.
- **Themed by the page.** Every colour in a drawing is a CSS variable with Pele's default as
  fallback (`var(--pele-line, #1f1f1f)`), so a page restyles it, light or dark, without drawing it
  again; Mermaid's own themes are ignored, as in Pele. The page
  [Theming](https://pietroppeter.github.io/nimaki/theming/) lists the variables and how to set them.
- **Small to depend on.** Its only dependency is nitely's pure Nim `regex` (with its Unicode
  tables). From other languages, the C interface (`src/nimaki/capi.h`: `nimaki_render`,
  `nimaki_parse`) does the same through a shared library.
- **Exact.** Each build draws the same bytes as [Pele](https://github.com/obsidianmd/pele) on
  all 2118 test diagrams of the corpus.

## How it is made

nimaki is a port of Pele, the Mermaid renderer by Steph Ango and Obsidian, from TypeScript to
Nim, made one explained step at a time and checked byte for byte against Pele run in Node. Pele
is the original and nimaki follows it. The native build is what Nim adds.

**Site:** https://pietroppeter.github.io/nimaki/ (devlog, roadmap, coverage map, decisions,
playground).

- The snapshot being ported is pinned in [`reference/PIN`](reference/PIN): Pele 1.13.0
  (commit `3a2f075`). Releases are in [`CHANGELOG.md`](CHANGELOG.md); the latest is 0.2.0.
- The working rules, for people and coding agents: [`AGENTS.md`](AGENTS.md).
- To work on it: `sh tools/setup.sh`, then `nim r tests/all.nim` (tests) and
  `nim r docs/all.nim` (the pages).

## The name

In Hawaiian stories Nāmaka is a goddess of the sea and Pele's older sister. When Pele dug her
fire pits down the island chain, Nāmaka's sea followed. nimaki is Nim plus Nāmaka: the sea once
more, after Mermaid, Pele and [mari](https://github.com/pietroppeter/diagrammari). It is an
independent port, made to learn, with every respect for Pele and its author: nimaki exists
because Pele was written first, and written well.

## Licence

MIT, like Pele. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE), which keeps Pele's copyright.
This project is not affiliated with Obsidian, Pele or Mermaid.
