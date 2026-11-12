## devlog: 12 Nov 2026 N | Three small diagrams | Journey, info and packet join pie and timeline: a mood chart, a version stamp and a table of bits, each byte for byte as Pele draws them, and what JavaScript's Number() and sort() hide.
## kind: port
import std/[os, strformat, strutils, json, algorithm, tables, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki
from nimaki/js import jsToNumber, jsString, jsCompare

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
var identical = 0
for r in difftest["types"]:
  cases[r["type"].getStr] = r["cases"].getInt
  identical += r["identical"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]

nbText: &"""
## The findings, first

- **Five types now.** Journey ({cases["journey"]} corpus cases), info ({cases["info"]}) and packet
  ({cases["packet"]}) come out of nimaki identical to Pele's, byte for byte, as pie and timeline do.
  The referee finds {identical} identical drawings in the corpus, and none different.
- **The fuzzer covers all five.** CI now writes {fuzz["journey"]["cases"].getInt.thousands} journeys,
  {fuzz["info"]["cases"].getInt.thousands} infos and {fuzz["packet"]["cases"].getInt.thousands} packets
  on every pull request, besides pies and timelines, and compares every drawing and error message.
- **JavaScript hides in a score.** A journey's score is read with `Number()`, which accepts more
  than it seems: spaces, an empty text, `0x3`, `Infinity`. Its people are sorted with `sort()`,
  which orders text by UTF-16, not by the bytes Nim compares. Both are now in `js.nim`, tested
  against Node.
- **Each type was a small port.** None needed anything new below it beyond three short shared
  files: `fit-text.ts` and `literal-label.ts` for packet, and `scan.ts` and `fit.ts`, which
  [timeline](../timeline/) had already brought.

## A journey

A *user journey* follows someone through a task, step by step, and says how each step felt: a
score from 1 to 5, drawn as a face. Mermaid's syntax gives each task a score and the people in it:
"""

let journeyText = """journey
  title Porting a diagram
  section Read
    Read the TypeScript: 4: Port
    Find the traps: 2: Port, Referee
  section Check
    Run the referee: 3: Referee
    All identical: 5: Port, Referee
"""

nbText: &"""
```mermaid
{journeyText.strip}
```
"""

nbCode:
  let fromPele = peleSvg(journeyText)
  let fromNimaki = render(journeyText).svg
  echo "identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "A journey, drawn by nimaki; Pele draws the same bytes."

nbText: """
Journey is read like timeline, by a hand-written loop in the style of Mermaid's Jison grammar
([the timeline post](../timeline/) explains it), and shares its lexer rules and its way of fitting
words in a card. Two small things in it are JavaScript at work.

## What `Number()` accepts

Pele reads the score as written, with `Number(text)`. JavaScript's `Number` is generous: it drops
spaces around the number, any kind of space, reads an empty text as 0, knows hexadecimal and
`Infinity`, and gives `NaN`, *not a number*, for anything else. Nim's `parseFloat` raises an error
instead, and reads some of these differently. So `js.nim` gained `jsToNumber`, which follows the
rules of the ECMAScript specification, and a test compares it with Node on fifty texts:
"""

nbCode:
  for text in ["4", " 4 ", "", "0x3", "3.", ".5", "Infinity", "1_000", "x", "　3"]:
    let shown = "\"" & text.replace("\u3000", "\\u3000") & "\""
    echo shown.alignLeft(12), " → ", jsString(jsToNumber(text))

nbText: """
A journey keeps a score that is not a number, draws it at the middle of the scale, with a
neutral face; one of 7 sits at 5. All of this is Pele's behaviour, and now nimaki's.

## The order of names

The legend lists everyone in the journey in sorted order, with `sort()`. With no comparator,
JavaScript sorts text by its UTF-16 code units. Nim compares the bytes of UTF-8, which gives the
same order almost always: for every character up to U+FFFF, and for all the characters past it
among themselves. The two disagree on one corner: a character from U+E000 to U+FFFF (the private
use area, some CJK compatibility forms, the replacement character) against one past U+FFFF (most
emoji). UTF-16 writes the emoji with two *surrogates* starting at 0xD800, so it sorts first;
UTF-8 sorts it last:
"""

nbCode:
  var names = @["\uE000 (U+E000)", "😀 (U+1F600)", "a"]
  names.sort(system.cmp)
  echo "bytes:  ", names
  names.sort(jsCompare)
  echo "UTF-16: ", names

nbText: """
No corpus case has such names; the fuzzer now puts both in a journey, and `jsCompare` is the one
comparison every port of a `sort()` uses.

## Info

`info` is the smallest type: it draws the name and version of the renderer. Pele writes
`Pele v1.13.0`, read from its own `package.json`. nimaki writes the same text, Pele's version at
the pin, because the drawing must be identical; whether a later nimaki should say its own name
here is a question for a wanted divergence, not for this step.
"""

nbCode:
  echo render("info").svg == peleSvg("info")

nbText: """
## Packet

A *packet diagram* draws the fields of a network packet (or any binary format) as a table of
bits, 32 to a row by default. Each line names a range of bits, or a width with `+`:
"""

let packetText = """packet
  0-15: "Source port"
  16-31: "Destination port"
  32-63: "Sequence number"
  +4: "Offset"
  +6: "Reserved"
  +6: "Flags"
  +16: "Window"
"""

nbText: &"""
```mermaid
{packetText.strip}
```
"""

nbCode:
  let packetSvg = render(packetText).svg
  echo "identical to Pele's: ", packetSvg == peleSvg(packetText)

nbSvg packetSvg, "The start of a TCP header, drawn by nimaki."

nbText: """
Three things in it were new to the port:

- **Fields across rows.** A field that runs past the end of a row is split, and each piece keeps
  its label. Mermaid counts a piece's bits one short, and Pele keeps that count, so the port does
  too.
- **Fitting a label in a field.** A narrow field cannot wrap its label. `fitText` (in
  `common/fit-text.ts`) first shrinks the font, down to half the diagram's font size, and then cuts the text and
  adds an ellipsis, `…`. It cuts between code points, never inside one.
- **A pattern that backtracks.** A bit number is the token `INT`, `/0|[1-9][0-9]*(?!\.)/`: a run
  of digits that a dot does not follow. On `12.`, the regular expression gives back its last digit
  and matches `1`, because `1` is followed by `2`, not by a dot. The hand-written scanner does the
  same, as pie's number did.

On a narrow screen, a packet turns too: rows get shorter (a byte at the narrowest), and each label wraps one character
at a time if it must (`literalLabel`):
"""

nbCode:
  var phone: RenderOptions
  phone.maxWidth = some(390.0)
  let narrow = render(packetText, phone)
  echo "width ", narrow.width, ", identical to Pele's: ", narrow.svg == peleSvg(packetText, %*{"maxWidth": 390})

nbSvg narrow.svg, "The same packet for a phone."

nbNote """
The corpus cases of journey, info and packet: identical. Generated inputs before merging:
35,000 journeys, 9,000 infos and 40,000 packets across several seeds, identical; CI runs 5,000
journeys, 1,000 infos and 5,000 packets on every pull request. `jsToNumber` and `jsCompare`
against Node (`tests/test_js.nim`).
""", nkDone, "Checked"

nbNote """
- A hexadecimal score past 2^53 is summed digit by digit, which can round differently from
  JavaScript; no journey writes one.
- `breakLabel` and `leftLabelSvg`, in `literal-label.ts`, are ported but not used by these types;
  they will be checked by treeview and others.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Journey, info and packet are done** on the [coverage map](../../coverage/) and the
  [roadmap](../../roadmap/).
- **The porting guide** has rows for `Number()`, `sort()` and `substring()`: `jsToNumber`,
  `jsCompare` and `substringFrom` of `js.nim`.
- **Next, in this thread:** the other types that need no layered layout, smallest first: radar,
  treemap, treeview, sankey, git, quadrant, venn, xychart and railroad. Types that use the shapes,
  edges or titles the flowchart thread is porting wait for it.

## Sources

- Pele at the pin: [`src/diagrams/journey/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/journey),
  [`src/diagrams/info/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/info),
  [`src/diagrams/packet/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/packet),
  [`src/diagrams/common/fit-text.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/fit-text.ts),
  [`src/diagrams/common/literal-label.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/literal-label.ts),
  read for this step.
- JavaScript's rules: [StringToNumber](https://tc39.es/ecma262/#sec-stringtonumber) and
  [Array.prototype.sort](https://tc39.es/ecma262/#sec-array.prototype.sort) in the ECMAScript
  specification.
- Mermaid's syntax: [user journey](https://mermaid.js.org/syntax/userJourney.html) and
  [packet](https://mermaid.js.org/syntax/packet.html).
- The code of this step: [`src/nimaki/diagrams/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams),
  [`src/nimaki/js.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/js.nim),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
