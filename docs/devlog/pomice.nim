## devlog: 12 Nov 2026 C | Pomice, the look of nimaki | Pumice is the stone that fire makes and the sea carries. The pages of this port wear its colours: basalt, lava, sea, sulphur and olivine.
## kind: tooling
import std/[os, strformat, strutils]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../theme
import data/pomice/contrast

nbInit
nb.usePost()

let here = currentSourcePath().parentDir / "data" / "pomice"

nbText: """
## The short version

- The pages of nimaki have their own look, **Pomice**. It is drawn from the story of the
  project's name: Nāmaka, the sea, follows Pele, the fire, down the island chain. Pumice is
  what you get when the two meet: lava that the sea has cooled and carries away.
- **Six colours per mode**, all from the island: pumice paper, basalt ink, lava for Pele (the
  reference), sea for nimaki (the port), sulphur for warnings and olivine for what is done. Two
  modes, *giorno* and *notte*, switched in the header.
- **Three shapes**: a wave marks a place, a stone rounded by the sea is a sheet set apart, a dot
  is a step that glows while it is ported and cools when it is done.
- **Pele's diagrams wear the look too**: their colours come from the same tokens, so a diagram
  switches to night with the page, without being drawn again.
- Everything is vendored: three open-licensed fonts and no request to any other site.
"""

nbText: """
## Where the look comes from

The project's family is a sea and fire story. [Mermaid](https://mermaid.js.org) is the sea;
[Pele](https://github.com/obsidianmd/pele), the Hawaiian goddess of fire and volcanoes, gives
her name to the renderer this project ports; diagrammari's `mari` is the seas again, and
*nimaki* is Nim plus Nāmaka, Pele's older sister, the goddess of the sea. In the story Nāmaka
follows Pele from the oldest islands to the youngest, and the sea reaches every fire pit Pele
digs.

Where lava meets the sea, it cools at once into glassy stone full of bubbles: pumice, light
enough to float. It is a good picture for a port. The fire made the shape (Pele's code, its
layouts, its tests); the sea carries it somewhere new, and the shape is kept.
"""

nbNote("""
The palette borrows the island's materials, not Hawaiian symbols: no patterns, glyphs or images
that belong to Hawaiian culture. The project's README will tell Nāmaka's story with care, and
the look stays on the side of geology.
""", nkInfo, "A word on respect")

nbText: """
The structure comes from the looks of Pietro's other projects. From gleam-in-nim's *Lucciola*:
six tokens per mode with every other colour mixed from them, two modes with Italian names, and
one module, `docs/theme.nim`, that holds every CSS rule. From nanuq and cicak: a serif for long
reading and a grotesque for headings. From tabelline: the token names its tables read, so a
table needs no colours of its own.
"""

nbText: """
## The six colours

Each mode gives six values; the soft tints, the text tints, the greys and the surfaces are mixed
from them by the browser. The swatches below are drawn from the tokens themselves, so they
change when you switch the mode in the header.
"""

type Swatch = object
  role, colour, stone, giorno, notte, css: string

block:
  let rows = @[
    Swatch(role: "paper", colour: " ", stone: "pumice", giorno: giorno.paper, notte: notte.paper,
           css: tint("--paper")),
    Swatch(role: "ink", colour: " ", stone: "basalt", giorno: giorno.ink, notte: notte.ink,
           css: tint("--ink")),
    Swatch(role: "primary", colour: " ", stone: "lava", giorno: giorno.primary, notte: notte.primary,
           css: tint("--primary")),
    Swatch(role: "secondary", colour: " ", stone: "sea", giorno: giorno.secondary, notte: notte.secondary,
           css: tint("--secondary")),
    Swatch(role: "warning", colour: " ", stone: "sulphur", giorno: giorno.warning, notte: notte.warning,
           css: tint("--warning")),
    Swatch(role: "success", colour: " ", stone: "olivine", giorno: giorno.success, notte: notte.success,
           css: tint("--success"))]
  let t = tabella(rows, rownameCol = "role"):
    tabHeader "The tokens of Pomice", "the six values of each mode"
    tabStyle(style.fill(fromColumn("css")), loc.body("colour"))
    colsHide "css"
    optCssTheme()
  nbTable t

nbText: """
Colours must be readable before they are pretty. The browser mixes the text tints in Oklab
(`color-mix(in oklab, ...)`); the code below does the same mix in Nim
([contrast.nim](https://github.com/pietroppeter/nimaki/blob/main/docs/devlog/data/pomice/contrast.nim)) and measures each text colour on its paper with the
WCAG contrast ratio. 4.5 is enough for body text (level AA), 7 is the stricter level AAA.
"""

nbCode:
  for (name, look) in [("giorno", giorno), ("notte", notte)]:
    let paper = srgbOf(look.paper)
    let ink = srgbOf(look.ink)
    echo name
    echo "  ink            ", contrastRatio(ink, paper).formatFloat(ffDecimal, 1)
    echo "  muted          ", contrastRatio(mixOklab(ink, paper, 65), paper).formatFloat(ffDecimal, 1)
    for (role, c) in [("lava text", look.primary), ("sea text", look.secondary),
                      ("olivine text", look.success)]:
      let text = mixOklab(srgbOf(c), ink, textShare.float)
      echo "  ", role.alignLeft(15), contrastRatio(text, paper).formatFloat(ffDecimal, 1)

nbText: """
Every text colour passes AA in both modes, and the ink passes AAA. The pure lava, sea and
olivine are never used for text on the paper: they colour marks, dots, swatches and borders,
and text uses their `-text` tint, the colour mixed with the ink.

## Three typefaces

- **Bricolage Grotesque** for headings, the wordmark and labels: a grotesque with a bit of fire
  in its curves, and a variable weight from 200 to 800.
- **Source Serif 4** for the text: a calm serif with real italics, made for reading on screens.
  Explainers are long, and Pietro reads them on a phone.
- **JetBrains Mono** for code, with ligatures off, so `->` and `=>` look as typed.

Both text fonts carry the Latin Extended set, so Hawaiian names keep their marks: Nāmaka,
Kīlauea, Hāna, the ʻokina of Kauaʻi.

## Three shapes

**The wave is a place.** It is in the wordmark (Nāmaka's wave reaching an ember of Pele's fire),
before each section heading, under the masthead and above the footer.

**A stone rounded by the sea is a sheet set apart.** Notes, cards, code and the contents all
have the same rounded corners. A note takes the colour of its kind, and its title names the kind
in words, for those who do not see the colour:
"""

nbNote("How Pele does it: the layout runs once per diagram, synchronously, with no DOM.",
       nkPele, "Pele")
nbNote("How the port does it, and why it differs: a Nim `func` with the same steps.",
       nkNim, "Nim")
nbNote("Byte-identical SVG on all the pie charts of the corpus.", nkDone, "Verified")
nbNote("JavaScript strings are UTF-16; Nim strings are bytes.", nkWarning, "Watch out")
nbNote("Should the gantt chart take today's date from the clock?", nkQuestion, "Open question")
nbNote("A page to go to, or a fact to keep in mind.", nkInfo, "Information")

nbText: """
Cards are notes in a grid, one column on a phone:
"""

nbCards "a specimen of cards":
  nbCard("Roadmap", "#three-shapes", "kept up to date", nkInfo):
    nbText "Every step, its owner and how far it is."
  nbCard("Coverage map", "#three-shapes", "kept up to date", nkNim):
    nbText "Diagram types by parse, layout and render."

nbText: """
**A dot is a step.** The chain shows the steps of the port as
islands: grey while planned, glowing lava while they are being ported, olivine once they have
cooled (done). The chain below is made up, to show the look:
"""

nbPipeline [("text metrics", stDone), ("svg builder", stDone), ("pie", stStarted),
            ("timeline", stStarted), ("layered layout", stPlanned), ("flowchart", stPlanned)]

nbText: &"""
The same colours say a status in a sentence or in a table: {status(stPlanned)},
{status(stStarted)}, {status(stDone)}, {status(stBlocked)}.

Long things fold away:
"""

nbFold "What a fold looks like":
  nbText "A long listing, raw data or a detour goes here, closed by default."

nbText: """
## Diagrams drawn by Pele

The explainers will be full of diagrams, and Pele draws them. A Pele diagram reads its colours
from CSS variables (the background, the ink, the lines, an accent, eight series colours), and
the theme sets those from the tokens. So the diagrams below are plain Pele SVG, drawn once by
Pele 1.13.0 in Node from the Mermaid text in
[items.json](https://github.com/pietroppeter/nimaki/blob/main/docs/devlog/data/pomice/items.json)
with [render.js](https://github.com/pietroppeter/nimaki/blob/main/docs/devlog/data/pomice/render.js): switch the mode and they follow. Later, nimaki itself will
draw them.
"""

for (name, caption) in [("family", "The family: the sea, the fire, and the sea again."),
                        ("lines", "Where Pele's lines of TypeScript are (v1.13.0, src/)."),
                        ("chain", "Nāmaka follows Pele down the island chain.")]:
  nbSvg readFile(here / name & ".svg"), caption

nbText: """
## Rules for pages

- A page names no colour and holds no CSS: it uses blocks, and blocks use the tokens. A new
  block that needs a rule gets it in `docs/theme.nim`.
- Lava is for Pele and for what is hot (being ported now); the sea is for nimaki, for Nim and
  for links. A note about Pele is `nkPele`, a note about the port is `nkNim`.
- Check a new block in both modes and at 390 pixels wide.
- Fonts live in `docs/assets/fonts/` with their licences; nothing loads from another site.

## What this changes for the port

Nothing in the code: the look is all in `docs/theme.nim`, with the header's wordmark and the
`pele` note kind in `docs/blocks.nim`. It gives the explainers a place to stand, and it gives
Pele's diagrams a home: the coverage map and the explainers can show a diagram as Pele draws
it and, later, as nimaki draws it, side by side, in the same colours.

## Sources

- The story of Nāmaka and Pele: the project brief.
- [Bricolage Grotesque](https://github.com/ateliertriay/bricolage) by Mathieu Triay,
  [Source Serif 4](https://github.com/adobe-fonts/source-serif) by Frank Grießhammer for Adobe,
  [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) by JetBrains: all under the SIL
  Open Font License 1.1, taken from the [Fontsource](https://fontsource.org) packages on npm.
- [Oklab](https://bottosson.github.io/posts/oklab/), by Björn Ottosson: the colour space of the
  mixes. [WCAG 2.2 contrast](https://www.w3.org/TR/WCAG22/#contrast-minimum): the ratio.
- Pele's theme variables (`--pele-*`): read from the SVG that [Pele](https://github.com/obsidianmd/pele) 1.13.0 writes.
"""

nbSave
