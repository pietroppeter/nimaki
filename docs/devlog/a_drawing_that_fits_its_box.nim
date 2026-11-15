## devlog: 15 Nov 2026 N | A drawing that fits its box | Pele's browser side, ported: a diagram put in a box of a page and drawn again when the box changes width or its fonts load, zoom and pan for a drawing shrunk to fit, and text measured with the page's own font. Pele's own tests of all three pass on the port.
## kind: port
import std/[json, strformat, strutils, os]
import nimib
import ../blocks
import nimaki/zoom

nbInit
nb.usePost()

const docs = currentSourcePath().parentDir.parentDir
let tests = parseJson(readFile(docs / "data" / "peletests.json"))
proc passed(file: string): int = tests["byFile"][file]["passed"].getInt
proc total(file: string): int =
  for k, v in tests["byFile"][file]: result += v.getInt
let mountTests = passed("tests/mount.test.ts")
let zoomTests = passed("tests/zoom.test.ts")
let measurerTests = passed("tests/util/measurer.test.ts")
let entriesTests = passed("tests/entries.test.ts")
let browserTests = mountTests + zoomTests + measurerTests
let counts = tests["counts"]

nbText: &"""
## The findings, first

- **Pele's browser side is ported.** `mount` puts a diagram in a box of a page and keeps it
  fitted: it draws again when the box changes width or when the page's fonts finish loading, and
  keeps the last good drawing, dimmed, under an error. `enableZoom` lets a reader enlarge a drawing
  that was shrunk to fit and move about in it, with a finger, a mouse or the keys. And the text
  measurer has its second half: in a browser, nimaki measures text with the page's own font, as
  Pele does.
- **Pele's own tests of these pass on the port**: {mountTests} of {total("tests/mount.test.ts")}
  in `mount.test.ts`, {zoomTests} of {total("tests/zoom.test.ts")} in `zoom.test.ts` and
  {measurerTests} of {total("tests/util/measurer.test.ts")} in `measurer.test.ts`, the canvas ones
  included. Pele tests its browser side without a browser, on fake elements, and those fakes now
  meet nimaki's code instead of Pele's.
- **A page's `nimaki` is now Pele's `pele`**: the same functions under the same names (`render`,
  `parse`, `mount`, `enableZoom`, `PeleError`, the lazy `renderAsync`...), so that a page written
  for Pele's bundle can load nimaki's instead. The playground below and on the
  [Playground page](../../playground/) draws with `mount`.
- **One thing does not match yet: the size.** nimaki's JavaScript file is about 9 MB (1.4 MB
  compressed), where Pele's bundle is 730 kB. A smaller build is in the backlog, by Pietro's choice
  this morning; until then a page that cares about weight keeps Pele's bundle.
"""

nbText: """
## Try it

The box below is drawn by `mount`, in your browser. The flowchart runs across, and on a phone
there is no room for that: `mount` draws it for the width the box has, and it turns to run
down. Turn the phone sideways, or widen the window, and it is drawn again for the new width. The
three small buttons in its corner enlarge it, reduce it and (once enlarged) reset it; pinch it,
drag it, double tap it too. This box asks for them always (the option `zoom: true`); by default
they come only with a drawing that had to be shrunk to fit. Edit the text: a mistake leaves the
last drawing in place, dimmed, with the error over its bottom edge.
"""

nbPlayground """flowchart LR
  text["Mermaid text"] --> parse["parse"] --> model[("model")]
  model --> render["render, for the width there is"] --> svg(["SVG in the box"])
  svg -->|"the box changes width"| render
  svg -->|"the fonts load"| render
""", """{"zoom": true}"""

nbText: """
## What "the browser side" is

Everything nimaki did until today happens without a page: Mermaid text goes in, SVG text comes
out, and the same input always gives the same bytes. That is all a build needs, and it is what
the referee checks. A page that shows a diagram needs three more things, and Pele has them in
three files of its own, about 1,100 lines of TypeScript.

**Putting a drawing in a box** (`src/mount.ts`). A page has a box for the diagram, an element.
`mount(element, text)` reads the text once (`parse`), draws it for the width the box has, and puts
the SVG in it. Then it keeps watching, because a page changes under its diagrams:

- The box changes width (a phone turned sideways, a side panel opened). The browser reports it
  through a *ResizeObserver*, an object that calls back when an element's size changes. Many
  changes can come in one moment, so the redraw waits for the next *frame*, the moment the
  browser paints (`requestAnimationFrame`), and is done once.
- The fonts finish loading. A page's font often arrives after the page; text measured before
  that was measured in a fallback font, with other widths. The browser says when its fonts are
  ready (`document.fonts.ready`), and the diagram is measured again.
- The text changes, through `update`. Text that cannot be drawn does not wipe the box: the last
  good drawing stays, dimmed to 40%, and the error sits over its bottom edge.

**Zooming** (`src/zoom.ts`). A diagram wider than its box is shrunk to fit. To read it, the reader
enlarges it, and the box shows less of it, larger: the drawing's `viewBox`, the part of the SVG
that is shown, gets smaller while the box keeps its size.

**Measuring with the page's font** (the canvas half of `src/text/measurer.ts`). To place a label,
Pele must know how wide its text is. Without a page, it uses a table of Arial's widths, and so
does nimaki in C, in Node and at build time. In a page there is a *canvas*, an element for
drawing pictures in script, and its `measureText` gives the width of a text in any font the page
has. Pele uses it there, and now nimaki does too.
"""

nbNote """
`mount` draws twice when it must. If the drawing, once in the page, sees a different font than
its box (a style may set `--pele-font` on the drawing itself), it is measured again for that font
at once. And to know whether a narrow box changes the drawing at all, Pele draws it once for no
room at all (`maxWidth: 1`): a pie chart comes out the same and is never drawn again for a width,
while a flowchart that runs across turns to run down. [`src/mount.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/mount.ts)
""", nkPele, "How Pele does it"

nbText: """
## The part of a drawing a box shows

The arithmetic of the zoom is one small function, `frame`, and it is the one part of the browser
side that is plain Nim in both builds, so it runs here. A drawing 1,200 by 300 pixels in a box 400
by 100: at scale 1 the box shows a 400 by 100 piece of it, starting where the reader dragged it to,
but never past the drawing's own edges.
"""

nbCode:
  let drawing = (width: 1200.0, height: 300.0)
  let box = (width: 400.0, height: 100.0)
  echo frame(drawing, box, 400 / 1200, 0, 0)    # shrunk to fit: all of it
  echo frame(drawing, box, 1, 300, 120)         # at its natural size, dragged
  echo frame(drawing, box, 1, 5000, 5000)       # dragged too far: stops at the corner
  echo frame(drawing, box, 2, -50, -50)         # twice as large, dragged past the start

nbText: """
The rest of `zoom.ts` turns gestures into calls of `frame`. A pinch is two fingers on the screen:
the distance between them grows by some factor, and the scale grows by the same factor, around the
point between the fingers, so that what is under the fingers stays there. The wheel zooms only
with Ctrl or ⌘ held (without it, the wheel scrolls the page), and the keys `+`, `-`, `0` and the
arrows do the same from the keyboard.

## How the port is written

Pele writes `mount` as one function whose local variables are the diagram's state (what is shown,
the width it was drawn for, the fonts it was measured with) and whose inner functions are its
steps (`fit`, `draw`, `refresh`, `mark`). It returns an object of closures over that state. The
port keeps exactly that shape: `mountWith` in `src/nimaki/mount.nim` is one proc with the same
variables and the same inner procs, in the same order, so that the two can be read side by side.
`zoomWith` in `src/nimaki/zoom.nim` is written the same way.
"""

nbNote """
What comes from the page stays a JavaScript value (`JsObject` of Nim's `std/jsffi`): the element,
its computed style, an event, the options, and the models and results of the engine. Converting
them to Nim types would be wrong here, not just slow: Pele's tests give fake elements that have
only some of an element's fields, and Pele reads a missing field as `undefined` (`element.isConnected
=== false` is false for a fake without the field, `!(element.clientWidth > 0)` is true when the
width is missing). `src/nimaki/dom.nim` holds the few such operators, each written to mean what
JavaScript means.
""", nkNim, "JavaScript values, JavaScript meanings"

nbText: """
Four traps of `nim js` showed up on the way, each worth a line in the porting guide:

- **A method called `delete`.** `map.delete(key)` through `std/jsffi` does not call the method:
  `delete` is a word JavaScript reserves, and jsffi renames it. The port calls it by name
  (`invoke("delete", key)`). Pele's tests found it at once: every test that removes a pointer or a
  font wait failed.
- **A method with the name of a proc in scope.** Inside `mountWith`, `zoomer.refresh()` called the
  local `refresh` proc with `zoomer` as its argument, by Nim's method call syntax, instead of the
  zoom's own `refresh`. Again `invoke("refresh")`.
- **An error that is not Nim's.** In the JavaScript build `getCurrentException()` is nil when what
  was caught was thrown by JavaScript (Pele's `PeleError` from the engine, a host's `onRender`).
  `mount` must keep that very value and hand it to `onError`, so it reads it as caught
  (`caughtError()`, the `lastJSError` of Nim's runtime) and throws it again as it was.
- **Backticks in `importjs`.** A JavaScript template literal (`` `${a} ${b}` ``) inside an
  `importjs` pattern breaks the pattern: Nim reads backticks there itself.

## How it is checked

The referee compares SVG bytes, and a box on a page is not bytes. But Pele's own tests of its
browser side do not need a browser: they build fake elements with a width, a fake `getComputedStyle`
and a fake `ResizeObserver` whose callback the test fires by hand, and check what `mount` puts in
the element and when. `tools/peletests.nim` already ran Pele's suites on nimaki's JavaScript build;
now it also points the tests' imports of `src/mount.js`, `src/zoom.js` and `src/text/measurer.js`
to the port (`tools/peletests/mount.mjs`, `zoom.mjs`, `measurer.mjs`), so these tests meet nimaki's
code with Pele's expectations.
"""

nbNote &"""
- `tests/mount.test.ts`: {mountTests} of {total("tests/mount.test.ts")} pass on the port (before
  today, 24 of them were counted apart as `api`: they called what nimaki did not have).
- `tests/zoom.test.ts`: {zoomTests} of {total("tests/zoom.test.ts")}; until today they ran Pele's
  own zoom, as the test imports it directly.
- `tests/util/measurer.test.ts`: {measurerTests} of {total("tests/util/measurer.test.ts")}, the
  canvas measurer's included (it was the one `canvas` test).
- `tests/entries.test.ts`: {entriesTests} of {total("tests/entries.test.ts")}: `registered` is
  nimaki's now.
- Over all of Pele's suites: {counts["passed"].getInt} of {tests["tests"].getInt} pass,
  {counts["api"].getInt} `api`, {counts["canvas"].getInt} `canvas`, {counts["failed"].getInt} failed.
- In a real browser (Chromium, at 390 pixels wide): the playground above mounts, draws again when
  the window is resized (the flowchart runs down at 390 pixels and across at 800), enlarges with
  its buttons, and keeps the drawing
  dimmed under an error while the text is wrong.
""", nkDone, "Checked"

nbText: """
## A page's nimaki is Pele's pele

`src/nimaki/web.nim`, compiled with `nim js`, is the file a page loads. Until today it gave one
function, `nimaki.render`, which returned `{ok: false}` on an error. It now gives what Pele's
browser bundle gives, under the same names and with the same behaviour: `render` throws a
`nimaki.PeleError` with Pele's `code`, `line`, `column` and `snippet`; `parse` returns a model
that `render` draws; `mount` and `enableZoom`; `detectType`, `supports`, `registered`,
`forgetTextWidths`. Pele also has a lazy entry point, which loads a diagram type's code the first
time it is needed (`load`, `renderAsync`, `mountAsync`). nimaki.js holds every type already, so
those functions are there, with nothing to load: a page written for the lazy entry point works
unchanged.

```js
const handle = nimaki.mount(document.querySelector('#flow'), 'flowchart LR\n  A --> B', {
  onError: (e) => console.warn(e.code, e.message),
});
handle.update('flowchart LR\n  A --> B --> C');   // the same box, new text
```

In a browser `render` now measures with the canvas by default, as Pele's does, so its bytes are
those of the page's font. A page that must draw the same bytes as the build (the live figures of
these pages, which compare the two) passes `measurer: nimaki.metricsMeasurer`.
"""

nbNote """
- **The size of nimaki.js.** Every type in one file of about 9 MB, which compresses to 1.4 MB.
  Pele's whole bundle is 730 kB, and its lazy entry point loads a few tens of kB a type. Making the
  JavaScript build smaller (and splitting it by type, for real lazy loading) is the roadmap step
  [A smaller JavaScript build](../../roadmap/), in the backlog: Pietro's answer this morning was
  "not now".
- **`register`** is not there: in Nim the types are chosen at compile time, so there is nothing to
  register in a page.
""", nkWarning, "Not done"

nbText: """
## What this changes for the port

- The roadmap step *Pele's browser side* is done: `src/mount.ts`, `src/zoom.ts`, `src/window.ts`
  and the canvas half of `src/text/measurer.ts` are ported, and marked `conformant`. Decision
  0014 asks for the referee, the fuzzer and Pele's tests to agree; the referee and the fuzzer
  compare SVG, which these files do not make, so here Pele's tests are the whole check, and every
  one of them passes. With them, every file of the port map is conformant.
- The last `api` and `canvas` tests of Pele's suites pass; what Pele's tests still count apart is
  the time limits of a few stress tests in the JavaScript build, and the known ones.
- For diagrammari, whose client mode calls `pele.mount` with Pele's bundle: nimaki.js can take the
  bundle's place, with the same calls, once its size is acceptable. The proposal post is updated
  in the next step.
- Next: nimaki 0.2.0, with this in it.

## Sources

- Pele at the pin: [`src/mount.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/mount.ts),
  [`src/zoom.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/zoom.ts),
  [`src/window.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/window.ts),
  [`src/text/measurer.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/text/measurer.ts),
  [`src/lazy.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/lazy.ts),
  and the tests [`tests/mount.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/mount.test.ts),
  [`tests/zoom.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/zoom.test.ts)
  and [`tests/util/measurer.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/util/measurer.test.ts),
  read for this post.
- The browser's side of it, on MDN: [ResizeObserver](https://developer.mozilla.org/en-US/docs/Web/API/ResizeObserver),
  [requestAnimationFrame](https://developer.mozilla.org/en-US/docs/Web/API/Window/requestAnimationFrame),
  [FontFaceSet.ready](https://developer.mozilla.org/en-US/docs/Web/API/FontFaceSet/ready),
  [CanvasRenderingContext2D.measureText](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/measureText),
  [viewBox](https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/viewBox).
- The port: `src/nimaki/mount.nim`, `zoom.nim`, `window.nim`, `dom.nim`, `jsapi.nim`, `web.nim`,
  `text/measurer.nim`; `tools/peletests/` for the tests' aliases.
- The size of Pele's bundle: diagrammari's vendored `pele.global.js`, as the post
  [A proposal for diagrammari](../a-proposal-for-diagrammari/) measured it.
"""

nbSave
