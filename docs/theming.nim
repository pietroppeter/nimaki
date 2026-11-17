## The page Theming, docs/theming/index.html: how a drawing of nimaki (and of Pele) takes its
## colours and fonts from the page it is on, which variables it reads, and how a Nim program or a
## web page sets them. Kept up to date: the table of variables and their defaults is read from
## nimaki's own drawings of the corpus, so it follows the pin; the descriptions follow Pele's
## Theming page at the pin (website/src/content/docs/theming.md).
import std/[json, strformat, strutils, tables, sets, algorithm, sequtils, options]
import nimib
import tabelline, tabelline/nimib
import blocks, pele
import nimaki

nbInit
nb.doc.filename = docsDir / "theming" / "index.html"
nb.usePage(section = "Theming", cadence = "kept up to date", title = "Theming · nimaki",
           homeHref = "../", description = "How a drawing of nimaki takes its colours and fonts from the page: the --pele-* CSS variables, light and dark, palettes, and what Mermaid's themes do here.")

nbTitle "Theming · kept up to date", "How a drawing takes its colours", """
nimaki does not paint its drawings in fixed colours. Every colour in the SVG is a question to the
page (*what is your background colour?*) with an answer ready in case the page says nothing.
This is how Pele does it, and it is not how Mermaid does it. This page explains how it works,
lists every question a drawing asks, and shows how to answer them from a web page or from Nim.
"""

nbToc

let peleTheming = "https://github.com/obsidianmd/pele/blob/" & pin.commit & "/website/src/content/docs/theming.md"
let peleCompat = "https://github.com/obsidianmd/pele/blob/" & pin.commit & "/website/src/content/docs/compatibility.md"

nbText: &"""
## The short version

- **Colours are CSS variables.** A drawing writes `var(--pele-line, #1f1f1f)` where another
  renderer would write `#1f1f1f`: "the page's `--pele-line` colour, or dark grey if the page
  has none". The same SVG text looks different on every page that sets the variables.
- **Light and dark need no second drawing.** A page that switches to dark changes the variables,
  and every drawing on it changes at once, without being drawn again. Press the ☾ / ☀ button
  at the top of this page to see it.
- **A page sets them with CSS** on the class `pele`, which every drawing has. There are eight
  main colours, eight series colours (for pie slices, branches, chart lines), two text colours
  for fills the diagram chose itself, fonts, a corner radius and three font weights.
- **Mermaid's themes do nothing here.** `theme: dark` or `forest`, and almost every
  `themeVariables` entry, are ignored, as in Pele. The exception: the palettes that set series
  colours, such as `pie1` to `pie8`. Colours written in the diagram (`style`, `classDef`) are
  kept, and stay fixed.
- nimaki draws the same bytes as Pele, so all of this is Pele's design, documented on
  [Pele's Theming page]({peleTheming}). nimaki adds nothing and changes nothing.
"""

nbText: """
## Variables, not colours

A *CSS variable* (CSS calls it a *custom property*) is a value with a name that starts with two
dashes, such as `--pele-bg: white`. An element sets it, and the element and everything inside it
can read it with `var(--pele-bg)`. `var(--pele-bg, #fff)` reads it with a *fallback*: the value
to use when nobody set the variable.

Here is the start of a drawing nimaki makes, a three-node flowchart. The code renders it and
prints the `style` of the root `svg` element, one declaration per line (`styleAttr` is the
text `style="`, defined out of sight):
"""

const styleAttr = "style" & "=\""   ## the root's style attribute (spelled apart, as tools/drift.nim counts the whole word)

nbCode:
  let drawing = render("flowchart LR\n  A[Draft] --> B[Review] --> C[Done]\n").svg
  let rootStyle = drawing.split(styleAttr)[1].split("\"")[0]
  for declaration in rootStyle.split(';'):
    echo declaration

nbText: """
Read it from the top. `max-width` and `height` let the drawing shrink to a phone. Then come short
private names, such as `--_bg` and `--_l`, each set to a public `--pele-*` variable with its
fallback: the rest of the drawing writes `var(--_l)` in each line, which is shorter than repeating
`var(--pele-line,#1f1f1f)` every time. `color` and the `font` declarations follow, with the
font as a variable too.

So a page that sets nothing gets Pele's own default colours, and a page that sets
`--pele-line: teal` gets teal lines, from the same bytes.
"""

nbText: """
## One drawing, four themes

The flowchart below is drawn once, by nimaki (and checked against Pele, byte for byte, when this
page is built), and the same SVG text is shown four times. Only the page around it changes:
first this site's colours, which follow the ☾ / ☀ button; then no variable at all, so Pele's
defaults; then the light and dark example of Pele's Theming page.
"""

let flow = """
flowchart LR
  A[Draft] --> B{Review}
  B -->|yes| C[Published]
  B -->|no| A
  subgraph Desk
    A
    B
  end
  style C fill:olivedrab,color:white
"""
let flowSvg = mermaidSvg(flow)
nbSvg flowSvg, "This site: the variables come from the Pomice colours (`docs/theme.nim`), in light or dark."
nbSvg flowSvg, "No variable set: every colour is its fallback, Pele's default.", dlPele
nbSvg flowSvg, "The light example of Pele's Theming page.", dlExample
nbSvg flowSvg, "The dark example of Pele's Theming page: the same bytes again.", dlExampleDark
nbFold "The Mermaid text of this diagram":
  nbText "```mermaid\n" & flow.strip & "\n```\n"

nbText: """
The green node does not change: its colour is written in the diagram (`style C fill:...`), and
a colour written in the diagram is a fixed colour. Its label is white because the text asked for
it (`color:white`); without it, nimaki picks the text colour that reads best on that green (see
[Colours written in the diagram](#colours-written-in-the-diagram)).
"""

# ------------------------------------------------------------------ the variables, from the corpus

type Use = object
  default: string
  types: HashSet[string]

proc fallbacks(svg: string, into: var OrderedTable[string, Use], kind: string) =
  ## Every `var(--pele-NAME, FALLBACK)` in a drawing, and the type that asked for it.
  var i = svg.find("var(--pele-")
  while i >= 0:
    var j = i + "var(--pele-".len
    while j < svg.len and svg[j] in {'a'..'z', '0'..'9', '-'}: inc j
    let name = "--pele-" & svg[i + "var(--pele-".len ..< j]
    var default = ""
    if j < svg.len and svg[j] == ',':
      var depth = 1
      var k = j + 1
      while k < svg.len and depth > 0:
        if svg[k] == '(': inc depth
        elif svg[k] == ')': dec depth
        inc k
      default = svg[j + 1 ..< k - 1]
    if name notin into: into[name] = Use()
    if into[name].default == "": into[name].default = default
    into[name].types.incl kind
    i = svg.find("var(--pele-", j)

const aliases = {"--pele-bg": "--_bg", "--pele-fg": "--_fg", "--pele-muted": "--_m",
                 "--pele-line": "--_l", "--pele-surface": "--_s", "--pele-surface-alt": "--_a",
                 "--pele-border": "--_b", "--pele-accent": "--_c", "--pele-font-mono": "--_fm"}.toTable
  ## The root of every drawing sets these private names, used or not (src/nimaki/svg/theme.nim):
  ## a type reads the variable when its drawing uses the private name.

let corpus = parseFile(repoDir / "corpus" / "cases.json")
var uses: OrderedTable[string, Use]
var drawn: HashSet[string]
for c in corpus["cases"]:
  let kind = c["type"].getStr
  var o = RenderOptions()
  o.now = some(fixedNow)
  let svg = try: render(c["source"].getStr, o).svg
            except CatchableError: ""
  if svg.len == 0: continue
  drawn.incl kind
  var found: OrderedTable[string, Use]
  fallbacks(svg, found, kind)
  let body = svg[svg.find('>') + 1 .. ^1]   # what comes after the root element's own style
  for name, use in found:
    if name notin uses: uses[name] = Use(default: use.default)
    if name notin aliases or ("var(" & aliases[name] & ")") in body or
       (name == "--pele-fg"):   # the root's own fill="var(--_fg)" draws every text
      uses[name].types.incl kind

const described = [
  # From Pele's Theming page at the pin: what each variable is for.
  ("--pele-bg", "backgrounds, and text drawn on a series colour"),
  ("--pele-fg", "text"),
  ("--pele-muted", "secondary text"),
  ("--pele-line", "edges and arrowheads"),
  ("--pele-surface", "the fill of nodes"),
  ("--pele-surface-alt", "the fill of subgraphs (groups of nodes)"),
  ("--pele-border", "the borders of nodes and subgraphs"),
  ("--pele-accent", "highlights"),
  ("--pele-critical", "critical tasks in a gantt chart, high priorities in a kanban"),
  ("--pele-fg-on-light", "text on a light fill the diagram chose itself"),
  ("--pele-fg-on-dark", "text on a dark fill the diagram chose itself"),
  ("--pele-font", "the font of labels (see Fonts)"),
  ("--pele-font-mono", "the font of monospace labels"),
  ("--pele-title-weight", "how bold the diagram's title is"),
  ("--pele-heading-weight", "how bold headings are, such as class names"),
  ("--pele-bold-weight", "how bold bold text in labels is"),
  ("--pele-radius", "the corner radius of rounded shapes"),
  ("--pele-series-1", "the first series or category colour (pie slice, branch, line…)"),
  ("--pele-error", "the error message that mount() shows in the browser")]

let typeCount = drawn.len

nbText: &"""
## The variables

Pele's Theming page lists the variables a drawing reads. The table below does not copy their
defaults by hand: when this page is built, nimaki draws all {corpus["cases"].len} diagrams of
the corpus, and the table collects every `var(--pele-..., default)` those drawings contain, with
the number of the {typeCount} diagram types that use it. So when the pin moves to a newer Pele,
the table follows.
"""

block:
  type Row = object
    variable, default, usedFor, types: string
  var rows: seq[Row]
  let order = described.mapIt(it[0])
  var names = toSeq(uses.keys)
  names.sort(proc (a, b: string): int =
    let (ia, ib) = (order.find(a), order.find(b))
    if ia >= 0 and ib >= 0: cmp(ia, ib)
    elif ia >= 0: -1
    elif ib >= 0: 1
    else: cmp(a, b))
  for name in names:
    if name.startsWith("--pele-series-") and name != "--pele-series-1": continue
    let at = order.find(name)
    var default = uses[name].default
    if name == "--pele-series-1":
      default = (1..8).mapIt(uses.getOrDefault("--pele-series-" & $it).default).join(" ")
    rows.add Row(variable: (if name == "--pele-series-1": "series-1 … 8" else: name["--pele-".len .. ^1]),
                 default: default,
                 usedFor: (if at >= 0: described[at][1] else: "(not on Pele's Theming page)"),
                 types: $uses[name].types.len)
  let mountSource = readFile(repoDir / "src" / "nimaki" / "mount.nim")
  let errorAt = mountSource.find("var(--pele-error,") + "var(--pele-error,".len
  rows.add Row(variable: "error", default: mountSource[errorAt ..< mountSource.find(')', errorAt)],
               usedFor: described[^1][1], types: "—")
  let t = tabella(rows, rownameCol = "variable"):
    tabHeader "What a drawing reads from the page", &"defaults from nimaki's drawings of the corpus; types: of {typeCount}"
    colsLabel {"variable": "--pele-…", "default": "default", "usedFor": "used for", "types": "types"}
    fmtSwatch "default"
    optCssTheme()
  nbTable t

nbText: """
A few notes on the table, in plain words:

- **The eight main colours** come first. Every drawing declares them on its root, so they are
  always there to set, even in a type that does not use one of them.
- **Series colours** are the colours of things that are told apart only by colour: the slices
  of a pie, the branches of a git graph, the lines of a chart, the sections of a timeline. There
  are eight; the ninth category takes the first colour again.
- **`fg-on-light` and `fg-on-dark`** are used only when the diagram itself chose a fill (see the
  next sections): nimaki computes how light that fill is and writes the one that is easier to
  read on it.
- **`--pele-error`** is not in any drawing: `mount()`, which draws into a web page, uses it for
  the message it shows when the text cannot be drawn. Its default is read from nimaki's
  `mount.nim`.
"""

nbText: &"""
## Setting them in a web page

Set the variables on the class `pele` (every drawing's root has it, and also `pele-flowchart`,
`pele-pie` and so on, one class per type) or on any element around the drawings. This is the
example of [Pele's Theming page]({peleTheming}), whose light and dark versions are drawn above.
The block inside `@media (prefers-color-scheme: dark)` applies only when the reader's device is
set to dark mode:

```css
.pele {{
  --pele-bg: #fffcf0;
  --pele-fg: #100f0f;
  --pele-muted: #6f6e69;
  --pele-line: #100f0f;
  --pele-surface: #f2f0e5;
  --pele-surface-alt: #e6e4d9;
  --pele-border: #cecdc3;
  --pele-accent: #205ea6;
  --pele-critical: #af3029;
}}

@media (prefers-color-scheme: dark) {{
  .pele {{
    --pele-bg: #100f0f;
    --pele-fg: #cecdc3;
    --pele-muted: #878580;
    --pele-line: #cecdc3;
    --pele-surface: #1c1b1a;
    --pele-surface-alt: #282726;
    --pele-border: #403e3c;
    --pele-accent: #4385be;
    --pele-critical: #d14d41;
  }}
}}
```

A variable can be set from another variable, so a site with its own colours maps them once.
This site does it in [docs/theme.nim](https://github.com/pietroppeter/nimaki/blob/main/docs/theme.nim):
lines in a grey mixed from the ink, the accent in the sea colour, *critical* in lava, and the
series colours from the six colours of the look. Its button switches an attribute on the page
(`data-look="dark"`), which changes those six colours, and so every drawing:

```css
.pele {{
  --pele-bg: var(--surface); --pele-fg: var(--ink); --pele-line: var(--neutral-7);
  --pele-accent: var(--secondary); --pele-critical: var(--primary);
  --pele-series-1: var(--secondary); --pele-series-2: var(--primary); /* ... */
}}
```

To change one kind of element without a variable, use the class names Pele gives them, such as
`pele-node`, `pele-edge`, `pele-label` and `pele-title`, and `data-id` for one node by its id in
the text; Pele's page lists them all.
"""

nbText: """
## A drawing on its own

An SVG saved to a file and opened on its own, or put in a page with an `img` tag, has no page
CSS around it: every variable falls back to Pele's default, so it is always light. To give such a
file its own colours, set the variables on the drawing itself, at the start of the root's
`style`. A few lines of Nim do it:
"""

nbCode:
  proc withTheme(svg: string, colours: openArray[(string, string)]): string =
    ## The drawing with `--pele-*` values of its own, set on its root element.
    var declarations = ""
    for (name, value) in colours:
      declarations.add "--pele-" & name & ":" & value & ";"
    let at = svg.find(styleAttr) + styleAttr.len   # the first style is the root's
    svg[0 ..< at] & declarations & svg[at .. ^1]

  let night = withTheme(render("flowchart LR\n  A[Draft] --> B[Review] --> C[Done]\n").svg,
    {"bg": "midnightblue", "fg": "white", "line": "lightskyblue", "surface": "navy",
     "border": "lightskyblue"})
  echo night.len, " bytes, root style starts: ", night.split(styleAttr)[1][0 ..< 60]

nbSvg night, "The result, shown in a figure with no page variables: the drawing carries its own.", dlPele

nbText: """
The figure stays white: a drawing paints no background of its own, so the page's shows through,
and `--pele-bg` colours only what sits on top of other shapes, such as the patch behind an edge
label. A page (or a file viewer) gives the background.

Values written on the element itself win over the page's CSS, so this drawing keeps its colours
on any page. It is not the same drawing as Pele's any more (it has more bytes), which is fine for
a file, but the comparison with Pele, the referee of the port, is made before this step.
"""

nbText: """
## Colours written in the diagram

Mermaid text can choose colours itself: `style` for one node, `classDef` and `:::` for a class
of nodes, `linkStyle` for an edge, `rect` and `box` in a sequence diagram. nimaki keeps these
colours, as Pele does, and writes them as they are: they do not change with the theme.

When the diagram chooses a fill and not a text colour, nimaki looks at how light the fill is
and writes, for the label on it, `var(--pele-fg-on-light, ...)` on a light fill or
`var(--pele-fg-on-dark, ...)` on a dark one. Here the gold node gets dark text and the blue one
white text, in every theme:
"""

nbMermaid """
flowchart LR
  A[Gold]:::gold --> B[Blue]:::blue
  classDef gold fill:gold
  classDef blue fill:navy
""", "The label colour follows the fill: `--pele-fg-on-light` on gold, `--pele-fg-on-dark` on navy."

nbText: """
## Series colours and palettes

Charts take their colours from `--pele-series-1` to `--pele-series-8`, which a page can set like
the others. Mermaid's *palette* theme variables are the one part of Mermaid's theming that Pele,
and so nimaki, reads: they replace series colours in one diagram.

| Diagram | Theme variables |
| --- | --- |
| XY chart | `xyChart.plotColorPalette`, a list with commas |
| Pie chart | `pie1` to `pie8` |
| Git graph | `git0` to `git7` |
| Timeline, radar, treemap | `cScale0` to `cScale7` |
| Mindmap | `cScale1` to `cScale8` |
| Venn diagram | `venn1` to `venn8` |

A palette colour is written in the diagram, so it is fixed, like a `style`. To keep it following
the theme, give a `--pele-*` variable as the colour, as this pie does: its two slices are the
page's *critical* and *accent* colours, so they change when you switch to dark. Only `--pele-*`
variables are accepted there, so a diagram cannot read other variables of the page.
"""

let pie = """
---
config:
  themeVariables:
    pie1: "var(--pele-critical)"
    pie2: "var(--pele-accent)"
---
pie
  "Lava" : 3
  "Sea" : 5
"""
nbMermaid pie, "A palette from the theme: `pie1` is `var(--pele-critical)`, `pie2` is `var(--pele-accent)`."
nbSvg mermaidSvg(pie), "The same drawing in the dark example of Pele's page.", dlExampleDark

nbText: &"""
## Unlike Mermaid

[Mermaid](https://mermaid.js.org/config/theming.html) themes a diagram when it draws it: it has
five themes (`default`, `neutral`, `dark`, `forest` and `base`, the one to customise), and
`themeVariables` such as `primaryColor` from which it computes the other colours. The colours
are written into the SVG it makes, so a page that switches to dark draws its diagrams again.

[Pele's compatibility page]({peleCompat}) says plainly that Mermaid's themes do not apply, and
that `themeVariables` colours apply only as series palettes. nimaki does the same; the code
below checks it, by drawing one flowchart with and without a dark Mermaid theme:
"""

nbCode:
  let plain = "flowchart LR\n  A[Draft] --> B[Review]\n"
  let themed = "%%{init: {\"theme\": \"dark\", \"themeVariables\": {\"primaryColor\": \"red\"}}}%%\n" & plain
  let forest = "---\nconfig:\n  theme: forest\n---\n" & plain
  echo "dark theme, same bytes:   ", render(themed).svg == render(plain).svg
  echo "forest theme, same bytes: ", render(forest).svg == render(plain).svg

nbText: """
The gain is that one drawing serves every theme and both modes, and a site's look applies to
every diagram without a theme for each one. The cost, for a text written for Mermaid, is that
its theme lines are ignored: the page decides.
"""

nbText: """
## Fonts

Fonts are different from colours, because the font decides how wide a label is, and nimaki
measures labels to size the boxes around them (it measures them with tables of font widths,
without a browser). So the font is chosen *before* drawing:

- From Nim, pass it in the options: `render(text, RenderOptions(fontFamily: "Georgia"))`, and
  `fontFamilyMono` for monospace text. The drawing measures with it and names it as the
  fallback of `--pele-font`.
- If the page also sets `--pele-font`, it must be the same font, or labels may not fit their
  boxes.
- In the browser, `nimaki.mount` (in `nimaki.js`) reads `--pele-font` and `--pele-font-mono`
  from the page's CSS, measures with them, and draws again when web fonts finish loading.
- `RenderOptions.monospace` lists parts to draw in the monospace font (`members` of class
  diagrams, `attributes` of ER diagrams, `files` of tree views, `messages` of sequence
  diagrams), so they are measured in that font.

The font weights (`--pele-title-weight` and the others) and `--pele-radius` change only how
text and corners look, not their size, so a page can set them freely.
"""

nbText: &"""
## Sources

- [Pele's Theming page]({peleTheming}) and [Compatibility page]({peleCompat}), at the pin: the
  variables, the classes, palettes and what Mermaid themes do in Pele.
- nimaki's ports of Pele's theme code: [svg/theme.nim](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/svg/theme.nim)
  (the root's variables, series colours), [svg/palette.nim](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/svg/palette.nim)
  (Mermaid's palettes) and [svg/ink.nim](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/svg/ink.nim)
  (the text colour on a fill).
- [Mermaid's theming page](https://mermaid.js.org/config/theming.html), for how Mermaid does it.
- This site's own mapping: [docs/theme.nim](https://github.com/pietroppeter/nimaki/blob/main/docs/theme.nim),
  explained in the post [Pomice, the look of nimaki](../devlog/pomice/).
"""

nbSave
