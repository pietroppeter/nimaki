## devlog: 13 Nov 2026 A | Fishbones and domains: ishikawa and cynefin | Two small beta diagrams join the port: a fishbone of causes and a map of five ways a situation can be, whose wavy borders come from a seeded random number generator that has to match JavaScript's bit for bit.
## kind: port
import std/[os, strformat, strutils, json, tables, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/diagrams/cynefin/boundaries

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
var same = initTable[string, int]()
for r in difftest["types"]:
  cases[r["type"].getStr] = r["cases"].getInt
  same[r["type"].getStr] = r["identical"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]
proc fuzzed(kind: string): string =
  if fuzz.hasKey(kind): fuzz[kind]["cases"].getInt.thousands else: "no"

nbText: &"""
## The findings, first

- **Two more types.** Ishikawa ({same["ishikawa"]} of {cases["ishikawa"]} corpus cases identical)
  and cynefin ({same["cynefin"]} of {cases["cynefin"]}) come out of nimaki byte for byte as Pele
  draws them. Both are *beta* in Mermaid: they start with `ishikawa-beta` and `cynefin-beta`.
- **The fuzzer writes both.** CI draws {fuzzed("ishikawa")} generated fishbones and
  {fuzzed("cynefin")} generated cynefin maps on every pull request and compares each with Pele's.
  Before merging, seeds 1 to 3 (3,000 cases each, per type) were identical too.
- **Randomness, made repeatable.** Cynefin's borders wiggle, and the wiggle comes from a small
  random number generator, *mulberry32*, seeded by a hash of the diagram's id. It is written with
  JavaScript's 32-bit integer tricks (`Math.imul`, `>>>`, `|0`), which Nim spells with casts
  between `int32` and `uint32`. Every bit has to agree, or every curve moves.
- **No new shared code.** Both types use the labels, the root `<svg>` and the fitting to a
  narrow host that earlier steps ported; ishikawa turns itself on its side when it does not fit.

## A fishbone

An *Ishikawa diagram*, or fishbone, starts from a problem, the head of the fish, and lists its
causes along bones that join the spine. Each category of cause gets a bone; the causes inside it
are smaller bones on that one, and so on. Mermaid reads the tree from the indentation, like an
outline:
"""

let fishText = """ishikawa-beta
    Late release
    People
        Two on holiday
        New to the code
    Process
        Review waits a day
        Tests are slow
            One suite takes an hour
    Tools
        Flaky CI
"""

nbText: &"""
```mermaid
{fishText.strip}
```
"""

nbCode:
  let fishPele = peleSvg(fishText)
  let fishNim = render(fishText).svg
  echo "identical to Pele's: ", fishNim == fishPele

nbSvg fishNim, "A fishbone, drawn by nimaki; Pele draws the same bytes."

nbText: """
The first line under the keyword is the problem; every line indented under it is a cause.
Categories alternate above and below the spine, and their causes alternate between slanted
bones and level ones, so a deep cause still reads left to right. The lexer is Mermaid's Jison
lexer again, ported as a loop that tries each rule at the current position ([the timeline
post](../timeline/) explains the idea); the depth of a line is the length of its leading spaces,
counted in UTF-16 units as JavaScript counts them.

On a phone the head cannot sit at the right of a wide fish. When the host is narrower than the
drawing, Pele draws the causes as a column under the problem instead, and so does nimaki:
"""

nbCode:
  let narrowPele = peleSvg(fishText, %*{"maxWidth": 320})
  let narrowNim = render(fishText, RenderOptions(maxWidth: some(320.0))).svg
  echo "identical to Pele's at 320 pixels: ", narrowNim == narrowPele

nbSvg narrowNim, "The same fishbone in 320 pixels: the causes in a column."

nbText: """
## Five domains

The *Cynefin framework* (a Welsh word, said *kuh-NEV-in*) sorts situations by how cause and
effect relate in them: *clear* (the answer is known), *complicated* (an expert can work it out),
*complex* (you learn by trying), *chaotic* (act first), and *confusion* in the middle, for when
you do not yet know which. Mermaid's diagram puts the four in quadrants, confusion in the
center, items in each, and arrows for moves between domains:
"""

let cynefinText = """cynefin-beta
  title A port, by domain
  complex
    "How to explain a layout"
  complicated
    "Port the sequence diagram"
  clear
    "Run the referee"
  chaotic
    "CI is red on main"
  confusion
    "A new diagram type"
  chaotic --> complex : "Stabilized"
  complex --> complicated : "Pattern found"
"""

nbText: &"""
```mermaid
{cynefinText.strip}
```
"""

nbCode:
  let cynPele = peleSvg(cynefinText)
  let cynNim = render(cynefinText).svg
  echo "identical to Pele's: ", cynNim == cynPele

nbSvg cynNim, "A cynefin map, drawn by nimaki; Pele draws the same bytes."

nbText: """
## Random, but the same every time

The borders between domains are not straight: they wave, as hand-drawn Cynefin maps do, and the
cliff between clear and chaotic is an S. A drawing that changed every time it was rendered would
be useless to compare, to cache, or to review, so the waves are *pseudo-random*: numbers that look
random but follow from a starting number, the *seed*. The same seed gives the same waves.

Pele makes the seed from the diagram's id (the `idPrefix` option, `pele` when none is given)
with a classic string hash: start at 0, and for each UTF-16 unit multiply by 31 and add the
unit, keeping 32 bits. Then *mulberry32*, a tiny generator of a few lines, turns the seed plus a
step into a number between 0 and 1. Each point of a wave takes its own step, so the waves look
irregular but are fixed. Both run on this page, ported:
"""

nbCode:
  echo "hash of \"pele\":  ", hashString("pele")
  echo "hash of \"other\": ", hashString("other")
  for step in 0 .. 3:
    echo "mulberry32(", step, ") = ", seededRandom(float(step))

nbText: """
Change the id and the hash changes, so the waves move; keep it and they stay put. Pele's own
answer for the same id is the same drawing, and that is what the referee checks:
"""

nbCode:
  let other = RenderOptions(idPrefix: some("other"))
  let otherNim = render(cynefinText, other).svg
  echo "a different id draws different borders: ", otherNim != cynNim
  echo "and still Pele's: ", otherNim == peleSvg(cynefinText, %*{"idPrefix": "other"})

nbNote """
JavaScript has one kind of number, a 64-bit float. Its bit operators (`^`, `|`, `>>>`) first
turn it into a 32-bit integer (*ToInt32* in the specification: drop the fraction, wrap around
2^32), and `Math.imul` multiplies two of them keeping the low 32 bits. mulberry32 is built from
nothing else. Nim has real 32-bit integers, but its `int32` arithmetic stops with an overflow
error where JavaScript wraps, so `boundaries.nim` does the arithmetic on `uint32`, which wraps,
and casts back to `int32` where the sign matters. `toInt32` follows the specification for
values far outside 32 bits, NaN and infinity, which a configured `seed` can be.
""", nkNim, "32-bit integers in a language of floats"

nbNote &"""
- `nim r tools/difftest.nim ishikawa`: {same["ishikawa"]} of {cases["ishikawa"]} identical;
  `cynefin`: {same["cynefin"]} of {cases["cynefin"]}.
- `nim r tools/fuzz.nim ishikawa` and `cynefin`: 5,000 cases on seed 1 and 3,000 on each of
  seeds 1 to 3, all identical, error messages included. The generators vary indentation (spaces,
  tabs and other Unicode spaces), deep causes, titles, accessibility lines, comments, domains in
  any order, arrows with and without labels, a configured `seed` and border amplitude, and the
  render options, `maxWidth` and `idPrefix` among them.
- The whole corpus and every other type's fuzz run, after merging main: identical.
""", nkDone, "Checked"

nbNote """
- Every file is `draft` until a second reading against the TypeScript.
- Mermaid marks both types beta, so their syntax may still change in a later Mermaid; the port
  follows the pin.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Ishikawa and cynefin are done** on the [coverage map](../../coverage/) and the
  [roadmap](../../roadmap/).
- **The porting guide** has a row for JavaScript's bit operators on floats (`|0`, `^`, `>>>`), which convert with ToInt32 first.
- **Next, in this thread:** wardley, architecture, c4 and block.

## Sources

- Pele at the pin: [`src/diagrams/ishikawa/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/ishikawa)
  and [`src/diagrams/cynefin/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/cynefin),
  read in full for this step.
- The ideas: [Ishikawa diagram](https://en.wikipedia.org/wiki/Ishikawa_diagram) and
  [Cynefin framework](https://en.wikipedia.org/wiki/Cynefin_framework) on Wikipedia.
- JavaScript's rules: [ToInt32](https://tc39.es/ecma262/#sec-toint32) and
  [Math.imul](https://tc39.es/ecma262/#sec-math.imul) in the ECMAScript specification.
- The code of this step: [`src/nimaki/diagrams/ishikawa/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/ishikawa),
  [`src/nimaki/diagrams/cynefin/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/cynefin),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
