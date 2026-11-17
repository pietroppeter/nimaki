## devlog: 17 Nov 2026 C | Theming, explained | A drawing of nimaki asks the page for its colours, as Pele's does: a new page, Theming, says how, with every variable and its default read from the corpus; and the site's two modes are now called light and dark.
## kind: tooling
import nimib
import ../blocks, ../pele

nbInit
nb.usePost()

nbText: """
## The findings, first

- Pietro asked how nimaki does theming: like Pele and unlike Mermaid? Yes. A drawing writes no
  fixed colours. Each colour is a CSS variable with Pele's default as its fallback,
  `var(--pele-line, #1f1f1f)`, so the page around the drawing decides, and a page that turns dark
  turns its drawings dark without drawing them again.
- Nothing on the site explained it: the README said it in one line. The new living page
  [Theming](../../theming/) explains it from scratch, shows one drawing in four themes, lists
  every variable with its default, and covers Mermaid's palettes, fonts, and what Mermaid's own
  themes do here (nothing, as in Pele).
- The table of variables is not typed by hand: when the page is built, nimaki draws the whole
  corpus and collects every `var(--pele-..., default)` the drawings contain. When the pin moves,
  the table moves with it.
- The page also checks, in code that runs on it, that a Mermaid `theme: dark` leaves the drawing
  the same bytes.
- The two modes of the site, *giorno* and *notte*, are now **light** and **dark**, as Pietro
  asked: plain words for every reader. A browser that remembered the old names keeps its choice.
"""

nbText: """
## How it looks

The same drawing, once in the site's colours (press ☾ / ☀ at the top to switch) and once in no
colours at all, which gives Pele's defaults. The page [Theming](../../theming/) has two more.
"""

let text = """
flowchart LR
  A[Draft] --> B{Review}
  B -->|yes| C[Published]
  B -->|no| A
"""
nbMermaid text, "This site's colours, which follow light and dark."
nbSvg mermaidSvg(text), "The same bytes with no variable set: Pele's defaults.", dlPele

nbText: """
## How the page shows other themes

A page here holds no CSS and no colours (the rule of [For coding agents](../../agents/)), so the
four themes could not be written in the page. The block `nbSvg` got a third, optional argument,
the look of the figure (`DrawingLook` in `docs/blocks.nim`): the site's, Pele's defaults, or the
light and dark example of Pele's own Theming page. The values are CSS rules in `docs/theme.nim`,
like every other colour of the site.

Pele's defaults are shown by setting each variable to `initial` around the drawing. For a CSS
variable, `initial` means *not set*, so `var(--pele-bg, #fff)` takes its fallback, as it would
on a page that knows nothing of Pele.

## The rename

`giorno` and `notte` were the names of the two `Look` values in `docs/theme.nim`, of the
attribute that switches the page (`data-look`), of the button and of the value the browser keeps
in `localStorage`. All are now `light` and `dark`. The script that picks the mode on load turns an
old `giorno` or `notte`, kept by a browser or in a `?look=` link, into the new name, so no
reader loses the mode they chose. The post [Pomice](../pomice/), dated, keeps the names it was
written with, and has a note saying they changed.

## What this changes for the port

Nothing in `src/`: theming was ported with the core, and is identical to Pele's. What changes is
that the site now says it, the README and the home page point to the page, and a later session
that touches colours has one place to read.

## Sources

- [Pele's Theming page](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/website/src/content/docs/theming.md)
  and [Compatibility page](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/website/src/content/docs/compatibility.md), at the pin.
- [Mermaid's theming page](https://mermaid.js.org/config/theming.html).
- nimaki's [svg/theme.nim](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/svg/theme.nim),
  [svg/palette.nim](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/svg/palette.nim) and
  [svg/ink.nim](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/svg/ink.nim).
"""

nbSave
