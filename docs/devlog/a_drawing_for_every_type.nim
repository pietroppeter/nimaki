## devlog: 15 Nov 2026 J | A drawing for every type | Each diagram type's page now opens with a drawing of that type, made by nimaki and checked against Pele, and the coverage map tells the types from the core at a glance.
## kind: tooling
import std/[strformat, strutils]
import nimib
import ../blocks, ../site, ../pele

nbInit
nb.usePost()

let cov = loadCoverage()

nbText: &"""
## The findings, first

- **Every page of a diagram type now shows a drawing of that type**: {cov.diagrams.len} pages,
  {cov.diagrams.len} drawings. Each one is drawn by nimaki while the site is built, and Pele draws
  it too; the build stops if the two drawings are not the same bytes. Pietro asked for it this
  morning, after [A page for every module](../a-page-for-every-module/).
- **The coverage map shows two groups**, with a caption each: the shared core
  ({cov.core.len} parts, rounded islands) and the diagram types ({cov.diagrams.len}, square boxes,
  like the nodes of a diagram). Pietro suggested an emoji on the diagram pills; shown both, he
  chose the groups (below).

Here are the two groups, as on the home page and the coverage map:
"""

nbModules(cov, "../../modules/")

nbText: """
## Which drawing

Each page takes its example from the referee's corpus, the Mermaid texts that nimaki is compared
with Pele on (`corpus/cases.json`). It picks the first text that comes from Pele's
documentation and has 4 to 25 lines: short enough to read on a phone, long enough to show what the
type is for. The `info` type has no such text; it takes its shortest one. The caption names the
file of Pele the text comes from, and the Mermaid text is folded under the drawing.

This is the one for `pie`, drawn here the same way:
"""

nbMermaid """pie title Pets adopted by volunteers
    "Dogs" : 386
    "Cats" : 85
    "Rats" : 15""", "A pie, drawn by nimaki and checked against Pele while this page was built."

nbNote """
- **Groups, or an emoji?** Pietro suggested marking the diagram pills with an emoji. An emoji
  looks different on every phone and adds a colour the Pomice palette does not have, so this post
  proposes two captioned groups instead, the types drawn as boxes. The emoji version was shown to
  him as a screenshot next to this one.
- **Pietro's answer** (15 November 2026): two groups, as this post shows them; they shipped in
  [pull request 97](https://github.com/pietroppeter/nimaki/pull/97).
""", nkQuestion, "For Pietro"

nbNote """
- `docs/modules.nim` picks each type's example (`exampleOf`) and draws it with `nbMermaid`; Pele
  draws all {n} of them in one Node process first.
- `nbPipeline` takes a caption and a group (`docs/blocks.nim`), and `nbModules` in `docs/site.nim`
  draws the two groups; the boxes are a few lines of `docs/theme.nim`.
""".replace("{n}", $cov.diagrams.len), nkNim, "In the port"

nbNote """
- The pages build, so every example is the same bytes as Pele's drawing.
- `tools/links.nim`: no broken link. The drift check: no HTML or colour in a page.
- At 390 pixels wide, in both modes: no type page scrolls sideways.
""", nkDone, "Checked"

nbText: """
## What this changes for the port

- A type's page shows what the type draws, and proves it on every build.
- The coverage map reads as two lists: what every type shares, and the types.

## Sources

- The code: [`docs/modules.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/modules.nim),
  [`docs/site.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/site.nim).
- The examples: `corpus/cases.json`, built from Pele's own test corpus by `tools/corpus.mjs`.
"""

nbSave
