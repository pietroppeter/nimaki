## devlog: 13 Nov 2026 J | Drawn in your browser | nimaki compiled to JavaScript now draws on the site itself: a playground to type Mermaid in, and diagrams that the reader's browser draws again and checks byte for byte against the build.
## kind: tooling
import std/[strformat, strutils, os]
import nimib
import ../blocks, ../pele
import nimaki

nbInit
nb.usePost()

let jsFile = nimakiJs()   # builds docs/assets/nimaki.js, as every page that draws live does
let megabytes = formatFloat(getFileSize(jsFile).float / 1_000_000, ffDecimal, 1)

nbText: &"""
## The findings, first

- **The site draws with nimaki in your browser.** A new living page, the
  [Playground](../../playground/), has a box for Mermaid text that nimaki draws as you type, and
  diagrams that come with the page and are drawn again when it opens.
- **Same bytes as the build.** Each of those diagrams carries the SVG nimaki (compiled to C) made
  when the site was built. The browser's nimaki (compiled to JavaScript) draws the text again and
  compares: in the sandbox's Chromium, at phone width, every one was the same, byte for byte, in
  both looks. The diagram below does the same check in your browser now.
- **One entry point.** `src/nimaki/web.nim` defines `nimaki.render(text, options)` for a page, as
  Pele's bundle defines `render`. It is about {megabytes} MB, not minified, and loaded only by a
  page that draws live.
- **Two blocks** for the pages: `nbLive` and `nbPlayground`, with their script in
  `assets/live.js`.

## The diagram below is drawn twice
"""

let source = """flowchart LR
  text["Mermaid text"] --> c["nimaki, compiled to C"]
  text --> js["nimaki, compiled to JavaScript"]
  c -->|when the site is built| svg1(["SVG"])
  js -->|in your browser| svg2(["SVG"])
  svg1 -.-|the same bytes?| svg2
"""

nbText: &"""
```mermaid
{source.strip}
```
"""

nbCode:
  let built = render(source, RenderOptions(now: fixedNow)).svg
  echo built.len, " bytes of SVG, drawn when this page was built"

nbLive source, built, "The two ways nimaki draws. The line below says what your browser found.", """{"now": 1767225600000}"""

nbText: """
When this page was built, nimaki drew the text above in the build's own process, compiled to C,
and the page carries that SVG. When the page opens, a small script, `assets/live.js`, loads
nimaki compiled to JavaScript, draws the same text with the same options, puts its drawing in
place of the one from the build, and compares the two strings. If JavaScript is off, the drawing
from the build stays, and nothing else changes.

## How a page loads nimaki

The [previous post](../nimaki-in-javascript/) compiled nimaki to JavaScript for Node, to check it
against Pele. A page needs a different entry point: no files to read, but a function to call.
`src/nimaki/web.nim` is that entry point. It turns the options (a JavaScript object, as Pele
takes) into nimaki's `RenderOptions`, calls `render`, and gives back a plain object:

```js
const r = nimaki.render("pie\n  \"a\" : 1", { maxWidth: 390 });
// { ok: true, svg: "<svg ...", width: ..., height: ... }
// or { ok: false, code: "syntax", message: "Parse error on line 2: ..." }
```

When the pages are built, the first page that needs it compiles it, with
`nim js -d:danger`, into `docs/assets/nimaki.js`. The file is not committed: CI builds it with the
pages and publishes it with them. A page that draws live adds `assets/live.js`, which loads
`nimaki.js` only when the page has a live block, so the other pages stay as light as before.

## Two blocks

The pages are written with blocks, never with HTML (the rule of
[AGENTS.md](../../agents/)), so the browser's nimaki comes as two new blocks in
`docs/blocks.nim`:

- `nbLive(source, svg, caption, options)`: a diagram drawn at build time, which the browser draws
  again and checks, as above.
- `nbPlayground(source, options)`: a text area and a drawing under it, redrawn as you type. An
  error shows Pele's message, which points at the column; a type not ported yet says so.

Their look is in `docs/theme.nim`, from the tokens, in both modes.
"""

nbNote """
- `src/nimaki/web.nim` is the browser's entry point; it ports no Pele file. Decision 0013 already
  says that `src/` builds with `nim js`; nothing in the renderer changed.
- The Playground is a living page with a card on the home page. The list of types it says nimaki
  draws comes from the referee's last run.
""", nkNim, "In the port"

nbNote """
- In Chromium (the sandbox's, headless, 390 px wide, both looks): every live diagram of the
  Playground identical to the build, the playground drawing as text is typed, a type not ported
  yet and a syntax error answered in words.
- The C and JavaScript builds already agree on every case of the corpus (`difftest --js`, in CI).
""", nkDone, "Checked"

nbNote &"""
- Safari and Firefox were not tried: their JavaScript engines may differ in the floating-point
  functions the layout uses. The check under each live diagram will say so if they do.
- The file is {megabytes} MB before compression, which is a lot for a phone; GitHub Pages sends it
  compressed. Making it smaller (dropping unused parts, minifying) is open.
- Speed: a few tens of milliseconds per diagram in the sandbox, measured by the page itself.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **The [Playground](../../playground/)** is where to see nimaki work, on any device with a
  browser. Its live diagrams are a check that runs on the reader's own engine.
- **Posts can draw live** with `nbLive`, as this one does.

## Sources

- The code of this step: [`src/nimaki/web.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/web.nim),
  [`docs/assets/live.js`](https://github.com/pietroppeter/nimaki/blob/main/docs/assets/live.js),
  [`docs/blocks.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/blocks.nim),
  [`docs/playground.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/playground.nim).
"""

nbSave
