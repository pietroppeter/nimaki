## devlog: 12 Nov 2026 M | A timeline, and a second kind of lexer | nimaki draws Mermaid's timelines, byte for byte as Pele does: a lexer in Jison's style, words cut to fit their box, and a diagram that turns to run down a phone.
## kind: port
import std/[os, strformat, strutils, json]
import nimib
import ../blocks, ../site, ../pele
import nimaki
from nimaki/diagrams/timeline/lexer import tokenize, TOKEN_NAMES

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var row: JsonNode
for r in difftest["types"]:
  if r["type"].getStr == "timeline": row = r
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["timeline"]

proc nimLines(dir: string): int =
  for path in walkDirRec(repoDir / dir):
    if path.endsWith(".nim"): result += readFile(path).countLines

let timelineLines = nimLines("src" / "nimaki" / "diagrams" / "timeline")

nbText: &"""
## The findings, first

- **nimaki draws timelines.** All {row["cases"].getInt} timeline cases of the corpus come out
  identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} generated ones
  ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages), on every run of CI.
- **The core held.** Timeline is the second type, and it needed almost nothing new below it: two
  small shared files (`scan.ts`, `fit.ts`) and the arrow head of `svg/edges.ts`. The type itself is
  {timelineLines} lines of Nim. It matched on the first run of the referee, which says more about
  the core [First light](../first-light/) built than about this step.
- **A second kind of lexer.** Pie reads its text with a tokenizer driven by a table of patterns.
  Timeline's lexer is a hand-written loop, a port of the rules Mermaid's Jison grammar compiles to.
  Most of Pele's older types are read this way, so its traps are worth writing down now.
- **Bytes, not code units, again.** The lexer steps over characters one at a time. In JavaScript a
  step is one UTF-16 code unit; here it is one byte, unless the character is longer. Where that
  matters, the port steps over the whole character, and the fuzzer now tries spaces from outside
  ASCII in the places it matters.

## A timeline, twice

A timeline is a list of *periods* (a year, a phase), each with *events*, grouped in *sections*:
"""

let timelineText = """timeline
  title Steps of the port
  section Core
    numbers : JavaScript's rounding : UTF-16 lengths
    text : the metrics measurer
  section Diagrams
    pie : first light
    the timeline : this post
    flowchart : the layered layout
"""

nbText: &"""
```mermaid
{timelineText.strip}
```

Pele draws it, in Node, while this page is built:
"""

let fromPele = peleSvg(timelineText)
nbSvg fromPele, "Pele 1.13.0, in Node."

nbText: "And nimaki, in the program that builds this page:"

nbCode:
  let fromNimaki = render(timelineText).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "nimaki, in Nim. The same bytes."

nbText: """
## Two ways to cut text into tokens

Before a program can understand a line like `pie : first light`, it cuts it into *tokens*: the
words of the language, each with a kind. This is *lexing*, and the program that does it is a
*lexer*. [Drawing a diagram from scratch](../drawing-a-diagram/) built a toy one.

Pele has two kinds of lexer, because Mermaid has two kinds of grammar:

- The newer types (pie, and later packet, radar, treemap...) are written in Langium, which
  describes each token with a regular expression. Pele's `tokens.ts` runs such a table: at each
  position it tries every pattern and keeps the one that matches. Pie used it.
- The older types (timeline, journey, flowchart, sequence...) are written in Jison, a tool from
  2009 that compiles a grammar into a JavaScript program. Pele does not run Jison: it ports the
  rules by hand, as a loop that looks at the next character and decides. Timeline's lexer is one
  such loop, 134 lines.

Here is what it makes of a short timeline, run on this page:
"""

nbCode:
  let source = "timeline\n  section Core\n    pie : first light : merged\n"
  let tokens = tokenize(source)
  for i, kind in tokens.types:
    echo TOKEN_NAMES[kind].alignLeft(10), " \"", tokens.texts[i].replace("\n", "\\n"), "\""

nbText: """
The rules are Mermaid's, with its oddities kept on purpose. A line is a *period* up to the first
colon. Then each `: ` starts an *event*, which runs to the end of the line or to the next colon
that is followed by a space: `1:2` stays inside one event, `a : b` makes two. A `section` keeps
everything up to the line's end as its name, and `title` alone on a line is ignored. A period
cannot start with the word `timeline`: the lexer reads it as the header again, and the parser
stops. This post's first draft found that out, in Pele and in nimaki alike. The parser
after it is short: it walks the tokens and calls the *database*, an object that collects the
sections, periods and events, as Mermaid's own parsers do.

## The step is a byte

The loop moves along the text one character at a time: `p++` in TypeScript. In JavaScript a
string is a row of UTF-16 code units, so `p++` steps over one of them. In nimaki strings are
UTF-8 bytes ([decision 0011](../../decisions/#0011-strings-stay-utf-8-javascript-s-utf-16-is-counted-only-where-it-shows)),
so `p += 1` steps over a byte, and a character outside ASCII is two to four bytes.

Most of the time this does not matter. When the loop is looking for a colon or a line break,
stepping into the middle of a longer character is harmless: no byte of `ü` or `日` is a colon. It
matters where the loop asks whether the next character is a *space*, because JavaScript's
`\s` includes spaces outside ASCII, like the ideographic space `　` (three bytes in UTF-8). After
`title`, `section` or the colon of an event, Pele skips one space character and keeps the rest:
`text.substring(6)` drops `title` and its space. The port drops the keyword and one whole
character instead (`afterUnits` in the parser), and the lexer steps with `sizeAt`, which gives
the length in bytes of the character at a position:
"""

nbCode:
  let wide = "timeline\ntitle　Wide\n"
  echo "title in Pele:   ", peleSvg(wide).contains(">Wide<")
  echo "title in nimaki: ", render(wide).svg.contains(">Wide<")

nbText: """
The fuzzer did not find this one: the corpus has no such space, and neither had the fuzzer's list
of words until this step added a few. It was read off the TypeScript while porting, and the
fuzzer now checks it on every run.

## Cutting a word to fit

A period's box has a fixed width, 152 pixels. Pele's labels wrap only at spaces, so a long word
would run out of its box. Timeline (and journey) use `fitLabel` from `fit.ts`: when a label is
still too wide after wrapping, it cuts the text into *units* and puts a line break before the
first unit that would overflow. A unit is one character, or something that must not be split:
a `<br>`, an entity like `&amp;`, or a character outside the Basic Multilingual Plane, which
JavaScript stores as two code units (a *surrogate pair*).

In nimaki one character is already one unit, whatever its size in bytes, so the surrogate pairs
need no rule of their own; but `fit.ts` treats a unit longer than two code units as markup, so the
port measures each unit's length in UTF-16 (`utf16Len`) before it asks.
"""

let longWord = "timeline\n  Supercalifragilisticexpialidocious : a word wider than its box\n  short : fits\n"
nbSvg render(longWord).svg, "A word cut to fit its box, drawn by nimaki."

nbText: """
## Across, or down

A timeline runs across, left to right. On a narrow screen that makes a very wide drawing, so Pele
turns it to run down when the host says it has less than 640 pixels and the drawing would not
fit (`turnToFit` in `fit-width.ts`, ported with pie). Here is the first timeline again, drawn for
a phone 390 pixels wide:
"""

nbCode:
  var phone: RenderOptions
  phone.maxWidth = some(390.0)
  let down = render(timelineText, phone)
  echo "width ", down.width, ", identical to Pele's: ", down.svg == peleSvg(timelineText, %*{"maxWidth": 390})

nbSvg down.svg, "The same timeline, turned for a narrow screen."

nbText: """
## The fuzzer, for timelines

`tools/fuzz.nim` learned a second grammar. It writes timelines from a list of words (the labels
pie used, and words with colons, `<br>`, tags, icons, long words, spaces from outside ASCII), with
sections, titles, accessibility lines, comments, front matter that turns off the colours, and
broken lines on purpose. About a third of its inputs are errors, so the error messages, their
line and column, are compared too. CI runs 5,000 on every pull request:
"""

nbCode:
  echo "fuzz: timeline, seed ", fuzz["seed"].getInt, ", ", fuzz["cases"].getInt, " cases: ",
    fuzz["identical"].getInt, " identical, ", fuzz["different"].getInt, " different"

nbNote """
The timeline corpus (24 cases) and 5,000 generated timelines in CI: identical. Before merging,
35,000 more across seven seeds: identical. Pie and the type detector still identical.
""", nkDone, "Checked"

nbNote """
- The fuzzer writes from a list of words; it does not invent characters. Labels with Markdown,
  math or images are not used by timeline, so they are not checked here.
- `edges.nim` holds only the arrow marker for now (`## port-part-of`); the rest of `edges.ts`
  comes with the layered layout and flowchart.
- Every file is `draft` until a second reading against the TypeScript
  ([decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)).
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Timeline is done** on the [coverage map](../../coverage/) and the [roadmap](../../roadmap/).
  Milestone 1 (the core, pie and timeline) is complete.
- **Jison-style lexers have their rules.** The porting guide now says how a hand-written lexer
  steps over text (`codeAt`, `sizeAt`) and how a `substring(n)` after a keyword is written.
  Journey shares `scan.ts` and `fit.ts` with timeline, so it is the cheapest next type.
- **The layered layout runs in its own thread**, with flowchart. It will extend `svg/edges.nim`,
  which this step started with the arrow marker, under the same names.

## Sources

- Pele at the pin: [`src/diagrams/timeline/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/timeline),
  [`src/diagrams/common/scan.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/scan.ts),
  [`src/diagrams/common/fit.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/fit.ts),
  [`src/svg/edges.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/svg/edges.ts)
  (`marker` and `ARROW`), read for this step.
- [Mermaid's timeline syntax](https://mermaid.js.org/syntax/timeline.html) and
  [Jison](https://gerhobbelt.github.io/jison/), the parser generator of Mermaid's older grammars.
- The code of this step: [`src/nimaki/diagrams/timeline/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/timeline),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
