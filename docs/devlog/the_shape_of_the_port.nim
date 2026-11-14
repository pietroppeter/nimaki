## devlog: 13 Nov 2026 K | The shape of the port | A tour of nimaki's own code, a day and a half in: a mirror of Pele file for file, the path one diagram takes through it, the parts every type leans on, and what explaining it turned up.
## kind: research
import std/[algorithm, json, os, sequtils, strformat, strutils, tables, math]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../pele
import nimaki
from nimaki/js import jsString, jsRound, utf16Len

nbInit
nb.usePost()

# The census of the code this post was written on, frozen: `nim r tools/census.nim --out:...`
# at the commit it records. The numbers below come from it, so they stay the ones of that day.
const dataDir = currentSourcePath.parentDir / "data" / "the_shape_of_the_port"
let census = parseJson(readFile(dataDir / "census.json"))

proc thousands(n: int): string = insertSep($n, ',')

let
  areas = census["areas"].elems
  commit = census["commit"].getStr
  shortCommit = commit[0 .. 6]
  nimFiles = census["files"].getInt
  ported = areas.mapIt(it["ported"].getInt).foldl(a + b, 0)
  tsCode = areas.mapIt(it["ts"].getInt).foldl(a + b, 0)
  ratio = ported / tsCode
  withoutOrigin = census["withoutOrigin"].elems
  typeAreas = areas.filterIt(it["area"].getStr.startsWith("diagrams/") and it["area"].getStr != "diagrams/common")
  shared = census["shared"].elems
  typesCount = typeAreas.len
  drafts = census["statuses"]{"draft"}.getInt
  regexes = census["regexes"].elems
  repeated = regexes.filterIt(it["helpers"].len > 1)
  repeatedHelpers = repeated.mapIt(it["helpers"].len).foldl(a + b, 0)
  top = regexes[0]
  topCount = top["helpers"].len

proc area(name: string): JsonNode =
  for a in areas:
    if a["area"].getStr == name: return a

proc usersOf(module: string): int =
  for s in shared:
    if s["module"].getStr == module: return s["types"].len

nbText: fmt"""
Pietro asked for an article, every once in a while, that explains a part of nimaki's code: its
overall shape, one module, or a pattern that keeps coming back, because having to explain code
is a good way to find out what is in it. This is the first one, and it takes the widest view. The
post *[How Pele is built](../how-pele-is-built/)* toured the TypeScript we port; this one tours
the Nim we have written so far, at commit `{shortCommit}` of 13 November 2026, when {typesCount}
of Pele's diagram types were on `main`.

## The short version

- **The port is a mirror.** `src/` holds {nimFiles} Nim files. All but {withoutOrigin.len} name
  the TypeScript file they translate, and those come to {thousands(ported)} lines of code for
  the {thousands(tsCode)} lines of TypeScript they port: {formatFloat(ratio, ffDecimal, 2)} lines
  of Nim for each line of TypeScript. A reader of Pele can find their way in nimaki with Pele's
  map.
- **Four files port nothing.** Three hold the JavaScript that Pele relies on without saying so
  (how numbers print and round, how strings count, how dates work), and one is the entry point.
- **The layers are clean.** Shared code never imports a diagram type, and only two types import
  another one (swimlane and agentflow build on flowchart), as in Pele.
- **One JavaScript line became {topCount} functions.** Pele cleans up an accessible description
  with `text.replace(/\n\s+/g, '\n')`. With no regular expressions in the port, each type wrote
  that line again as a small scanner, in five slightly different ways. Explaining them made me
  test them: they all agree with Pele, on inputs the corpus does not have.
- **Every ported file is still a `draft`.** The ladder of
  [decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)
  (draft, verified, conformant) has not been climbed once, while the coverage map calls
  all {typesCount} ported types done. That needs a decision, not a fix.

## A map of the code

The code lives in `src/nimaki/`, in folders named after Pele's `src/`:

- **core**: the files directly in `src/nimaki/`: `core.nim` (the `render` function), `detect.nim`
  (which diagram is this?), `preprocess.nim` (front matter, directives, comments), `errors.nim`,
  `types.nim` (the options and the result), and the JavaScript layer.
- **util**: YAML, URLs and a few character tables.
- **text**: measuring text without a browser, and cutting labels into lines.
- **svg**: writing SVG: escaping, numbers, shapes, edges and arrowheads, the theme.
- **layout**: the layered layout and its compound and lane variants, shared by the types made of
  boxes and arrows.
- **diagrams/common**: the lexer machinery and small helpers the types share.
- **diagrams/&lt;type&gt;**: one folder per type, each a small pipeline of its own.

Measured as the port map (`tools/portmap.nim`) measures Pele (lines that are neither blank nor
only a comment), each part beside the TypeScript it ports (TS), and the ratio of the two:
"""

block:
  type Row = object
    part: string
    files, nim, ts: int
    ratio: string
  var rows: seq[Row]
  var typesNim, typesTs, typesFiles = 0
  for a in areas:
    let name = a["area"].getStr
    if name in typeAreas.mapIt(it["area"].getStr):
      typesNim += a["ported"].getInt
      typesTs += a["ts"].getInt
      typesFiles += a["files"].getInt
      continue
    rows.add Row(part: name.replace("diagrams/", ""), files: a["files"].getInt, nim: a["ported"].getInt, ts: a["ts"].getInt,
                 ratio: formatFloat(a["ported"].getInt / a["ts"].getInt, ffDecimal, 2))
  rows.add Row(part: &"{typesCount} types", files: typesFiles, nim: typesNim, ts: typesTs,
               ratio: formatFloat(typesNim / typesTs, ffDecimal, 2))
  let t = tabella(rows, rownameCol = "part"):
    tabHeader "Nim beside TypeScript", "lines of code of the files that port Pele, at " & shortCommit
    colsLabel {"nim": "Nim", "ts": "TS", "ratio": "ratio"}
    fmtInteger ["nim", "ts"]
    optCssTheme()
  nbTable t

let
  core = area("core")
  util = area("util")

let common = area("diagrams/common")

nbText: fmt"""
The table counts only the files that port Pele. The JavaScript layer, which has no TypeScript to
be compared with, adds {thousands(core["nim"].getInt - core["ported"].getInt)} more lines to the
core. Two rows run long: **util**, {formatFloat(util["ported"].getInt / util["ts"].getInt, ffDecimal, 2)}
times its TypeScript, and **diagrams/common**,
{formatFloat(common["ported"].getInt / common["ts"].getInt, ffDecimal, 2)} times. Both for the
same reason: they hold the YAML and URL readers and the shared lexer machinery, where Pele leans
hardest on regular expressions, and a regular expression of one line is a loop of ten in a
hand-written scanner. Everywhere else, Nim and TypeScript are about the same length, which is what
a translation that keeps "same functions, same control flow"
([decision 0002](../../decisions/#0002-this-is-a-port-not-a-rewrite)) should look like.
"""

nbFold "Every diagram type, Nim beside TypeScript":
  block:
    type Row = object
      `type`: string
      files, nim, ts: int
      ratio: string
    var rows: seq[Row]
    for a in typeAreas:
      rows.add Row(`type`: a["area"].getStr.replace("diagrams/", ""), files: a["files"].getInt,
                   nim: a["ported"].getInt, ts: a["ts"].getInt,
                   ratio: formatFloat(a["ported"].getInt / a["ts"].getInt, ffDecimal, 2))
    rows.sort(proc (a, b: Row): int = cmp(b.nim, a.nim))
    let t = tabella(rows, rownameCol = "type"):
      tabHeader "The diagram types, largest first", "lines of code, at " & shortCommit
      colsLabel {"nim": "Nim", "ts": "TS", "ratio": "ratio"}
      fmtInteger ["nim", "ts"]
      optCssTheme()
    nbTable t

nbText: """
## One diagram, start to finish

The whole port is reached through one function, `render`, in `src/nimaki.nim`. Here it draws a
diagram of its own path, while this page is built:
"""

let pathText = """flowchart TD
  text["Mermaid text"] --> pre["preprocess: front matter, directives, comments"]
  pre --> detect["detect: which diagram is this?"]
  detect --> table["the table of types: diagrams[kind]"]
  table --> parse["the type's parse: text to model"]
  parse --> draw["the type's render: model to SVG"]
  draw --> svg["SVG text"]
"""

nbCode:
  let drawn = render(pathText)
  echo drawn.diagramType, ": ", drawn.svg.len, " bytes of SVG, ", jsString(drawn.width), " × ",
    jsString(drawn.height), " pixels"
  echo "the same bytes as Pele's: ", drawn.svg == peleSvg(pathText)

nbSvg drawn.svg, "The path of a diagram through render(), drawn by nimaki."

nbText: """
Step by step, in `core.nim`:

1. **Preprocess.** Mermaid text can start with YAML front matter (`---` lines with a title and a
   configuration) and carry `%%{init: ...}%%` directives and `%%` comments. `preprocess` takes
   them out and keeps the configuration aside.
2. **Detect.** `detect.nim` reads the first words (`flowchart TD`, `pie`, `sequenceDiagram`...)
   and names the type. It knows all 33 of Pele's types, ported or not.
3. **Look up.** Every ported type is one entry of a table, `diagrams`, filled by the
   `register(...)` calls at the end of `src/nimaki.nim`. A type that is not there yet raises an
   error with the code `unsupported`, which the referee counts as *not ported* rather than
   *wrong*.
4. **Parse.** The type's `parse` turns the text into a **model**: plain data (slices, nodes,
   messages) with nothing about pixels in it.
5. **Render.** The type's `render` measures the labels, places everything (alone, or with the
   shared layered layout) and writes SVG text.

Two Nim ideas carry these steps, and both come straight from the TypeScript.
"""

nbText: """
### A table of types, and models of different shapes

Each type is described by a value of one object type, `Diagram` (in `types.nim`): its name and
two procedures, `parse` and `render`. In Pele it is `Diagram<PieModel>`, a type with a parameter.
TypeScript forgets that parameter when the program runs, so a list of diagrams of different
models is no problem there. Nim keeps it, and a `Diagram[PieModel]` and a `Diagram[FlowModel]`
would be two different types that cannot sit in one table. So the port passes models as
`RootRef`, a reference to *some object*, and each type converts it back to its own model on the
way in. The conversion is checked when the program runs. A small version, runnable:
"""

nbCode:
  type
    Kind = object
      name: string
      parse: proc (text: string): RootRef
      render: proc (model: RootRef): string
    Slices = ref object of RootObj     # one type's model
      values: seq[int]

  let pieLike = Kind(name: "slices",
    parse: proc (text: string): RootRef =
      Slices(values: text.split(',').mapIt(parseInt(it.strip))),
    render: proc (model: RootRef): string =
      let m = Slices(model)            # back to the type's own model, checked at run time
      m.values.mapIt($it).join(" + ") & " = " & $m.values.foldl(a + b))

  var kinds: Table[string, Kind]
  kinds[pieLike.name] = pieLike
  let k = kinds["slices"]
  echo k.render(k.parse("386, 85, 15"))

nbText: fmt"""
The real `pie` entry, in `src/nimaki/diagrams/pie/index.nim`, is the same shape: `parse` calls
`buildPie(parsePie(source), title)` and `render` calls `renderPie(PieModel(model), ...)`. Every
type has an `index.nim` like it, and none is longer than a screen.

### Settings that hold while a diagram is drawn

Some settings must reach code deep inside a render without being passed through every call: the
colour palette, the resolver that turns `fa:fa-car` into an icon, the one that turns `$$x^2$$`
into math. Pele keeps each in a variable of its module and sets it for the length of one call:

```ts
export function withPalette<T>(next: Palette, run: () => T): T {{
  const outer = current;
  current = next;
  try {{
    return run();
  }} finally {{
    current = outer;
  }}
}}
```

The `finally` puts the old value back even when the render fails, so one diagram's palette
never leaks into the next. The port has the same four functions (`withPalette`, `withIcons`,
`withMath`, and `locatingIn` for error positions), line for line. `render` nests three of them
around the type's own `render`. A small version:
"""

nbCode:
  var ink = "black"
  proc withInk[T](next: string, run: proc (): T): T =
    let outer = ink
    ink = next
    try:
      result = run()
    finally:
      ink = outer
  proc drawDot(): string = "<circle fill=\"" & ink & "\"/>"   # far from the caller, reads `ink`

  echo withInk("lava", proc (): string = drawDot())
  echo drawDot()

nbNote """
This works because a render runs from start to end on one thread, as Pele's does in JavaScript.
Two renders at once on two threads would share these variables. Nothing in nimaki does that
today; a host that wants it, such as a server, should keep one render per thread.
""", nkNim, "One render at a time"

nbText: fmt"""
## What every type leans on

Each diagram type imports a handful of shared modules. Counting, for each shared module, how
many of the {typesCount} types import it directly shows what the core really is:
"""

block:
  type Row = object
    module: string
    types: int
  var rows: seq[Row]
  for s in shared:
    if s["types"].len >= 6:
      rows.add Row(module: "`" & s["module"].getStr & "`", types: s["types"].len)
  let t = tabella(rows, rownameCol = "module"):
    tabHeader "Shared modules by how many types import them", "imported by six types or more, at " & shortCommit
    colsLabel {"types": &"of {typesCount} types"}
    fmtMarkdown ["module"]
    optCssTheme()
  nbTable t

nbText: fmt"""
At the top, imported by almost every type, are the plumbing of a render: the options and the
`Diagram` type (`types.nim`), the preprocessed configuration (`preprocess.nim`), the SVG writer
(`svg/builder.nim`), labels (`text/label.nim`) and the text measurer (`text/measurer.nim`),
which is how a renderer with no browser knows how wide a word is. The JavaScript layer,
`js.nim`, is imported by {usersOf("js.nim")} types. The layered layout, the largest single file
of the port, is imported directly by only {usersOf("layout/layered.nim")}: the types made of
boxes and arrows. Pie, journey or gantt place their shapes with a little arithmetic of their
own.

Arrows between parts go one way only. The census looks for shared code that imports a diagram
type and finds {census["upward"].len} such imports. Between types there are exactly two
dependencies, both on flowchart: **swimlane** is a flowchart whose groups become lanes, and
**agentflow** is a flowchart that knows what each node is. Pele has the same two.

## The JavaScript layer

The four files that port nothing are worth a look, because they are where JavaScript's
behaviour is made explicit:
"""

block:
  type Row = object
    file: string
    lines: int
    holds: string
  let holds = {"js.nim": "how JavaScript prints, rounds and parses numbers, and counts strings in UTF-16 units",
               "jsdate.nim": "JavaScript's `Date`: its calendar, time values and V8's forgiving date parser (for gantt)",
               "jsmath.nim": "the one door for `sin`, `cos`, `pow`... so V8's own versions could replace C's in one place",
               "nimaki.nim": "the entry point: imports every ported type and registers it"}.toTable
  var rows: seq[Row]
  for f in withoutOrigin:
    rows.add Row(file: "`" & f["path"].getStr & "`", lines: f["code"].getInt, holds: holds.getOrDefault(f["path"].getStr))
  let t = tabella(rows, rownameCol = "file"):
    tabHeader "The files with no TypeScript twin", "lines of code, at " & shortCommit
    fmtMarkdown ["file", "holds"]
    optCssTheme()
  nbTable t

nbText: """
Pele never writes these down because JavaScript gives them for free. A port has to, or the SVG
comes out different by a digit. Three of them, run here:
"""

nbCode:
  echo "String(100) is ", jsString(100.0), " and String(-0) is ", jsString(-0.0), "; Nim's $ says ", $100.0, " and ", $(-0.0)
  echo "Math.round(-2.5) is ", jsString(jsRound(-2.5)), "; Nim's round(-2.5) is ", jsString(round(-2.5))
  echo "\"🌊\".length is ", utf16Len("🌊"), " in JavaScript; the Nim string holds ", "🌊".len, " bytes"

nbText: """
The [porting guide](../../porting/) lists when to use which, and `tests/test_js.nim` checks
them against Node on thousands of seeded numbers every time the tests run.
"""

nbText: fmt"""
## What explaining it turned up

### One line of JavaScript, {topCount} functions

Pele has no regular expression library to avoid; it uses JavaScript's, about 480 times. The port
uses none: the porting guide asks for a hand-written scanner instead, with the pattern it
answers to quoted in its first comment line. That convention makes them countable. The census
finds {regexes.len} different patterns written as {census["regexHelpers"].getInt} helper
functions, and {repeated.len} of the patterns written more than once, as {repeatedHelpers}
helpers.

The champion is the line every type uses to tidy an accessible description (the text a screen
reader announces, written `accDescr {{ ... }}`): drop the indentation after each line break.

```ts
this.accDescr = text.replace(/\n\s+/g, '\n');
```

Pele writes this line inline in {top["peleFiles"].getInt} files. Ported, it became {topCount} functions in {topCount}
files, named `collapseIndents`, `dropBreakSpaces`, `dropIndentation` or folded into
`setAccDescription`, and written in five different shapes by different sessions on different
days. The subtle part is `\s`: in JavaScript it is not only space and tab but also the line
break itself, the no-break space, the ideographic space, the byte order mark and a dozen more,
and the corpus has none of those after a line break. Five shapes of loop, a class of characters
the corpus never tries: a good place for a bug to hide.

So I tried. For every type that keeps a description, the same small diagram with twelve awkward
descriptions, drawn by Pele in Node and by nimaki, compared byte for byte, while this page is
built:
"""

let awkward = ["one\n   two", "one\n two", "one\n　two", "one\n﻿two", "one\n\t\n  two",
  "one\n two", "one\n​two", "one\n two", "one\n  two", "one\n\n\ntwo",
  "one\n᠎two", "one\n\u0085two"]
let withDescription = [
  ("pie", "pie\nBODY\n\"a\": 1\n\"b\": 2"),
  ("packet", "packet-beta\nBODY\n0-15: \"Source\""),
  ("radar", "radar-beta\nBODY\naxis a, b, c\ncurve x{1,2,3}"),
  ("treemap", "treemap-beta\nBODY\n\"A\"\n  \"B\": 10"),
  ("treeView", "treeView-beta\nBODY\n\"a\"\n  \"b\""),
  ("info", "info\nBODY"),
  ("architecture", "architecture-beta\nBODY\nservice db(database)[DB]"),
  ("cynefin", "cynefin-beta\nBODY\nclear \"x\""),
  ("wardley", "wardley-beta\nBODY\ncomponent A [0.5, 0.5]"),
  ("gantt", "gantt\nBODY\ndateFormat YYYY-MM-DD\nsection S\nT :a1, 2026-01-01, 3d"),
  ("railroad", "railroad-ebnf-beta\nBODY\ndigit = \"0\" | \"1\" ;"),
  ("class", "classDiagram\nBODY\nclass A"),
  ("sequence", "sequenceDiagram\nBODY\nA->>B: hi"),
  ("flowchart", "flowchart LR\nBODY\nA-->B"),
  ("requirement", "requirementDiagram\nBODY\nrequirement r {\nid: 1\n}"),
  ("journey", "journey\nBODY\nsection S\nT: 5: Me"),
  ("timeline", "timeline\nBODY\n2020 : a"),
  ("state", "stateDiagram-v2\nBODY\n[*] --> A"),
  ("er", "erDiagram\nBODY\nA ||--o{ B : has"),
  ("gitGraph", "gitGraph\nBODY\ncommit"),
  ("usecase", "usecase-beta\nBODY\nactor A"),
  ("agentflow", "agentflow-beta\nBODY\nA --> B"),
  ("swimlane", "swimlane-beta\nBODY\nA --> B"),
  ("c4", "C4Context\nBODY\nPerson(a, \"A\")"),
]

nbCode:
  var sources: seq[string]
  for (kind, diagram) in withDescription:
    for body in awkward:
      sources.add diagram.replace("BODY", "accDescr {\n" & body & "\n}")
  let fromPele = peleRenders(sources)      # one Node process, Pele 1.13.0
  var same, different, described = 0
  for i, source in sources:
    let nim = render(source, RenderOptions(now: some(fixedNow))).svg
    if nim == fromPele[i]["svg"].getStr: inc same else: inc different
    if "<desc" in nim: inc described
  echo withDescription.len, " types × ", awkward.len, " descriptions: ", same, " identical, ",
    different, " different (", described, " drawings carry the description)"

doAssert different == 0, "an accDescr scanner disagrees with Pele"

nbFold "The twelve descriptions, and the five shapes of the scanner":
  nbText: """
Each description is `one`, a line break, something, and `two`: three spaces; a no-break space
(U+00A0); an ideographic space (U+3000); a byte order mark (U+FEFF); a tab and a blank line; the
Ogham space mark (U+1680); a zero-width space (U+200B, *not* `\s`); the line separator (U+2028);
two em spaces; two blank lines; the Mongolian vowel separator (U+180E, `\s` until Unicode 6.3,
not any more); and the next-line control (U+0085, not `\s` either).

The five shapes, as they stand in the code: one checks for a space after the line break before
writing the break, then skips the spaces (`pie/model.nim`); one writes the break and skips
whatever spaces follow, none included (`gantt/db.nim`); one calls a shared `spaces` skipper of
its own folder (`railroad/db.nim`); one steps over code points with `isJsSpaceAt`
(`class/db.nim`); and one reads each code point and asks `isSpace` of `util/chars.nim`
(`c4/db.nim`). They read differently and do the same thing.
"""

nbText: fmt"""
They are all right: {withDescription.len} types, twelve awkward descriptions each, not one byte
different. The finding is not a bug but a cost: {repeatedHelpers} functions that re-derive
{repeated.len} JavaScript patterns, each a one-liner in Pele, and the next type will write its
own again. The porting guide
already has the answer for numbers, `js.nim`: one place, tested against Node. The same could
hold the patterns Pele uses most (`/\n\s+/g`, `/^\s+/`, `/^default\s?/`, a JavaScript integer, an
identifier), each tested once against Node, and the call sites would still be one line, as in
the TypeScript. That is a change to many files other threads own, so it goes on the
[roadmap](../../roadmap/) as a step (`shared-scanners`), not into this post's pull request.
"""

nbFold "The patterns written more than once":
  block:
    type Row = object
      pattern: string
      helpers: int
      where: string
    var rows: seq[Row]
    for r in repeated:
      var files = r["helpers"].elems.mapIt(it["file"].getStr.replace("diagrams/", "").split('/')[0])
      files = files.deduplicate
      rows.add Row(pattern: "`" & r["regex"].getStr.replace("|", "\\|") & "`", helpers: r["helpers"].len,
                   where: files.join(", "))
    let t = tabella(rows, rownameCol = "pattern"):
      tabHeader "Regular expressions written as scanners more than once", "at " & shortCommit
      fmtMarkdown ["pattern"]
      optCssTheme()
    nbTable t

nbText: fmt"""
### Every file is a draft

Each ported file says in its second line how far it has come: `draft` (translated), `verified` (a
second reading, with fresh eyes, against the TypeScript, function by function, looking for
differences), `conformant` (Pele's own tests for it pass, and the referee finds its part
identical). All {drafts} ported files say `draft`. None has been read a second time, and the
port map (`docs/data/portmap.json`) has no file past the first rung.

Meanwhile the [coverage map](../../coverage/) marks all {typesCount} ported types done, because the referee
finds every case of their corpus identical, and fuzzing finds thousands more identical. So the
port is better checked than its headers say, in one way (the output), and less in another (the
reading). A second reading is the check that finds what no corpus covers, like the twelve
descriptions above; this time they all held.

The ladder is starting to move. Today another thread claimed two steps that end with files
leaving `draft`: `labels-check` (the label features of `src/text`, against Pele with a fuzzer)
and `pele-tests` (Pele's own test suites, run through the port). Both say their files become
`verified`, through tests. Decision 0005 gives that word to the second reading and keeps tests
for `conformant`. Neither reading is wrong, but the port map can only mean one thing by it.
"""

nbNote """
What moves a file past `draft`? Either the ladder stays as decision 0005 wrote it (`verified`
after a second reading, `conformant` after Pele's tests), and a step reads each file again, in the
order of how much code depends on it (`js.nim`, the measurer, the SVG builder, the layered layout
first); or a new decision lets tests and fuzzing count, so a file whose part is identical on the
corpus, on Pele's tests and on fuzzing may say `conformant`, keeping `verified` for files that were
reread. The roadmap holds this as a planned step, `second-reading`, until Pietro picks.
""", nkQuestion, "For Pietro: draft, verified, conformant"

nbText: fmt"""
### Smaller things

- **The flowchart has a twin.** Agentflow's lexer and parser share at least six helpers with
  flowchart's, copied rather than imported (`reNodir`, `reDir`, `lineTerminatorFrom`,
  `replaceBraceTrail`...). Pele has the same copies: its agentflow lexer repeats flowchart's
  patterns constant for constant (`RE_NODIR`, `RE_DIR_SYM`, `RE_EMPTY_CALL`...). A port should
  keep the copy, but a fix to one must be made to both, and nothing says so yet. A
  comment on each copy naming its twin would.
- **The port map has no page.** `tools/portmap.nim` writes `docs/data/portmap.json` in every
  pull request that ports a file, and CI checks its origins, but only the first post of the
  devlog reads it. The [coverage map](../../coverage/) could show it beside each type, so the
  rung each file stands on is visible where the port is followed.
- **`tests/` is small on purpose.** {census["tests"]["files"].getInt} files,
  {thousands(census["tests"]["code"].getInt)} lines of code: the JavaScript layer and dates checked
  against Node, the layout's invariants (`test_layout.nim`, Pele's own layout tests, ported),
  detection, and the referee's own verdicts. Pele's tests of each type are not ported; their
  inputs reach the port through the corpus instead, which is how the referee checks the output.
  That is also why no file can be `conformant` yet: decision 0005 asks for those tests.

## What this changes for the port

- The [roadmap](../../roadmap/) has phase 5, *Along the way*, with this article's step and the
  recurring step for the articles that follow, and two new planned steps from this one:
  `shared-scanners` (the repeated patterns, once, tested against Node) and `second-reading` (the
  status ladder, waiting on the question above).
- `tools/census.nim` counts the code the way this post does: sizes beside the TypeScript, imports,
  shared modules, and the repeated patterns. Each article freezes one census in its data folder,
  so a later article can say what changed. Its `ERROR` line fires if shared code ever imports a
  diagram type.
- The probe of the twelve descriptions runs every time the pages are built, and fails the build if
  a scanner ever disagrees with Pele.
- Next articles, one subject each: the lexers (three families of them: Jison's rules ported by
  hand, a shared tokenizer, and stateful lexers like class's thirteen states); the layered layout
  file by file; the referee and fuzzers, as code; and the JavaScript layer in depth.

## Sources

- nimaki at commit [`{shortCommit}`](https://github.com/pietroppeter/nimaki/tree/{commit}):
  [`src/nimaki.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki.nim),
  [`src/nimaki/core.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/core.nim),
  [`src/nimaki/types.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/types.nim),
  [`src/nimaki/svg/palette.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/svg/palette.nim),
  [`src/nimaki/js.nim`](https://github.com/pietroppeter/nimaki/blob/{commit}/src/nimaki/js.nim),
  and the census of that commit, [`census.json`](https://github.com/pietroppeter/nimaki/blob/main/docs/devlog/data/the_shape_of_the_port/census.json),
  made by [`tools/census.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/census.nim).
- Pele at the pin: [`src/core.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/core.ts),
  [`src/types.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/types.ts),
  [`src/svg/palette.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/svg/palette.ts),
  and the files that hold `/\n\s+/g`, counted by the census in the pinned checkout.
- What `\s` matches: [character class escapes](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Regular_expressions/Character_class_escape)
  on MDN, and [WhiteSpace](https://tc39.es/ecma262/#sec-white-space) and
  [LineTerminator](https://tc39.es/ecma262/#sec-line-terminators) in the ECMAScript specification.
"""

nbSave
