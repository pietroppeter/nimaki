## devlog: 13 Nov 2026 M | What a label holds | A label in Pele can hold Markdown, HTML tags, icons, math and text that wraps; icons and math come from the page that hosts the diagram, so the referee had never run them. Now it does, on both sides, and a fuzzer made of labels finds no difference.
## kind: tooling
import std/[os, json, strformat, strutils]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import ../../tools/answers

nbInit
nb.usePost()

let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["labels"]
let js = parseFile(docsDir / "data" / "js.json")["fuzz"]["labels"]
let corpus = parseFile(repoDir / "corpus" / "cases.json")["cases"]
var withMath, withIcons = 0
for c in corpus:
  if "$$" in c["source"].getStr: inc withMath
  if ":fa-" in c["source"].getStr: inc withIcons

nbText: &"""
## The findings, first

- **Every label feature draws identically to Pele.** A new fuzzer writes diagrams whose labels mix
  Markdown, HTML tags, icons, math, Chinese and Japanese text, soft hyphens and entities:
  {fuzz["cases"].getInt.thousands} of them come out identical, byte for byte, on every run of CI
  ({fuzz["rendered"].getInt.thousands} drawings, {fuzz["errors"].getInt.thousands} error
  messages). Before merging, 15,000 more on three other seeds agreed, and so did the JavaScript
  build of nimaki on {js["cases"].getInt.thousands}.
- **Icons and math had never been checked.** Both come from the page that hosts the diagram, as
  functions, and functions do not travel through the referee's JSON. The corpus has
  {withMath} diagram with `$$` math and {withIcons} with a `fa:` icon, and difftest drew them
  without a host, so the code that lays them out never ran.
- **Now both sides get the same made-up host.** `icons: "test"` and `math: "test"` stand for two
  small functions, written once in JavaScript for Pele and once in Nim for nimaki. CI runs the
  whole corpus with them too, and every fuzzer was run with them once before merging: no
  difference.
- **Not done in this step**: the second reading of `src/text` against the TypeScript (decision
  0005), which moves its files from *draft* to *verified*. It was started and stopped by a usage
  limit; it is the first thing to do on the next start.

## What a label holds

A label is the text in a box or beside a line. In Mermaid, and so in Pele, it is more than text:

- **Line breaks**: `<br>`, or `\n`.
- **HTML tags** that change the style: `<b>`, `<i>`, `<code>`, `<sub>`, `<sup>`, `<u>`. Other tags
  are dropped and their text kept; something shaped like a tag that is not HTML, as the `<T>` of
  `List<T>`, stays text.
- **Markdown emphasis**, in labels written as Markdown (in a flowchart, between backquotes):
  `**bold**`, `*italic*`, `_italic_` (but not the underscores of `snake_case`).
- **Icons**, written `fa:fa-car`: Font Awesome's names, drawn by whatever icon set the host page
  has.
- **Math**, written `$$\frac{{a}}{{b}}$$`, typeset by whatever the host page uses (KaTeX, MathJax).
- **Wrapping**: a label wider than its room breaks at spaces, between any two Chinese or Japanese
  characters, at a zero-width space, and at a soft hyphen, which then shows as `-`.

Here is one label with most of them, drawn by Pele and by nimaki with the same made-up host. The
"icon" is a slanted line and the "math" a filled box as wide as the TeX is long, which is all the
referee needs:
"""

let label = """flowchart LR
  A["`**Bold**, H<sub>2</sub>O, fa:fa-car a car, $$\frac{a}{b}$$ and a soft hyphen in super­cali­fragilistic`"] --> B["日本語のラベルは文字の間で折り返す"]
"""
let host = %*{"icons": "test", "math": "test", "maxWidth": 390}

nbText: &"""
```mermaid
{label.strip}
```
"""

let fromPele = peleSvg(label, host)
nbSvg fromPele, "Pele 1.13.0, in Node, with the test host."

nbCode:
  let fromNimaki = render(label, toOptions(host)).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbText: """
## A made-up host

The host gives Pele two functions in its render options. `icons(name)` returns the SVG of an icon,
or nothing; a label leaves room for an icon only when the host has it. `math(tex, size)` returns
the typeset formula, as SVG or as HTML, with its width and height; Pele drops an answer whose
size is not a positive number. The test host covers each of those cases, chosen by what the name
or the TeX contains, so a fuzzer can reach them by writing words:
"""

nbCode:
  for tex in ["x^2", "\\frac{a}{b}", "html", "bad", "nan"]:
    let m = toOptions(%*{"math": "test"}).math(tex, 16)
    if m == nil: echo tex.alignLeft(12), " no formula"
    else: echo tex.alignLeft(12), " ", (if m.isSvg: "svg " else: "html"), " ", m.width.formatFloat(ffDecimal, 1), " x ", m.height.formatFloat(ffDecimal, 1)

nbText: """
The same two functions are in `tools/oracle.mjs`, for Pele:

```js
function testIcons(name) {
  return name.includes('none') ? null : `<path d="M0 0L${name.length} 24"/>`;
}
function testMath(tex, size) {
  if (tex.includes('bad')) return null;
  const width = tex.length * size * 0.55;
  const height = size * (tex.includes('frac') ? 2.25 : 1.2);
  if (tex.includes('nan')) return { svg: '<g/>', width: NaN, height };
  if (tex.includes('html')) return { html: `<span class="m">${tex.length}</span>`, width, height };
  return { svg: `<svg viewBox="0 0 ${tex.length} 1"><rect width="${tex.length}" height="1"/></svg>`, width, height };
}
```

`name.length` counts UTF-16 code units in JavaScript; the Nim side counts the same way.

## The fuzzer

`tools/fuzz.nim labels` builds a label from one to six pieces: words (plain, accented, Chinese,
Japanese, emoji, a word too long for any box, words with soft hyphens or zero-width spaces,
entities) and marks (each tag, open and unclosed tags, Markdown emphasis, line breaks, icons that
the host has and does not have, formulas that typeset as SVG, as HTML, as nothing, with a bad size,
and unclosed `$$`). It puts the labels where five types draw them: flowchart nodes, edges and
subgraph titles, with and without Markdown; sequence messages, notes and participants; state
descriptions, notes and transitions; class notes and relations; timeline titles and events.
Seven cases in ten get each host function. CI runs 5,000:
"""

nbCode:
  echo "fuzz: labels, seed ", fuzz["seed"].getInt, ", ", fuzz["cases"].getInt, " cases: ",
    fuzz["identical"].getInt, " identical, ", fuzz["different"].getInt, " different"

nbText: """
Two flags bring the host to the other tools: `difftest --hosts` draws the whole corpus with it
(CI runs it as a step of its own), and `fuzz --hosts` gives it to every case of any fuzzer.
"""

nbNote """
- The label fuzzer: 5,000 cases on seed 1 and 15,000 on seeds 2 to 4, identical; 2,000 in the
  JavaScript build, identical.
- The whole corpus with the test host: no difference.
- Every other fuzzer, 1,500 cases each on seed 7 with the test host: no difference.
""", nkDone, "Checked"

nbNote """
- The second reading of `src/text` (decision 0005), so its files are still *draft*.
- The test host is not a real one. A real typesetter returns markup the port only copies, so its
  content does not matter; its sizes do, and the test host's are only a few.
- Measuring text with a measurer other than Pele's default (a canvas in a browser) is not covered
  here: the referee always measures with Pele's metrics.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- The label features are checked against Pele, in every type that draws them, on every run of CI.
- **Where the work stopped** (the project is paused): this step is done except for the second
  reading of `src/text`, which is the first thing to do on the next start. The next step,
  *Run Pele's own test suites*, is on the [roadmap](../../roadmap/) and not started.

## Sources

- Pele at the pin: [`src/text/label.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/text/label.ts),
  [`src/text/math.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/text/math.ts),
  [`src/text/icons.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/text/icons.ts)
  and the resolver types in [`src/types.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/types.ts),
  read for this step.
- The code of this step: [`tools/answers.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/answers.nim),
  [`tools/oracle.mjs`](https://github.com/pietroppeter/nimaki/blob/main/tools/oracle.mjs),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim),
  [`tools/difftest.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/difftest.nim).
"""

nbSave
