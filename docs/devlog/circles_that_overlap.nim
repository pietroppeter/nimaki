## devlog: 14 Nov 2026 E | Circles that overlap | nimaki now draws venn diagrams as Pele does, byte for byte, and to get there it learnt to do arithmetic the way Node's engine does, down to the last bit.
## kind: port
import std/[strformat, strutils, json, tables, random]
from std/math as nm import nil
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/jsmath
import nimaki/diagrams/venn/layout

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
for r in difftest["types"]:
  cases[r["type"].getStr] = r["cases"].getInt
let types = difftest["types"].len
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["venn"]

nbText: &"""
## The findings, first

- **One more type.** nimaki draws Mermaid's `venn-beta` identical to Pele, byte for byte, on all
  {cases["venn"]} of the corpus's cases, compiled to C and to JavaScript.
- **And with it, the whole corpus.** venn was the last type of this thread, and sankey and
  quadrant landed today in another: all {types} types now draw identical to Pele's, on
  {difftest["identical"].getInt.thousands} of the corpus's {difftest["cases"].getInt.thousands} cases
  and {difftest["diagrammari"]["identical"].getInt} of diagrammari's {difftest["diagrammari"]["cases"].getInt}.
- **The fuzzer agrees:** {fuzz["cases"].getInt.thousands} generated diagrams,
  {fuzz["identical"].getInt.thousands} identical.
- **The last bit matters here.** A venn layout moves its circles a few hundred times, and a
  difference in the last bit of one length or one cosine can grow into a pixel. Two
  generated diagrams out of thousands came out different: one by 0.4 pixels, one a pixel taller. The cause was not the port but the
  arithmetic: Node computes `Math.hypot`, `sin`, `cos`, `acos`, `atan` and `atan2` with its own
  code, and the C library rounds some results the other way.
- **So the C build now computes them as Node does:** `hypot` as V8, Node's engine, writes it,
  and the five others with a port of fdlibm, the library V8 compiles in. They match Node on
  every one of 200,000 inputs tried.
"""

nbText: """
## What a venn diagram is

A venn diagram draws each *set* as a circle, and things that belong to several sets in the
places where the circles overlap. In Mermaid each `set` is a circle, each `union` names an
overlap, and a number after a colon gives a size: here Alpha holds 20 things, Beta 12, and 3 of
them are in both.
"""

let twoText = """venn-beta
  set A["Alpha"]:20
    text A1["React"]
    text A2["Design Systems"]
  set B["Beta"]:12
  union A,B["AB"]:3
"""

nbText: "```mermaid\n" & twoText & "```"

nbCode:
  let twoSvg = render(twoText).svg
  echo "identical to Pele's: ", twoSvg == peleSvg(twoText)

nbSvg twoSvg, "Two sets with sizes, drawn by nimaki; Pele draws the same bytes."

nbText: """
## From a size to a radius, from an overlap to a distance

Pele makes the *area* of each circle proportional to the size of its set, so a radius is the
square root of the size divided by π. The overlap is harder: how far apart must two circles sit
for the lens they share to have a given area? The lens area has a formula (two slices of the
circles, minus the triangle between their centers), but no formula goes back from the area to
the distance.

What helps is that the lens only shrinks as the circles move apart. So Pele *bisects*: start
with the closest distance (one circle inside the other) and the farthest (just touching), try
the middle, and keep the half where the answer must be. Forty-eight halvings narrow it to far
less than a pixel.
"""

nbCode:
  let ra = sqrt(20 / nm.PI)
  let rb = sqrt(12 / nm.PI)
  let d = distanceForOverlap(ra, rb, 3)
  echo &"radii {ra:.4f} and {rb:.4f}, centers {d:.4f} apart"
  echo &"the lens at that distance: {lensArea(ra, rb, d):.6f}"

nbText: """
Two circles are then placed side by side at that distance. Three make a triangle whose sides
are the three distances: the first two on a line, the third where the law of cosines puts it.
When all three must share a region and the triangle leaves it too small, Pele shrinks the
triangle until there is room for a label.

Four or more sets have no exact answer in general, so Pele *relaxes*: it puts the circles on a
ring, then, for up to 300 rounds, nudges every pair toward its distance (apart, for pairs that
should not overlap) and moves each circle by the average of its nudges. This is the step where a
last bit can grow: every round starts from where the last one left the circles.
"""

let fourText = """venn-beta
  title Four sets
  set A
  set B
  set C
  set D
  union A,B
  union B,C
  union C,D
  union A,D
  union A,C["AC"]
"""

nbText: "```mermaid\n" & fourText & "```"

nbCode:
  let fourSvg = render(fourText).svg
  echo "identical to Pele's: ", fourSvg == peleSvg(fourText)

nbSvg fourSvg, "Four sets, placed by relaxation; the labels sit at the roomiest point of each region."

nbText: """
## Where the words go

A label goes at the point of its region that is farthest from every outline: inside its own
circles, outside the others. Pele samples the smallest circle of the region on a grid, then
walks uphill from the best sample. When the region is all but covered by other circles, the
label is written across them instead. Then the whole picture is scaled, by up to 1.6 times, so
that every label fits its region, and what still does not fit is wrapped.

An overlap is drawn as a shape of its own only when a `style` gives it a look. Its outline is
found from the *corners* where two circles cross inside all the others, joined by arcs.

## The last bit

A floating-point number has 53 bits of precision, and the IEEE 754 standard asks for `+`, `−`,
`×`, `÷` and `sqrt` to be rounded correctly: every computer gives the same bits. It does not ask
that of `sin`, `cos` or `hypot`, and libraries differ. The C library that Nim calls and V8, the
engine inside Node, agree almost always, and otherwise disagree in the last bit or two. Here is how
often `hypot`, the length of a vector, differs between them on seeded random inputs:
"""

nbCode:
  var r = initRand(1)
  var differ = 0
  var most = 0'i64
  const tries = 10_000
  for i in 0 ..< tries:
    let x = r.rand(-500.0 .. 500.0)
    let y = r.rand(-500.0 .. 500.0)
    let (v8, c) = (jsmath.hypot(x, y), nm.hypot(x, y))
    if v8 != c:
      inc differ
      # Two positive floats one step apart have bit patterns one apart as integers.
      most = max(most, abs(cast[int64](v8) - cast[int64](c)))
  echo &"{differ} of {tries} differ, by at most {most} steps of the last bit"

nbText: """
`jsmath.hypot` is V8's version, now part of nimaki; `nm.hypot` is the C library's. V8 divides
both numbers by the larger one, then adds their squares with *Kahan summation*, which carries
along the rounding error of each addition and adds it back. The C library uses another method
of the same accuracy, which rounds differently.

For `sin`, `cos`, `acos`, `atan` and `atan2`, V8 compiles fdlibm, the *freely distributable
math library* that Sun Microsystems wrote in 1993. To compute a sine, fdlibm first subtracts
the nearest multiple of π/2, in three pieces of π/2 so that no precision is lost, and then
evaluates a short polynomial whose coefficients were fitted to the sine on the remaining
quarter turn. nimaki's `fdlibm.nim` is a line-by-line port of those functions, with Sun's
notice kept.
"""

nbNote """
- A difference that small almost never shows: nimaki writes coordinates with two decimals, so a
  difference has to grow by a factor of about 10¹² to reach the SVG. A relaxation of 300 rounds
  can do that, because a circle that ends up a hair to one side changes which pairs still push.
  Of the two cases the fuzzer found, one moved a point by 0.4 pixels, and the other came out
  366 pixels tall where Pele's is 367.
- The JavaScript build of nimaki keeps calling JavaScript's own `Math`, which is already V8's.
""", nkPele, "Why a venn, and not a pie"

nbNote """
- Seven files under `src/nimaki/diagrams/venn/`, one per TypeScript file. A circle is a `ref
  object`, because the layout moves the circles it returns, and the outline code tells two
  circles apart by identity, which `==` on refs gives in C and in JavaScript.
- `src/nimaki/jsmath.nim` routes the six functions, in the C build only, to V8's versions:
  `hypot` there, the others in the new `src/nimaki/fdlibm.nim`. The long argument reduction of
  fdlibm, for angles past 2¹⁹·π/2, is not ported: those fall back to the C library, and no
  diagram turns that far.
- `NOTICE` now lists V8's licence (BSD 3-Clause) and fdlibm's notice.
""", nkNim, "In the port"

nbNote &"""
- `difftest venn`: {cases["venn"]} of {cases["venn"]} identical, also with `--js`. The whole
  corpus is still identical, `--check-done` passes.
- `fuzz venn`: {fuzz["cases"].getInt.thousands} cases of seed 1; seeds 2 and 3, 3,000 each, run
  by hand; 1,000 with `--js`. All identical. CI runs seed 1 on every pull request.
- fdlibm and `hypot` against Node's `Math`: 200,000 seeded inputs (small, medium, up to a
  million, and near zero), all identical bit for bit. Checked with a script for this step, not
  on this page.
- Since every type that draws curves or angles calls these functions, the fuzzer was rerun for
  them (pie, radar, wardley, block, flowchart, state, class, architecture, er, c4, swimlane,
  mindmap), 800 cases each: all identical.
""", nkDone, "Checked"

nbText: """
## What this changes for the port

- **venn is done**, on the [roadmap](../../roadmap/) and the [coverage map](../../coverage/),
  and with it every diagram type of Pele 1.13.0 has a port that draws the same bytes.
- **The math functions are V8's** in the C build: the porting guide's note on them says so.
- **Next in this thread:** the proposal for diagrammari.

## Sources

- Pele at the pin: [`src/diagrams/venn/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/venn),
  read for this step.
- V8 as Node 22 bundles it: [`deps/v8/src/base/ieee754.cc`](https://github.com/nodejs/node/blob/v22.x/deps/v8/src/base/ieee754.cc)
  (fdlibm) and [`deps/v8/src/builtins/math.tq`](https://github.com/nodejs/node/blob/v22.x/deps/v8/src/builtins/math.tq)
  (`MathHypot`), read for this step.
- fdlibm: [netlib.org/fdlibm](https://www.netlib.org/fdlibm/); not read for this step beyond
  the copy in V8.
- Kahan summation: W. Kahan, *Further remarks on reducing truncation errors*, Communications of
  the ACM 8 (1), 1965; not read for this step, named for the method V8's code follows.
- The code of this step: [`src/nimaki/diagrams/venn/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/venn),
  [`src/nimaki/fdlibm.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/fdlibm.nim),
  [`src/nimaki/jsmath.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/jsmath.nim).
"""

nbSave
