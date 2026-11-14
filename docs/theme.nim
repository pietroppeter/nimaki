## The look of the pages, in one place: fonts, colours, every CSS rule.
##
## The look is called **Pomice** (pumice, in Italian): the stone that fire makes and the sea
## carries. Pele's lava, cooled in the sea, floats away as pumice; the port takes Pele's work and
## carries it into Nim, as Nāmaka's sea reached every fire pit Pele dug. Two modes: *giorno*
## (day, the default: a page without JavaScript is giorno), pale stone on a beach, and *notte*
## (night), the sea at night with the glow of a lava flow at its edge. The header switches them
## and the browser remembers; the first visit follows the system.
##
## Six values per mode, all taken from the island, and every other colour is mixed from them in
## the browser, as in tabelline's pages, so tabelline's tables (`optCssTheme()`) and the review
## mode read them as they are:
##
## - paper is pumice, ink is basalt;
## - primary is lava, Pele's colour: what is about Pele, the reference, and what is being
##   ported now (it glows);
## - secondary is the sea, nimaki's colour: what is about Nim and the port, links and places;
## - warning is sulphur (never text), success is olivine, the green crystal of Hawaiian basalt
##   (and of its green-sand beach): how a step went.
##
## Shape says the kind of thing: the wave is a place (the wordmark, a section heading, the edge
## of the masthead and the footer); a stone rounded by the sea is a sheet set apart (notes,
## cards, code); a dot is a step, glowing lava while it is ported and olivine once it has cooled
## (done). Pele's diagrams take their colours from the same tokens (`.pele`), so they switch with
## the page. No other module writes CSS or names a colour: pages use `blocks.nim`.

import std/[os, strformat, strutils]
when defined(singleFile): import std/base64

const
  lookName* = "Pomice"
  singleFile* = defined(singleFile)
    ## `-d:singleFile`: every page is one file, its style, fonts and scripts inlined
  assetsDir* = currentSourcePath().parentDir / "assets"
    ## `docs/assets/`: the files the pages share (deployed with them)
  fontDir = assetsDir / "fonts"

const
  latin = "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308," &
    "U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD"
    ## the Latin subset; it has the ʻokina (U+02BB) of Hawaiian names
  latinExt = "U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308," &
    "U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C4,U+2113," &
    "U+2C60-2C7F,U+A720-A7FF"
    ## Latin Extended: the kahakō of Hawaiian names (ā, ē, ī, ō, ū), and more

func face(family, file, weight, style: string, range = ""): string =
  when singleFile:
    let src = "data:font/woff2;base64," & encode(staticRead(fontDir / file))
  else:
    discard fontDir   # the font file, beside site.css
    let src = "fonts/" & file
  result = &"@font-face{{font-family:'{family}';src:url({src}) format('woff2');" &
    &"font-weight:{weight};font-style:{style};font-display:swap"
  if range.len > 0: result.add ";unicode-range:" & range
  result.add "}\n"

const fonts =
  # headings: a grotesque with some fire in it
  face("Bricolage Grotesque", "bricolage-grotesque-latin-wght-normal.woff2", "200 800", "normal", latin) &
  face("Bricolage Grotesque", "bricolage-grotesque-latin-ext-wght-normal.woff2", "200 800", "normal", latinExt) &
  # text: a calm serif, for long reading on a phone
  face("Source Serif 4", "source-serif-4-latin-wght-normal.woff2", "200 900", "normal", latin) &
  face("Source Serif 4", "source-serif-4-latin-ext-wght-normal.woff2", "200 900", "normal", latinExt) &
  face("Source Serif 4", "source-serif-4-latin-wght-italic.woff2", "200 900", "italic", latin) &
  face("Source Serif 4", "source-serif-4-latin-ext-wght-italic.woff2", "200 900", "italic", latinExt) &
  # code
  face("JetBrains Mono", "jetbrains-mono-latin-wght-normal.woff2", "100 800", "normal")

# ------------------------------------------------------------------------------------ the palette

type Look* = object
  ## The six values a mode gives, and `lift`, what the paper is mixed with for a raised sheet.
  paper*, ink*, primary*, secondary*, warning*, success*, lift*: string

const
  giorno* = Look(paper: "#F6F3EC",      # pumice, pale and warm
                 ink: "#1B2631",        # basalt, blue-black
                 primary: "#E0542B",    # lava, deep enough for paper
                 secondary: "#0F7F8E",  # the sea by the shore
                 warning: "#E3AA12",    # sulphur
                 success: "#5F9227",    # olivine
                 lift: "#FFFFFF")
  notte* = Look(paper: "#0D1922",       # the sea at night
                ink: "#E6EDEF",
                primary: "#FF7A4A",     # lava glowing in the dark
                secondary: "#4CC5D2",   # moonlight on the water
                warning: "#F4C445", success: "#9CCB5A", lift: "#23394A")

  neutralSteps* = [0, 4, 8, 14, 25, 40, 55, 65, 80, 100]  ## ink in paper, % per step `--neutral-0`..`--neutral-9`
  softShare* = 20   ## % of a colour in paper, for `--x-soft`
  textShare* = 55   ## % of a colour in ink, for `--x-text`

func tokensCss(): string =
  for i, s in neutralSteps:
    result.add &"--neutral-{i}: color-mix(in oklab, var(--ink) {s}%, var(--paper));\n"
  result.add "--shade: var(--neutral-1); --line: var(--neutral-3); --muted: var(--neutral-7);\n"
  result.add "--surface: color-mix(in oklab, var(--lift) 60%, var(--paper));\n"
  for role in ["primary", "secondary", "warning", "success"]:
    result.add &"--{role}-soft: color-mix(in oklab, var(--{role}) {softShare}%, var(--paper));\n"
    if role != "warning":
      result.add &"--{role}-text: color-mix(in oklab, var(--{role}) {textShare}%, var(--ink));\n"
  result.add "--font: 'Source Serif 4', Georgia, 'Times New Roman', serif;\n"
  result.add "--display: 'Bricolage Grotesque', system-ui, -apple-system, 'Segoe UI', sans-serif;\n"
  result.add "--mono: 'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace;\n"
  result.add "--stone: 14px;\n"   # the radius of a sheet: a stone the sea has rounded

func lookCss(l: Look): string =
  &"--paper: {l.paper}; --ink: {l.ink}; --primary: {l.primary}; --secondary: {l.secondary}; " &
    &"--warning: {l.warning}; --success: {l.success}; --lift: {l.lift};"

const tokens =
  "html {\n" & lookCss(giorno) & "\n" & tokensCss() & "--code-share: 60%; --glow: 0; color-scheme: light; }\n" &
  "html[data-look=\"notte\"] {\n" & lookCss(notte) & "\n--code-share: 85%; --glow: 1; color-scheme: dark; }\n"

# --------------------------------------------------------------------------------------- the marks

func svgUrl(svg: string): string =
  ## An SVG as a CSS `url(...)`, for a mask: its colour is the background it masks.
  "url(\"data:image/svg+xml," &
    svg.multiReplace(("<", "%3C"), (">", "%3E"), ("#", "%23"), ("\"", "'")) & "\")"

const
  waveMark = svgUrl("""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 12"><path d="M1.5 7.5c2.5 0 3.5-5 6-5s3.5 5 6 5 3.5-5 6-5c1.6 0 2.5 1.5 3 2.5" fill="none" stroke="#000" stroke-width="2.6" stroke-linecap="round"/></svg>""")
    ## a wave: a place
  waveLine = svgUrl("""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 8"><path d="M0 4c4 0 4-3 8-3s4 3 8 3 4 3 8 3 4-3 8-3" fill="none" stroke="#000" stroke-width="1.6"/></svg>""")
    ## the edge of the sea, repeated: under the masthead, above the footer, as a rule

const marks = &"""html {{ --wave-mark: {waveMark}; --wave-line: {waveLine}; }}
"""

# ------------------------------------------------------------------------------------- the rules

const rules = """
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; scroll-behavior: smooth; }
body { margin: 0 auto; max-width: 44rem; padding: 0 1.1rem 3rem; background: var(--paper); color: var(--ink);
  font: 400 18px/1.62 var(--font); overflow-wrap: break-word; font-optical-sizing: auto; }
[hidden] { display: none !important; }
a { color: var(--secondary-text); text-decoration-color: color-mix(in oklab, var(--secondary) 55%, transparent);
  text-decoration-thickness: 1.5px; text-underline-offset: 3px; }
a:hover { color: var(--ink); text-decoration-color: var(--secondary); }
::selection { background: var(--secondary-soft); }
img, svg { max-width: 100%; height: auto; }
hr { border: 0; height: 8px; margin: 2.2rem 0; background: var(--line);
  -webkit-mask: var(--wave-line) 0 50% / 32px 8px repeat-x; mask: var(--wave-line) 0 50% / 32px 8px repeat-x; }
strong { font-weight: 650; }

/* the header: a way back, the mode switch, the wordmark and where the page belongs */
body > header { padding: .7rem 0 0; }
.crumbs { display: flex; align-items: center; gap: .8rem; font: 500 .88rem var(--display); }
.crumbs a { color: var(--muted); text-decoration: none; min-height: 44px; display: inline-flex; align-items: center; }
.crumbs a:hover { color: var(--ink); }
.crumbs .grow { flex: 1; }
.look { font: inherit; color: var(--muted); background: transparent; border: 1px solid var(--line); border-radius: 999px;
  min-width: 44px; min-height: 34px; padding: 0 .8rem; cursor: pointer; }
.look:hover { color: var(--ink); border-color: var(--ink); }
.masthead { position: relative; display: flex; flex-wrap: wrap; align-items: center; gap: .2rem .8rem; margin: .4rem 0 0;
  padding-bottom: 1rem; font-family: var(--display); }
.masthead::after { content: ""; position: absolute; left: 0; right: 0; bottom: 0; height: 8px; background: var(--ink);
  -webkit-mask: var(--wave-line) 0 50% / 32px 8px repeat-x; mask: var(--wave-line) 0 50% / 32px 8px repeat-x; }
.wordmark { display: inline-flex; align-items: center; gap: .45rem; font-weight: 750; font-size: 1.3rem;
  letter-spacing: -.02em; color: var(--ink); text-decoration: none; }
.wordmark svg { width: 1.6rem; height: 1.6rem; flex: none; }
.wordmark .ember { fill: var(--primary); }
.wordmark .sea { fill: var(--secondary); }
.masthead .section { color: var(--muted); font-size: .95rem; }
.masthead .cadence { color: var(--muted); font-size: .74rem; margin-left: auto; text-transform: uppercase; letter-spacing: .08em; }

/* the title of a page */
.kicker { margin: 2.1rem 0 .3rem; font: 600 .8rem var(--display); letter-spacing: .09em; text-transform: uppercase; color: var(--muted); }
.kicker .kind { color: var(--ink); background: var(--secondary-soft); padding: .12rem .55rem; border-radius: 999px; }
.kicker .kind.port { background: var(--primary-soft); }
.kicker .kind.plan { background: var(--success-soft); }
.kicker .kind.tooling { background: var(--shade); }
.kicker .kind.article { background: var(--warning-soft); }
h1 { font: 760 2.35rem/1.08 var(--display); letter-spacing: -.03em; margin: .25rem 0 .7rem; text-wrap: balance; }
.lede { font-size: 1.16rem; line-height: 1.5; color: var(--neutral-8); font-style: italic; }
.lede p { margin: 0 0 .6rem; }

/* headings: the wave is a place */
h2 { font: 720 1.5rem/1.2 var(--display); letter-spacing: -.02em; margin: 2.7rem 0 .7rem; padding-top: .4rem; text-wrap: balance; }
h2::before { content: ""; display: inline-block; width: 1.05em; height: .55em; margin-right: .45rem; vertical-align: .08em;
  background: var(--secondary); -webkit-mask: var(--wave-mark) center / contain no-repeat; mask: var(--wave-mark) center / contain no-repeat; }
h3 { font: 650 1.16rem/1.3 var(--display); letter-spacing: -.01em; margin: 1.9rem 0 .5rem; }
h4 { font: 650 1rem/1.3 var(--display); margin: 1.4rem 0 .4rem; }
h2 a.up, h3 a.up { margin-left: .5rem; text-decoration: none; color: var(--line); font-weight: 400; }
h2 a.up::after, h3 a.up::after { content: "↑"; }
h2 a.up:hover, h3 a.up:hover { color: var(--ink); }
p { margin: 0 0 1rem; }
ul, ol { padding-left: 1.4rem; margin: 0 0 1rem; }
li { margin: .25rem 0; }
li::marker { color: var(--secondary); }
blockquote { margin: 1.2rem 0; padding: .2rem 1rem; border-left: 3px solid var(--secondary); color: var(--neutral-8); font-style: italic; }
blockquote p { margin: .6rem 0; }

/* code: small, in its own rounded box, scrolling sideways inside it */
code, pre { font-variant-ligatures: none; }   /* `->` and `=>` as they are typed */
code { font-family: var(--mono); font-size: .8em; background: var(--shade); padding: .1em .32em; border-radius: 5px; }
pre { margin: 1rem 0; overflow-x: auto; max-width: 100%; background: var(--shade); border-radius: var(--stone); }
body pre > code { display: block; overflow-x: auto; padding: .8rem .95rem; background: transparent; border-radius: 0;
  font: 400 13px/1.55 var(--mono); white-space: pre; tab-size: 2; }
body pre.nb-output { padding: .65rem .95rem; font: 400 12.5px/1.5 var(--mono); white-space: pre; background: var(--surface);
  border: 1px solid var(--line); border-radius: 0 0 var(--stone) var(--stone); margin-top: -.75rem; }
pre:has(+ pre.nb-output) { border-radius: var(--stone) var(--stone) 0 0; }
/* the colours of code: a role's colour, `--code-share` of it in the ink (more at night) */
.hljs-keyword, .hljs-meta { color: color-mix(in oklab, var(--secondary) var(--code-share), var(--ink)); font-weight: 600; }
.hljs-string { color: color-mix(in oklab, var(--success) var(--code-share), var(--ink)); }
.hljs-comment { color: var(--muted); font-style: italic; }
.hljs-number, .hljs-literal { color: color-mix(in oklab, var(--primary) var(--code-share), var(--ink)); }
.hljs-type, .hljs-title { color: color-mix(in oklab, var(--warning) var(--code-share), var(--ink)); }
.hljs-built_in { color: var(--neutral-8); font-weight: 600; }

/* tables written in Markdown (tabelline's bring their own rules and read the same tokens) */
.md-table { overflow-x: auto; margin: 1.2rem 0; }
.md-table table { border-collapse: collapse; width: 100%; font-size: .9rem; line-height: 1.4; }
.md-table th { text-align: left; font: 650 .8rem var(--display); letter-spacing: .03em; border-bottom: 2px solid var(--ink); padding: .4rem .6rem .4rem 0; vertical-align: bottom; }
.md-table td { border-bottom: 1px solid var(--line); padding: .45rem .6rem .45rem 0; vertical-align: top; }
.tabella { margin: 1.2rem 0 1.4rem; font-size: .9rem; line-height: 1.4; }
.tabella .tb_title { font-family: var(--display); font-weight: 650; }
.tabella td code { overflow-wrap: anywhere; }  /* long names in a cell wrap on a phone */

/* figures, and the diagrams Pele draws: they take the page's colours, and switch with it */
figure { margin: 1.4rem 0; }
figcaption { color: var(--muted); font: 500 .86rem/1.4 var(--display); margin-top: .6rem; }
figure.diagram { padding: 1rem; background: var(--surface); border: 1px solid var(--line); border-radius: var(--stone); overflow-x: auto; }
figure.diagram svg { display: block; margin: 0 auto; }
/* nimaki drawing in the reader's browser (nbLive, nbPlayground, assets/live.js) */
.live-status { margin: .6rem 0 0; color: var(--muted); font: 500 .82rem/1.4 var(--display); }
.live-status.good::before { content: "✓ "; color: var(--success); font-weight: 700; }
.live-status.bad::before { content: "✗ "; color: var(--primary); font-weight: 700; }
.playground .live-status.bad { white-space: pre-wrap; font-family: var(--mono); font-variant-ligatures: none; }   /* Pele's error points at a column */
.playground-text { display: block; box-sizing: border-box; width: 100%; min-height: 11rem; resize: vertical;
  padding: .8rem .95rem; font: 400 .85rem/1.5 var(--mono); color: var(--ink); background: var(--shade);
  border: 1px solid var(--line); border-radius: var(--stone); font-variant-ligatures: none;
  white-space: pre; overflow-wrap: normal; overflow-x: auto; }
.playground-text:focus { outline: 2px solid var(--secondary); outline-offset: 1px; }
.playground-drawing:empty { display: none; }
.pele {
  --pele-bg: var(--surface); --pele-fg: var(--ink); --pele-muted: var(--muted); --pele-line: var(--neutral-7);
  --pele-surface: var(--paper); --pele-surface-alt: var(--shade); --pele-border: var(--neutral-6);
  --pele-accent: var(--secondary); --pele-critical: var(--primary); --pele-radius: 8px; --pele-font-mono: var(--mono);
  --pele-series-1: var(--secondary); --pele-series-2: var(--primary); --pele-series-3: var(--success);
  --pele-series-4: var(--warning); --pele-series-5: color-mix(in oklab, var(--secondary) 50%, var(--ink));
  --pele-series-6: color-mix(in oklab, var(--primary) 50%, var(--paper));
  --pele-series-7: color-mix(in oklab, var(--success) 50%, var(--ink)); --pele-series-8: var(--neutral-5);
}

/* the contents of a page */
.toc { margin: 1.6rem 0; padding: .85rem 1.1rem; background: var(--surface); border-radius: var(--stone); border: 1px solid var(--line); }
.toc-title { font: 650 .8rem var(--display); letter-spacing: .09em; text-transform: uppercase; color: var(--muted); margin: 0 0 .4rem; padding: 0; }
.toc-title::before { content: none; }
.toc ol { margin: 0; padding-left: 1.3rem; font-family: var(--display); font-size: .95rem; }
.toc ol ol { font-size: .9rem; }
.toc a { color: var(--ink); text-decoration: none; }
.toc a:hover { text-decoration: underline; }

/* notes and cards: a stone set apart, rounded by the sea, tinted with the colour of its kind */
.note { margin: 1.2rem 0; padding: .75rem 1.05rem .15rem; background: var(--surface); border: 1px solid var(--line);
  border-radius: var(--stone); }
.note .head { display: flex; align-items: center; gap: .5rem; font: 650 .98rem/1.3 var(--display); margin-bottom: .35rem; }
.note .head::before { content: ""; width: .6rem; height: .6rem; border-radius: 50%; background: var(--neutral-5); flex: none; }
.note .num { display: block; font: 600 .72rem var(--display); letter-spacing: .09em; text-transform: uppercase; color: var(--muted); }
.note.info .head::before { background: var(--ink); }
.note.pele { border-color: color-mix(in oklab, var(--primary) 45%, var(--paper)); background: var(--primary-soft); }
.note.pele .head::before { background: var(--primary); box-shadow: 0 0 calc(.15rem + var(--glow) * .45rem) var(--primary); }
.note.nim { border-color: color-mix(in oklab, var(--secondary) 45%, var(--paper)); background: var(--secondary-soft); }
.note.nim .head::before { background: var(--secondary); }
.note.done { border-color: color-mix(in oklab, var(--success) 45%, var(--paper)); background: var(--success-soft); }
.note.done .head::before { background: var(--success); }
.note.warning { border-color: var(--warning); background: var(--warning-soft); }
.note.warning .head::before { background: var(--warning); }
.note.question { border-style: dashed; border-color: var(--neutral-6); background: transparent; }
.note.question .head::before { background: transparent; border: 1.5px dashed var(--ink); }
.cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); gap: .9rem; margin: 1.2rem 0; }
.cards .note { margin: 0; transition: transform .15s ease; }
.cards .note:hover { transform: translateY(-2px); }
.cards .note .head a { color: var(--ink); text-decoration: none; }
.cards .note .head a::after { content: " →"; color: var(--secondary); }
.cards .note p { font-size: .94rem; line-height: 1.45; }

/* something folded away */
details.fold { margin: 1rem 0; border-top: 1px solid var(--line); border-bottom: 1px solid var(--line); }
details.fold > summary { cursor: pointer; padding: .6rem 0; font: 600 .95rem var(--display); min-height: 44px;
  display: flex; align-items: center; gap: .45rem; list-style: none; }
details.fold > summary::-webkit-details-marker { display: none; }
details.fold > summary::before { content: "▸"; color: var(--secondary); transition: transform .15s ease; }
details.fold[open] > summary::before { transform: rotate(90deg); }
details.fold[open] > summary { border-bottom: 1px dashed var(--line); margin-bottom: .8rem; }

/* the chain: one island per step; it glows as lava while it is ported and cools to olivine when done */
.pipeline { display: flex; flex-wrap: wrap; gap: .5rem .35rem; margin: 1.4rem 0; padding: 0; list-style: none; font: 600 .82rem var(--display); }
.pipeline li { display: flex; align-items: center; gap: .45rem; margin: 0; padding: .38rem .75rem; border: 1px solid var(--line); border-radius: 999px; color: var(--muted); }
.pipeline li::before { content: ""; width: .62rem; height: .62rem; border-radius: 50%; background: var(--neutral-2); border: 1px solid var(--neutral-4); }
.pipeline li.started { color: var(--ink); border-color: var(--primary); }
.pipeline li.started::before { background: var(--primary); border-color: var(--primary); box-shadow: 0 0 .45rem var(--primary); }
.pipeline li.done { color: var(--ink); border-color: var(--success); background: var(--success-soft); }
.pipeline li.done::before { background: var(--success); border-color: var(--success); }
.pipeline-legend { color: var(--muted); font-size: .85rem; margin-top: -.8rem; }

/* a status, in words and a colour */
.status { font: 600 .76rem var(--display); letter-spacing: .03em; padding: .1rem .5rem; white-space: nowrap; background: var(--shade); border-radius: 999px; }
.status.done { background: var(--success-soft); }
.status.started { background: var(--primary-soft); }
.status.blocked { background: var(--warning-soft); }

/* the footer */
body > footer { margin-top: 3.5rem; padding-top: 1.2rem; position: relative; color: var(--muted); font-size: .86rem; line-height: 1.5; }
body > footer::before { content: ""; position: absolute; left: 0; right: 0; top: 0; height: 8px; background: var(--line);
  -webkit-mask: var(--wave-line) 0 50% / 32px 8px repeat-x; mask: var(--wave-line) 0 50% / 32px 8px repeat-x; }
body > footer p { margin: 0 0 .5rem; }
body > footer a { color: var(--muted); }
/* the notebook that made the page, folded at its foot */
body > footer details.source { margin-top: .8rem; color: var(--ink); }
body > footer details.source > summary { color: var(--muted); font-size: .86rem; }

@media (max-width: 480px) {
  body { font-size: 17px; padding: 0 .95rem 3rem; }
  h1 { font-size: 1.95rem; }
  h2 { font-size: 1.32rem; }
  .masthead .cadence { margin-left: 0; }
}
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .cards .note, details.fold > summary::before { transition: none; }
}
@media print {
  .crumbs, .rv-enter .rv-toggle { display: none; }
  body { max-width: none; }
}
"""

func scoped*(rules, scope: string): string =
  ## Puts `scope` before every selector of `rules`; `html` itself becomes `scope`. Rules inside
  ## `@media` are scoped too; comments are kept. (Used by the review mode, `review.nim`.)
  var i = 0
  while i < rules.len:
    if rules.continuesWith("/*", i):
      let e = rules.find("*/", i) + 2
      result.add rules[i ..< e]; i = e
    elif rules[i] in {'}', '\n', ' '}:
      result.add rules[i]; inc i
    elif rules.continuesWith("@media", i):
      let e = rules.find('{', i) + 1
      result.add rules[i ..< e]; i = e
    else:
      let e = rules.find('{', i)
      var sels: seq[string]
      for s in rules[i ..< e].split(','):
        let s = s.strip
        sels.add(if s == "html": scope else: scope & " " & s)
      let close = rules.find('}', e)
      result.add sels.join(", ") & " " & rules[e .. close]; i = close + 1

const css* = fonts & tokens & marks & rules
  ## All the CSS of a page.

const wordmarkSvg* = """<svg viewBox="0 0 32 32" aria-hidden="true">""" &
  """<circle class="ember" cx="20" cy="11" r="6.5"/>""" &
  """<path class="sea" d="M1 21c4.5 0 5.5-6 10.5-6s6 6 10.5 6 5-3.5 9-3.5V31H1z"/></svg>"""
  ## nimaki's mark: an ember of Pele's fire, and Nāmaka's wave reaching it. The header puts it
  ## before the name; its colours come from the tokens (`.wordmark .ember`, `.wordmark .sea`).

proc assetHref*(name, pageFile: string): string =
  ## The link from a page (its HTML file) to a file the pages share, `docs/assets/<name>`.
  relativePath(assetsDir / name, absolutePath(pageFile).parentDir).replace('\\', '/')

proc siteCss*(pageFile: string, extra = ""): string =
  ## What a page puts in its head for its style: a link to `docs/assets/site.css` (written when
  ## it changed), relative to the page; with `-d:singleFile`, the CSS itself. `extra` is CSS of
  ## other modules every page has (the review mode's).
  when singleFile:
    "<style>\n" & css & extra & "</style>"
  else:
    let file = assetsDir / "site.css"
    if not fileExists(file) or readFile(file) != css & extra: writeFile(file, css & extra)
    &"""<link rel="stylesheet" href="{assetHref("site.css", pageFile)}">"""

const tokenColours* = ["--paper", "--shade", "--line", "--muted", "--ink", "--surface",
  "--primary", "--primary-soft", "--primary-text", "--secondary", "--secondary-soft", "--secondary-text",
  "--warning", "--warning-soft", "--success", "--success-soft", "--success-text"]
  ## The tokens a page may name in a table colour, as `tint("--secondary")`.

func tint*(token: string): string =
  ## A token as a CSS colour, for tabelline's colour arguments: `style.fill(tint("--secondary-soft"))`.
  doAssert token in tokenColours, "not a token: " & token
  "var(" & token & ")"
