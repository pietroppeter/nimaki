## devlog: 12 Nov 2026 H | How Pele is built | A tour of the 52,973 lines we are about to port: the path a diagram takes, what each part does, how big it is, and where its decisions come from.
## kind: research
import std/[algorithm, json, math, os, sequtils, strformat, strutils, tables, unicode]
import nimib
import tabelline, tabelline/nimib
import ../blocks

nbInit
nb.usePost()

const dataDir = currentSourcePath.parentDir / "data" / "how_pele_is_built"
let
  measured = parseJson(readFile(dataDir / "components.json"))
  history = parseJson(readFile(dataDir / "history.json"))
  traps = parseJson(readFile(dataDir / "traps" / "results.json"))
  # the coverage map counts lines of code (not blank, not only a comment), by tools/coverage_seed.nim
  coverage = parseJson(readFile(currentSourcePath.parentDir.parentDir / "data" / "coverage.json"))
  pin = measured["pin"]

proc thousands(n: int): string = insertSep($n, ',')

proc typesWhere(pred: proc (t: JsonNode): bool): seq[JsonNode] =
  measured["types"].elems.filterIt(pred(it))

proc lines(rows: seq[JsonNode]): int = rows.mapIt(it["lines"].getInt).foldl(a + b, 0)

proc corePart(part: string): int =
  measured["core"].elems.filterIt(it["part"].getStr == part).lines

proc roleTotal(role: string): int =
  for t in measured["types"]: result += t["roles"][role].getInt

let
  types = typesWhere(proc (t: JsonNode): bool = t["type"].getStr != "common")
  common = typesWhere(proc (t: JsonNode): bool = t["type"].getStr == "common")[0]
  diagramLines = measured["types"].elems.lines
  coreLines = measured["core"].elems.lines
  total = diagramLines + coreLines
  parseShare = roleTotal("parse") / diagramLines
  family = proc (name: string): seq[JsonNode] = types.filterIt(it["parser"].getStr == name)
  usesLayout = types.filterIt(it["uses"].elems.anyIt(it.getStr.startsWith("layout/")))
  ownLayout = types.filterIt(it["roles"]["layout"].getInt > 0)
  releases = history["releases"].elems
  coverageCode = coverage["core"].elems.mapIt(it["code"].getInt).foldl(a + b, 0) +
                 coverage["diagrams"].elems.mapIt(it["code"].getInt).foldl(a + b, 0)
  codeOf = proc (name: string): int =
    for d in coverage["diagrams"]:
      if d["id"].getStr == name: return d["code"].getInt
  firstRelease = releases[0]
  lastRelease = releases[^1]

nbText: fmt"""
## The short version

- We port **Pele {pin["tag"].getStr}** (commit `{pin["commit"].getStr[0 .. 6]}`, {pin["date"].getStr}).
  Its `src/` is {thousands(total)} lines of TypeScript: {thousands(diagramLines)} in the
  {types.len} diagram types and their shared helpers, {thousands(coreLines)} in the core that
  every type uses. Without blank lines and comments, as the
  [coverage map](../../coverage/) counts, it is {thousands(coverageCode)} lines of code.
- Every diagram type is a **small pipeline of its own**: a parser turns text into a model, and a
  renderer turns the model into an SVG string. In between, a few types call one of the shared
  graph layouts; most place their boxes with plain geometry.
- **Parsing is most of the code.** {int(parseShare * 100)}% of the lines in the diagram folders
  are lexers, parsers and the models they fill. Pele reproduces Mermaid's grammars by hand, quirks
  included, and the ported Mermaid specs check that it does.
- The hard part for the port is not the size but the **arithmetic of JavaScript**. A byte for
  byte match depends on rounding, number printing, string lengths and `Math.sin` behaving
  exactly as in V8. We measured where Nim differs (most of it is easy to match).
- Pele grew from {thousands(firstRelease["src"].getInt)} to {thousands(lastRelease["src"].getInt)}
  lines in {releases.len} releases between {firstRelease["date"].getStr} and
  {lastRelease["date"].getStr}. The shared layout more than doubled in that month: it is the part
  that moves most.

## Rendering a diagram, in one page

A renderer like Pele is a function from text to text. Mermaid text goes in, an SVG document comes
out, and nothing else is touched: no browser, no files, no clock (except one, see *gantt* below).
Inside, it is a relay race, like a compiler:
"""

block:
  type Row = object
    stage, takes, gives, where: string
  let rows = @[
    Row(stage: "Preprocess", takes: "the text", gives: "the text without front matter, directives and comments; a config",
        where: "`preprocess.ts`, `util/yaml.ts`"),
    Row(stage: "Detect", takes: "the first word", gives: "which diagram type this is",
        where: "`detect.ts`"),
    Row(stage: "Parse", takes: "the text", gives: "a model: nodes, edges, slices, messages...",
        where: "`diagrams/<type>/lexer, parser, db`"),
    Row(stage: "Measure", takes: "every label", gives: "its width and height in pixels",
        where: "`text/measurer.ts`, `text/label.ts`"),
    Row(stage: "Lay out", takes: "the model and the label sizes", gives: "a position for every box and a route for every line",
        where: "`layout/`, or `render.ts` of the type"),
    Row(stage: "Write", takes: "the positions", gives: "the SVG string",
        where: "`svg/`, `render.ts` of the type"),
  ]
  let t = tabella(rows, rownameCol = "stage"):
    tabHeader "The relay race", "what each stage takes, gives, and where it lives in Pele"
    fmtMarkdown ["where"]
    optCssTheme()
  nbTable t

nbText: """
The companion post *Drawing a diagram from scratch* builds a toy renderer with exactly these
stages, in a few hundred lines of Nim, and explains each one for someone who has never written a
parser or a layout engine. This post is the map of the real thing.

## The path of one diagram

Everything starts in `render()` (`src/core.ts`, 195 lines). Here is what happens to the pie chart
from Mermaid's documentation:

```
pie title Pets adopted by volunteers
    "Dogs" : 386
    "Cats" : 85
    "Rats" : 15
```

1. **Limits.** A source longer than 50,000 characters (Mermaid's own `maxTextSize`) is refused
   before anything else. Characters here are UTF-16 code units, as `text.length` counts them.
2. **Preprocess.** Line breaks become `\n`; a `---` front matter block is read with Pele's own
   small YAML reader (`util/yaml.ts`, 470 lines); `%%{init: ...}%%` directives are merged into the
   config; `%%` comment lines go. What is left is the diagram proper.
3. **Detect.** A list of 37 regular expressions, *in the order Mermaid registers its
   detectors*, is tried against the start of the text; the first match wins. `pie` matches
   `/^\s*pie/`.
4. **Look up** the type in a registry. A program that only needs a few types registers only those
   (`pele/core` plus one entry per type), which keeps a browser bundle small.
5. **Encode entities** (`#quot;` and friends are hidden behind placeholder characters, as Mermaid
   does, so that `#` and `;` survive parsing), and add a final newline: Mermaid's grammars expect
   one.
6. **Parse.** The type's parser returns its model. For the pie it is a title, a `showData` flag
   and a map from label to value, in the order written.
7. **Render**, inside three small contexts: the colour palette of the type, the math typesetter
   and the icon resolver the host gave, if any. They are module-level variables set for the
   duration of the call (`withPalette`, `withMath`, `withIcons`), a pattern that ports to Nim as a
   global set and restored in a `try`/`finally`.
8. **Check the output.** An SVG over 4,000,000 characters is refused too: a short text can ask
   for an enormous drawing.

The result is `{ svg, width, height, links }`. The SVG is a single string.
"""

nbNote("""Every error the user can cause is a `PeleError` with a code (`syntax`, `semantic`,
`limit`, `unsupported-diagram`). A JavaScript `RangeError` (stack overflow from deep nesting) is
caught and turned into a `limit` error. In Nim, deep recursion crashes the process instead of
raising, so the port needs explicit depth counters where Pele relies on the stack.""", nkNim,
  "Errors, and one difference")

nbText: fmt"""
## The core: {thousands(coreLines)} lines every type shares
"""

block:
  const roles = {
    "layout/layered.ts": "Layered (Sugiyama) layout of a flat graph: ranks, crossings, positions, edge routes",
    "layout/compound.ts": "Graphs with groups (subgraphs): lays out each group, then the groups",
    "layout/lanes.ts": "Swimlanes: every top-level group is a band along the flow",
    "layout/components.ts": "Wraps disconnected parts of a graph into rows (class diagrams)",
    "svg/builder.ts": "`num()`, escaping, and writing a measured label as `<text>`",
    "svg/shapes.ts": "The node shapes: rectangles, diamonds, cylinders, and dozens more",
    "svg/edges.ts": "Turns an edge route into a path with curves and arrowheads",
    "svg/theme.ts": "The CSS custom properties (`--pele-*`) every colour and font goes through",
    "svg/palette.ts": "Series colours for charts, from Mermaid's `themeVariables`",
    "svg/ink.ts": "Picks a readable text colour on a filled shape",
    "svg/root.ts": "The `<svg>` element, its style and its accessible title",
    "text/label.ts": "Reads label markup (`<b>`, `<br>`, Markdown emphasis) and wraps lines",
    "text/measurer.ts": "How wide a text is, from a table of font metrics",
    "text/metrics.ts": "That table: Arial's widths for printable ASCII, packed",
    "text/entities.ts": "HTML entity codes",
    "util/yaml.ts": "The YAML subset front matter uses",
    "util/url.ts": "Which links and image addresses are safe to write",
    "preprocess.ts": "Front matter, directives, comments, entity placeholders",
    "detect.ts": "Which diagram type a text is",
    "core.ts": "`parse()` and `render()`",
    "mount.ts": "Browser only: renders into an element and redraws on resize",
    "zoom.ts": "Browser only: pan and zoom",
  }.toTable
  type Row = object
    file: string
    lines: int
    does: string
  var rows: seq[Row]
  for c in measured["core"]:
    let file = c["file"].getStr.replace("src/", "")
    rows.add Row(file: "`" & file & "`", lines: c["lines"].getInt, does: roles.getOrDefault(file, ""))
  rows.sort(proc (a, b: Row): int = cmp(b.lines, a.lines))
  let t = tabella(rows, rownameCol = "file"):
    tabHeader "The core, largest first", "measured at the pin by measure.nim"
    fmtInteger ["lines"]
    fmtMarkdown ["file", "does"]
    optCssTheme()
  nbFold "The core file by file":
    nbTable t

nbText: fmt"""
By part: **layout** {thousands(corePart("layout"))} lines, **svg** {thousands(corePart("svg"))},
**text** {thousands(corePart("text"))}, **util** {thousands(corePart("util"))}, and
{thousands(corePart("top"))} in the top-level files (of which `mount.ts` and `zoom.ts`, {thousands(
measured["core"].elems.filterIt(it["file"].getStr in ["src/mount.ts", "src/zoom.ts"]).lines)} lines,
only make sense in a browser and are not part of the port of the renderer).

### Measuring text without a browser

A layout needs the size of every label before it can place anything, and the size of a text
depends on the font. Mermaid asks the browser: it puts the text in the page and reads its width.
Pele cannot, since it runs without a DOM. In a browser it uses a canvas when there is one; in Node,
and in its own tests, it uses `metricsMeasurer`: a table of how wide each printable ASCII character
is in Arial, in thousandths of an em, packed as two base-36 digits per character. Everything
outside ASCII is guessed: 1 em for CJK and other wide scripts, 0.58 em for the rest, nothing for
combining marks.

This is the measurer the referee uses, so it is the first thing to port. Here it is in Nim,
complete:
"""

nbCode:
  # port-of: src/text/measurer.ts (metricsMeasurer) and src/text/metrics.ts. Pele, MIT, (c) kepano.
  const
    Regular = "7q7q9vfgfgopij5b9999atg87q997q7qfgfgfgfgfgfgfgfgfgfg7q7qg8g8g8fgs7ijijk2k2ijgzlmk27qdwijfgn5k2lmijlmk2ijgzk2ijq8ijijgz7q7q7qd1fg99fgfgdwfgfg7qfgfg6666dw66n5fgfgfgfg99dw7qfgdwk2dwdwdw9a789ag8"
    styleBold = 1
    styleMono = 4

  proc base36(c: char): int =
    if c in '0'..'9': ord(c) - ord('0') else: ord(c) - ord('a') + 10

  proc unpack(packed: string): seq[int] =
    ## Two base-36 digits per character, from ' ' (32) to '~' (126).
    for i in 0 ..< 95: result.add base36(packed[2*i]) * 36 + base36(packed[2*i + 1])

  let regular = unpack(Regular)

  iterator utf16(text: string): int =
    ## JavaScript strings are UTF-16: a character outside the first 65,536 is two code units.
    for r in text.runes:
      let c = int(r)
      if c < 0x10000: yield c
      else:
        yield 0xD800 + ((c - 0x10000) shr 10)
        yield 0xDC00 + ((c - 0x10000) and 0x3FF)

  proc isWide(c: int): bool =
    c in 0x1100..0x115f or c in 0x2e80..0xa4cf or c in 0xac00..0xd7a3 or c in 0xf900..0xfaff or
      c in 0xfe30..0xfe4f or c in 0xff00..0xff60 or c in 0xffe0..0xffe6 or c in 0xd800..0xdbff

  proc isZeroWidth(c: int): bool =
    c == 0xad or c in 0x300..0x36f or c in 0x200b..0x200f or c in 0xdc00..0xdfff or
      c in 0xfe00..0xfe0f or c == 0xfeff

  proc width(text: string, size: float, style = 0): float =
    let mono = (style and styleMono) != 0
    var units = 0
    for c in utf16(text):
      if c < 32: continue
      if c < 127: units += (if mono: 600 else: regular[c - 32])
      elif isZeroWidth(c): continue
      elif isWide(c): units += (if mono: 1200 else: 1000)
      else: units += (if mono: 600 else: 580)
    units.float * size / 1000

  for text in ["Dogs", "Pets adopted by volunteers", "iiii", "WWWW", "火山", "🌋"]:
    echo text.alignLeft(28), width(text, 16).formatFloat(ffDecimal, 3), " px"

nbText: """
The bold table and the sub- and superscript sizes are left out here, and so is one detail worth
noticing: the volcano emoji is one character for a person, two code units for JavaScript, and Pele
counts the first as wide (1 em) and the second as nothing. The port has to count the same way,
which is why `utf16` above exists. That is the first trap of the port, and there are more.

### Writing SVG

There is no SVG library. Each renderer builds its document as a string, with template literals:
`<rect x="${num(x)}" .../>`. Three things keep that safe and stable:

- **Every coordinate goes through `num()`** (`svg/builder.ts`): rounded to hundredths, no trailing
  zeros, `0` for anything that rounds to zero (so no `-0`). It builds the string from integers,
  which is fast and, for us, easy to match.
- **Every text goes through `esc()`** (`&`, `<`, `>`, `"`, and characters XML does not allow are
  dropped), and every value that came from the user (a colour, a style, a link) is checked before
  it is written. Pele's security page lists what it guarantees; the port inherits those
  guarantees only if it matches byte for byte, which is one more reason for the referee.
- **No colour is written as a colour.** Fills and strokes are CSS custom properties with a
  default, `fill="var(--_s)"`, and the root element maps the short private names to public ones:
  `--_s:var(--pele-surface,#f3f3f3)`. A page themes every diagram by setting `--pele-*`
  variables, with no need to render again. This is how Obsidian makes diagrams follow its themes.
"""

nbCode:
  # port-of: src/svg/builder.ts (num). Pele, MIT, (c) kepano.
  proc jsRound(x: float): float =
    ## Math.round: the nearest integer, and a tie goes up (toward +infinity).
    result = floor(x)
    if x - result >= 0.5: result += 1

  proc num(value: float): string =
    let n = jsRound(value * 100)
    if n == 0: return "0"
    let m = abs(n)
    let q = int(floor(m / 100))
    let f = int(m - float(q) * 100)
    result = (if n < 0: "-" else: "") & $q
    if f != 0:
      result.add(if f mod 10 == 0: "." & $(f div 10) else: "." & ($f).align(2, '0'))

  for v in [0.0, -0.004, 12.5, 12.345, -12.345, 1/3, 120.0, -0.005]:
    echo ($v).alignLeft(22), num(v)

nbText: fmt"""
The last two lines show why `jsRound` is not Nim's `round`: JavaScript sends a tie up, Nim sends it
away from zero, so `-0.005` becomes `0` in one and `-0.01` in the other. (The full `num()` also has
a branch for numbers past 10⁹, written with JavaScript's own number printing.)

### Three layouts, used by {usesLayout.len} types

The shared layouts are graph layouts: they take boxes (with sizes) and arrows between them, and
return a position for every box and a route for every arrow. All three are Pele's own; it uses
neither dagre nor ELK.

- **Layered** (`layout/layered.ts`, the largest file of the project) is a Sugiyama-style layout,
  the classic way to draw a flowchart: break cycles, put every node on a rank (a row), cut long
  arrows into one piece per rank, reorder each row to remove crossings, give every node an x
  (Brandes and Köpf's method), then route the edges. Its header lists eight aims, in order of
  priority, from *lines can be told apart* to *the drawing stays compact*, and names the function
  that carries out each one. It is the best piece of documentation in the code base.
- **Compound** (`layout/compound.ts`) handles groups, Mermaid's subgraphs: it lays out the inside
  of each group with the layered layout, then treats each group as one box at the level above,
  and routes the edges that cross a group's border through ports.
- **Lanes** (`layout/lanes.ts`) is for swimlanes: ranks shared by every lane, each node kept
  inside its own lane.

Which types use them, from their imports:
"""

block:
  type Row = object
    `type`: string
    lines: int
    shared: string
  var rows: seq[Row]
  for t in usesLayout:
    rows.add Row(`type`: t["type"].getStr, lines: t["lines"].getInt,
                 shared: t["uses"].elems.mapIt(it.getStr).filterIt(it.startsWith("layout/")).mapIt("`" & it & "`").join(", "))
  let t = tabella(rows, rownameCol = "type"):
    tabHeader "The types on the shared layouts", "every other type places its shapes itself"
    colsLabel {"lines": "type lines", "shared": "layout modules imported"}
    fmtInteger ["lines"]
    fmtMarkdown ["shared"]
    optCssTheme()
  nbTable t

nbText: fmt"""
Every other type places its shapes with geometry written for it: the angles of a pie, the bars of
a gantt chart, the columns of a sequence diagram. {ownLayout.len} of them have a file of their own
for it ({ownLayout.mapIt("*" & it["type"].getStr & "*").join(", ")}, in `layout.ts` or
`route.ts`); the rest do it inside `render.ts`.

## The {types.len} diagram types
"""

nbText: fmt"""
Each type lives in `src/diagrams/<type>/` with the same cast of files: `index.ts` (the glue that
registers it), a `parser.ts`, often a `lexer.ts` and `tokens.ts`, a `db.ts` or `model.ts` (what
the parser fills), sometimes a `layout.ts`, and a `render.ts`. `measure.nim` sorts the files into
three roles by name (*parse*, *layout*, *render*), which is rough (a `render.ts` often lays out
too) but shows where the weight is.

The types come from two families of grammars, because Mermaid has two:

- **Jison** ({family("jison").len} types, {thousands(family("jison").lines)} lines). Mermaid's
  older diagrams are written in Jison, a JavaScript port of Bison: a lexer with *start
  conditions* (modes: inside a string, inside an edge label...) and an LR grammar. Pele rewrites
  each lexer by hand as a state machine (`lexer.ts`, the flowchart one has 18 states) and each
  grammar as a hand-written recursive descent parser.
- **Langium** ({family("langium").len} types, {thousands(family("langium").lines)} lines).
  Mermaid's newer diagrams use Langium, whose lexer is Chevrotain: an ordered list of token
  patterns where the first match wins. Pele has one shared tokenizer for these
  (`diagrams/common/tokens.ts`) that reproduces Chevrotain's rules, and each type gives it its
  token table.
- **Neither** ({family("own").len} types: {family("own").mapIt(it["type"].getStr).join(", ")}).
  Mindmap and kanban are read by indentation (a shared outline reader in `common/`); swimlane is
  a flowchart with lanes and borrows the flowchart parser.

The folder `diagrams/common/` ({thousands(common["lines"].getInt)} lines) holds what the types
share: the Langium tokenizer, label fitting, accessibility fields.
"""

block:
  type Row = object
    `type`: string
    lines, code, parse, layout, render, tests, examples: int
    parser: string
  var rows: seq[Row]
  for t in types:
    rows.add Row(`type`: t["type"].getStr, lines: t["lines"].getInt, code: codeOf(t["type"].getStr),
                 parse: t["roles"]["parse"].getInt, layout: t["roles"]["layout"].getInt,
                 render: t["roles"]["render"].getInt + t["roles"]["entry"].getInt,
                 parser: t["parser"].getStr, tests: t["testLines"].getInt,
                 examples: t["docExamples"].getInt)
  let t = tabella(rows, rownameCol = "type"):
    tabHeader "Every diagram type, largest first", "all lines, lines of code (from the coverage map), and all lines by role; tests are Pele's own and the ported Mermaid specs"
    colsLabel {"code": "of code", "render": "render & glue", "tests": "test lines", "examples": "doc examples"}
    fmtInteger ["lines", "code", "parse", "layout", "render", "tests", "examples"]
    optCssTheme()
  nbTable t

nbText: """
A few things stand out:

- **The biggest types are not the famous ones.** Agentflow and use case outweigh the flowchart,
  because their grammars are large. The flowchart's weight is in the shared
  layout, which this table does not count.
- **The smallest types are small**: pie, packet, mindmap, kanban, info are each under 400 lines.
  Pie is the right first step: it touches the whole core (text, theme, SVG, the Langium tokenizer,
  `num()`) with almost no type-specific logic.
- **Tests are as big as the code.** Every type has the Mermaid parser specs ported to it
  (`tests/compat/<type>/`, with a `SKIPPED.md` saying which cases are left out and why), render
  tests and, for many types, an *oracle*: Mermaid's own grammar (the flowchart's `flow.jison`,
  vendored in the tests and run with the `jison` package), fed the same fuzzed input as Pele's
  parser, with the two results compared. Pele's render tests check properties (*one slice per
  section*), not whole SVG files: there are no SVG snapshots to replay, so our referee is Pele
  itself, run in Node.

## Where Pele's decisions come from

Pele's choices are written down in four places, and the port should read all four.

1. **Mermaid, for the syntax.** What Pele accepts is what Mermaid 12.1.0 accepts: same detectors
   in the same order, same token rules, same quirks. The gantt chart even carries a reimplementation
   of the parts of dayjs Mermaid uses, *"quirks are kept, because a date is accepted only when
   formatting the parsed result gives back the input"*. Where Pele differs on purpose, the
   compatibility page of pele.run says so.
2. **Obsidian, for everything around the syntax.** It has to be fast, synchronous and safe on
   text from anyone: limits on input, output and edges, no HTML in labels, links checked against
   a list of schemes, nothing executed. It has to follow the app's theme: hence CSS variables. It
   has to work offline and inside a worker: hence no DOM and no dependencies.
3. **Its own taste, for the drawing.** Pele does not try to look like Mermaid. Its layout and
   its style are its own, and its rules for them are in comments: the eight aims of the layered
   layout, and, by Pele's `AGENTS.md`, a comment for every *non-obvious decision, intentional
   difference from Mermaid, and preserved quirk*. Comments are the decision log.
4. **The git history.** The public repository starts on 5 October 2026 with a day that rebuilds
   the whole project in order (the flowchart parser and its spec suite first, then the layout
   engine, then a registry, then pie, then the other types in an evening), and then a month of
   small commits with an area in their subject: `Layout: ...`, `Sequence: ...`.
"""

block:
  type Row = object
    area: string
    commits: int
  var rows: seq[Row]
  for a in history["areas"]:
    if rows.len < 12 and a["area"].getStr != "(none)":
      rows.add Row(area: a["area"].getStr, commits: a["commits"].getInt)
  let none = history["areas"].elems.filterIt(it["area"].getStr == "(none)")[0]["commits"].getInt
  let t = tabella(rows, rownameCol = "area"):
    tabHeader "Where the commits went", fmt"""the twelve busiest areas of {history["commits"].getInt} commits ({none} name no area)"""
    fmtInteger ["commits"]
    optCssTheme()
  nbTable t

block:
  type Row = object
    release, date: string
    src, layout: int
  var rows: seq[Row]
  for r in releases:
    rows.add Row(release: r["tag"].getStr, date: r["date"].getStr, src: r["src"].getInt, layout: r["layout"].getInt)
  let t = tabella(rows, rownameCol = "release"):
    tabHeader "Lines at every release", "the whole of src/, and the shared layout"
    colsLabel {"src": "src lines", "layout": "layout lines"}
    fmtInteger ["src", "layout"]
    optCssTheme()
  nbFold "Pele's size at each of its releases":
    nbTable t

nbText: fmt"""
The layout is where Pele moves: {thousands(firstRelease["layout"].getInt)} lines at
{firstRelease["tag"].getStr}, {thousands(lastRelease["layout"].getInt)} at
{lastRelease["tag"].getStr}, and the busiest area of the history. A Pele release mostly changes
how diagrams are drawn, not what they accept. For the port, this means the layout is the part to
port carefully and to keep in sync with the most care.

## The traps of a port from TypeScript

The referee compares bytes. Anything that JavaScript and Nim compute differently, by even one
unit in the last place, can show. We counted the constructs that need care, and measured Nim
against V8 (Node {traps["node"].getStr}) on the number operations Pele uses.
"""

block:
  type Row = object
    asked, js, nim: string
  var js = initTable[string, string]()
  for c in traps["cases"]["toFixed0"]:
    if c[0].getFloat == 12.5: js["toFixed"] = c[1].getStr
  for c in traps["cases"]["round"]:
    if c[0].getFloat == -2.5: js["round"] = $c[1]
  for c in traps["cases"]["string"]:
    if c[0].getFloat == 1e-7: js["tiny"] = c[1].getStr
    if c[0].getFloat == 1.0: js["one"] = c[1].getStr
  for c in traps["cases"]["utf16"]:
    if c[0].getStr == "😀": js["len"] = $c[1]
  js["max"] = traps["cases"]["maxNaN"][0][2].getStr
  let rows = @[
    Row(asked: "12.5 to no decimals", js: js["toFixed"], nim: formatFloat(12.5, ffDecimal, 0)),
    Row(asked: "round −2.5", js: js["round"], nim: $round(-2.5)),
    Row(asked: "print 1e-7", js: js["tiny"], nim: $1e-7),
    Row(asked: "print 1.0", js: js["one"], nim: $1.0),
    Row(asked: "length of 😀", js: js["len"], nim: $"😀".len),
    Row(asked: "max of 1 and NaN", js: js["max"], nim: $max(1.0, NaN)),
  ]
  let t = tabella(rows, rownameCol = "asked"):
    tabHeader "Same question, two answers", "JavaScript recorded from Node by traps/v8.mjs; Nim computed as this page is built"
    colsLabel {"js": "JavaScript", "nim": "Nim"}
    optCssTheme()
  nbTable t

nbText: """
What each row means for the port:

- **`toFixed`** (pie writes every percentage with it): JavaScript uses the exact decimal value and
  sends a tie up; Nim's `formatFloat` follows C's `printf`, which sends a tie to the even digit and
  keeps the dot. The port needs its own `toFixed`.
- **`Math.round`** (133 uses): a tie goes toward +∞ in JavaScript, away from zero in Nim:
  `jsRound`, as above.
- **Printing a number**: every `${x}` of a number in a template literal uses ECMAScript's
  Number::toString (shortest round trip, no `.0`, its own exponent rules). The port needs a
  `jsString(float)`.
- **UTF-16**: `'😀'.length` counts UTF-16 code units, Nim's `len` counts bytes. Limits, the
  measurer and error offsets count the JavaScript way.
- **`Math.max` and `Math.min`** return NaN if any argument is NaN; Nim's `max` does not. Pele's
  layout uses NaN for *unknown*, so `jsMax` and `jsMin` where NaN can reach them.
"""

block:
  type Row = object
    function: string
    inputs, differ, shows: int
  var rows: seq[Row]
  for r in traps["libm"]:
    rows.add Row(function: "`Math." & r["function"].getStr & "`", inputs: r["inputs"].getInt,
                 differ: r["differ"].getInt, shows: r["showsInSvg"].getInt)
  let t = tabella(rows, rownameCol = "function"):
    tabHeader "Nim's math library against V8's", "seeded random inputs; differ: not the same bits; shows: still different after scaling to a 120 px radius and rounding to hundredths, as num() writes it"
    colsLabel {"differ": "differ", "shows": "shows in SVG"}
    fmtInteger ["inputs", "differ", "shows"]
    fmtMarkdown ["function"]
    optCssTheme()
  nbTable t

nbText: """
V8 computes `sin`, `cos`, `atan2`, `pow` and `log10` with its own port of fdlibm, and `hypot` with
an algorithm of its own; Nim calls the C library. They agree to the last bit most of the time, and
after rounding to hundredths we saw no difference at all. But a difference of one bit can still
flip a comparison inside the layout (*is this edge longer than that one?*), so the safe plan is a
small `jsmath` module: Nim's functions to begin with, and a port of V8's, bit for bit, the moment
the difftest finds a case they decide. `sqrt` is exact in both, by the IEEE standard.
"""

block:
  type Row = object
    trap: string
    count: int
    note: string
  var counts = initTable[string, int]()
  for t in measured["types"]:
    for k, v in t["traps"]: counts[k] = counts.getOrDefault(k) + v.getInt
  for c in measured["core"]:
    for k, v in c["traps"]: counts[k] = counts.getOrDefault(k) + v.getInt
  let rows = @[
    Row(trap: "regular expression literals", count: counts["regex"],
        note: "Lookahead is used, lookbehind never; `\\s` and `.trim()` include Unicode spaces in JavaScript, not in Nim. Scanners by hand where Pele already avoided a regex for speed; nim-regex for the rest (not PCRE)."),
    Row(trap: "sticky regular expressions (`/y`)", count: counts["sticky"],
        note: "A match anchored at a position: the token tables. nim-regex's `matchAt`-style calls, or the scanner."),
    Row(trap: "UTF-16 code unit access", count: counts["utf16"],
        note: "`charCodeAt` mostly compares with ASCII, which is the same byte in UTF-8; the rest needs the UTF-16 view."),
    Row(trap: "number to text and back", count: counts["numberText"],
        note: "`toFixed`, `toPrecision`, `parseFloat`, `Number()`: each with JavaScript's exact rules."),
    Row(trap: "`Math.round`", count: counts["round"], note: "`jsRound`."),
    Row(trap: "libm calls", count: counts["libm"], note: "`jsmath`."),
    Row(trap: "sorts", count: counts["sort"],
        note: "JavaScript's sort is stable, and so is Nim's `algorithm.sort` (a merge sort). Keep the same comparator, including its tie-breaks."),
    Row(trap: "dates", count: counts["date"],
        note: "Only the gantt chart. Pele computes in *local time*: the referee runs with `TZ=UTC` and a fixed `now`."),
  ]
  let t = tabella(rows, rownameCol = "trap"):
    tabHeader "Constructs that need care, counted in src/", "by measure.nim; the regex count comes from a small scanner, not a JavaScript parser, so take it as a size, not a census"
    fmtInteger ["count"]
    fmtMarkdown ["trap", "note"]
    optCssTheme()
  nbTable t

nbText: """
Three more, which do not count well but matter:

- **Maps keep insertion order** in JavaScript, and Pele iterates them (`new Map`, 253 times; `new
  Set`, 71). Nim's `Table` does not keep order: the port uses `OrderedTable` and `OrderedSet`
  wherever Pele iterates.
- **Integers are floats.** A JavaScript number is a 64-bit float, even as an array index. Pele's
  layout uses typed arrays (`Int32Array`, `Float64Array`, `Uint8Array`, about 370 uses) for speed,
  which port naturally to `seq[int32]`, `seq[float]`, `seq[uint8]`; `>>> 0` and `Math.imul` (the
  seeded random numbers) need 32-bit unsigned arithmetic.
- **Module state.** `withPalette` and its siblings are module globals set around a call, and
  caches such as the unpacked metrics tables are built on first use. Fine in Nim, but not if the
  port is ever called from two threads at once.
"""

nbText: fmt"""
## What this changes for the port

- **The order of the work.** Core first, the way Pele itself was built after its layout: the
  measurer, `num()` and escaping, the theme and `<svg>` root, preprocess and detect, the Langium
  tokenizer. Then **pie** ({types.filterIt(it["type"].getStr == "pie")[0]["lines"].getInt} lines),
  which uses all of them and nothing else. Then the **flowchart**, which brings the Jison-style
  lexer and the layered and compound layouts. With these, {usesLayout.len - 1} more types have their
  layout ready. Then the rest, smallest first. The [roadmap](../../roadmap/) already has this
  order; two notes for it: the Langium tokenizer (`diagrams/common/`) belongs with the core, since
  pie needs it, and swimlane, first of phase 3 by size, needs the lane layout, which no earlier
  type uses.
- **A JavaScript-semantics module before any diagram**: `jsRound`, `toFixed`, `jsString(float)`,
  `parseFloat`/`Number()`, `jsMax`/`jsMin`, UTF-16 length and code units, and `jsmath`. Each one
  is tested against values recorded from Node, like the table above.
- **The referee's settings**: `metricsMeasurer` (Node has no canvas, so Pele uses it there anyway),
  `TZ=UTC`, a fixed `now` for gantt, and the corpus Pele's own tests use: every diagram string in
  the ported specs plus `tests/corpus/*.json` ({measured["types"].elems.mapIt(it["docExamples"].getInt).foldl(a + b, 0)} examples
  from Mermaid's documentation), and Pele's seeded mutator for fuzzing (`tests/support/corpus.ts`).
- **Port the decisions with the code.** Pele's comments carry its reasons. A ported file keeps
  them, translated to Nim but not shortened, so the next session knows why a line is there.
"""

nbNote("""Strings: should the port keep Nim's UTF-8 strings and emulate UTF-16 where it shows
(lengths, the measurer, error offsets), or carry UTF-16 everywhere? This post leans to the first:
most of the 600-odd `charCodeAt` calls compare with ASCII, which is the same in both, and UTF-8
keeps nim-regex and the standard library usable. It is a decision for a record before the first
parser is ported.""", nkQuestion, "Open: how to hold a string")

nbText: """
## Sources

- Pele at the pin: [obsidianmd/pele@3a2f075](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac),
  MIT. In particular `AGENTS.md`, `CONTRIBUTING.md`, `src/core.ts`, `src/layout/layered.ts` (its
  header), `src/text/measurer.ts`, `src/svg/builder.ts`, `src/diagrams/common/tokens.ts`,
  `src/diagrams/gantt/dates.ts`, `tests/support/corpus.ts`, and the compatibility page
  (`website/src/content/docs/compatibility.md`, published at pele.run).
- Every number on this page comes from `docs/devlog/data/how_pele_is_built/measure.nim`, run on
  that checkout, and from `traps/v8.mjs` and `traps/compare.nim` (Node and Nim versions are in
  `traps/results.json`).
- The relay race and the layout of this post follow gleam-in-nim's *How the Gleam compiler is
  made*.
"""

nbSave
