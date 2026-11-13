## devlog: 12 Nov 2026 W | Crow's feet and requirements | nimaki draws Mermaid's ER and requirement diagrams byte for byte as Pele does: tables of attributes, lines that end in crow's feet, and requirements traced to what satisfies them.
## kind: port
import std/[os, strformat, strutils, json]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/diagrams/er/[lexer, markers, tokens]
import nimaki/diagrams/common/generics

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var row, reqRow: JsonNode
for r in difftest["types"]:
  if r["type"].getStr == "er": row = r
  if r["type"].getStr == "requirement": reqRow = r
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["er"]
let reqFuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]["requirement"]

proc nimLines(dir: string): int =
  for path in walkDirRec(repoDir / dir):
    if path.endsWith(".nim"): result += readFile(path).countLines

let erLines = nimLines("src/nimaki/diagrams/er")
let reqLines = nimLines("src/nimaki/diagrams/requirement")

nbText: &"""
## The findings, first

- **nimaki draws ER diagrams.** All {row["cases"].getInt} ER cases of the corpus come out
  identical to Pele's, byte for byte, and so do {fuzz["cases"].getInt.thousands} generated ones
  ({fuzz["rendered"].getInt.thousands} drawings and {fuzz["errors"].getInt.thousands} error
  messages), on every run of CI. Before merging, 9,000 more on three other seeds agreed too.
- **And requirement diagrams.** All {reqRow["cases"].getInt} requirement cases of the corpus are
  identical too, and so are {reqFuzz["cases"].getInt.thousands} generated ones in CI. The corpus
  is small for this type, so the fuzzer does most of the checking here.
- **They are {erLines} and {reqLines} lines of Nim**, one file for each TypeScript file of
  `src/diagrams/er/` and `src/diagrams/requirement/`.
- **Both matched on the first run**, like state, on the compound layout that flowchart brought.
  The work for ER was in the lexer, which reads both `||--o{{` and `only one to zero or more`, and
  in the drawing of each entity as a small table.

## What an ER diagram is

An *entity relationship* diagram describes the things a system keeps records of (*entities*:
a customer, an order), what each record holds (*attributes*: a name, a date, an id), and how the
records refer to each other (*relationships*). Peter Chen proposed it in 1976 for designing
databases, and it is still how a database schema is sketched.

Each end of a relationship says how many records can be on that side: exactly one, zero or one,
one or more, zero or more. The usual way to draw that is *crow's foot* notation: a bar for one, a
ring for zero, and a three-toed foot for many. A solid line is an *identifying* relationship (the
child cannot exist without its parent), a dashed one is not:
"""

let erText = """erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE-ITEM : contains
  CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
  CUSTOMER {
    string name
    string email UK "the login"
    int id PK
  }
  ORDER {
    int id PK
    int customer FK
    List~Item~ items
  }
"""

nbText: &"""
```mermaid
{erText.strip}
```

Pele draws it, in Node, while this page is built:
"""

let fromPele = peleSvg(erText)
nbSvg fromPele, "Pele 1.13.0, in Node."

nbText: "And nimaki, in the program that builds this page:"

nbCode:
  let fromNimaki = render(erText).svg
  echo fromNimaki.len, " bytes, identical to Pele's: ", fromNimaki == fromPele

nbSvg fromNimaki, "nimaki, in Nim. The same bytes."

nbText: """
## Two ways to say how many

Mermaid writes each end of a relationship as two characters, the outer one first: `|o` is zero or
one, `||` exactly one, `}o` zero or more, `}|` one or more (and mirrored on the right: `o|`, `||`,
`o{`, `|{`). Between them `--` is identifying and `..` is not. It also accepts words: `one or
zero`, `only one`, `zero or more`, `one or many`, `many(0)`, `1+`, `0+`, `1`, and `to` or
`optionally to` for the line itself.

That makes the lexer the subtle part. `1` can be a cardinality or the name of an entity, `u` can
be the parent marker of a `u--` line or an entity called `u`, and `one` is a cardinality only when
a word does not go on after it. Pele decides with a look at the next characters; the port asks
the same questions in the same order. Here is the lexer, run on this page, on the same
relationship written both ways:
"""

nbCode:
  proc show(src: string) =
    let t = tokenize(src)
    var names: seq[string]
    for k in 0 ..< t.types.len - 2:
      if t.types[k] != T_NEWLINE: names.add TOKEN_NAMES[t.types[k]]
    echo names.join(" ")
  show("erDiagram\nCUSTOMER ||--o{ ORDER : places\n")
  show("erDiagram\nCUSTOMER only one to zero or more ORDER : places\n")

nbText: """
## Crow's feet, drawn

Pele draws each marker with a few lines of SVG, measured back from the point where the line
meets the box, along the line's direction. The port's `erMarker` is the same function. Here are
the five, each at the end of a short line that comes in from the left:
"""

nbCode:
  var markersSvg = ""
  for k, kind in ["only_one", "zero_or_one", "one_or_more", "zero_or_more", "md_parent"]:
    let x = 70.0 + 110 * float(k)
    markersSvg.add "<path d=\"M" & $(x - 50) & ",30H" & $x & "\" stroke=\"currentColor\"/>"
    markersSvg.add erMarker(kind, x, 30, 1, 0)
  echo markersSvg.len, " bytes of SVG for five markers"

nbSvg "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"pele\" viewBox=\"0 0 560 60\" width=\"560\" height=\"60\" fill=\"none\" stroke=\"currentColor\">" &
  markersSvg.replace("var(--_bg)", "none") & "</svg>",
  "Exactly one, zero or one, one or more, zero or more, and Mermaid's parent marker."

nbText: """
## Entities as tables

An entity with attributes is drawn as a table: the name on top, then one row per attribute with
up to four columns (type, name, keys, comment), every other row shaded, and the last row rounded
to follow the box. The widths of the columns are the widest cell of each, and a box made wider by
its name shares the spare room between the columns. Types written with `~` are generics:
`List~int~` is shown as `List<int>`, by Mermaid's own rules for pairing the tildes
(`common/generics.ts`, ported with class diagrams just before this step), quirks included:
"""

nbCode:
  for t in ["List~int~", "Map~string,int~", "a~b~c~d", "~x"]:
    echo t, " -> ", parseGenericTypes(t)

nbText: """
Two more things happen after the layout. The layout brings every line that ends on one side of a
box to the middle of that side, where their markers would cover each other, so Pele spreads them
along the side, in the order they fan out. And a relationship from an entity to itself is a loop
off a side no other line uses: the right, or the bottom when the diagram runs across.

## Requirement diagrams

A requirement diagram comes from SysML, the systems engineering dialect of UML: *requirements*
(with an id, a text, a risk and a way to verify them) and the *elements* of a design that
satisfy, verify or refine them, joined by named relationships. Each node is a box with its kind
in guillemets, its name in bold, and its fields as a small two-column table:
"""

let reqText = """requirementDiagram
  requirement login {
    id: 1
    text: A user signs in with a password.
    risk: high
    verifymethod: test
  }
  element login_form {
    type: component
  }
  login_form - satisfies -> login
"""

nbText: &"""
```mermaid
{reqText.strip}
```
"""

nbCode:
  let reqSvg = render(reqText).svg
  echo reqSvg.len, " bytes, identical to Pele's: ", reqSvg == peleSvg(reqText)

nbSvg reqSvg, "A requirement and the element that satisfies it, drawn by nimaki."

nbText: """
Its lexer is small, but it has one trick: a line that holds `direction LR` anywhere is a
direction statement, whatever else is on it, because Mermaid's rule for it starts with `.*`. Pele
finds every such statement in one pass over the text before lexing, and the port does the same.

## How it was ported

The rule of the port is to translate, not to improve
([decision 0002](../../decisions/#0002-this-is-a-port-not-a-rewrite)).
"""

nbNote """
- **Bytes and code units.** Pele's lexer reads UTF-16 code units; the port reads UTF-8 bytes
  ([decision 0011](../../decisions/)). Where a run of characters is tested with `c >= 128`, the
  bytes give the same answer, since every byte of a character that is not ASCII is 128 or more.
  Where a single character is tested against a range (an attribute name may hold any letter from
  U+00C0 up, and the micro sign), the port reads the whole code point.
- **A requirement named `Requirement`.** The constant for the plain kind of requirement,
  `REQUIREMENT`, would be the same name as the type `Requirement` in Nim; it is `RT_REQUIREMENT`.
- **Arrays shared by reference.** `spreadEnds` keeps references to the routes of the edges and
  writes into them. In Nim a `seq` is a value, so the port keeps the edge's number and writes
  through it.
- **A name clash.** Nim names are the same whatever their case after the first letter, so the
  constant `LOOP` and the type `Loop` could not both exist; the type is `SelfLoop` here.
""", nkNim, "What changed in translation"

nbText: """
## The fuzzers

`tools/fuzz.nim` learned the ER grammar: relationships with every symbol and word form of
cardinality, both kinds of line, quoted and plain names, entities with aliases (`p[Person]`),
attribute blocks with generic types, keys and comments, subgraphs with titles and directions,
`classDef`, `class`, `:::`, `style`, self-relationships, comments, accessibility lines, front
matter with the spacing options, and broken lines on purpose. About a quarter of its inputs are
errors. It also learned the requirement grammar: the six kinds of requirement, elements, every
field and its keyword values, relationships written in both directions, self-relationships,
`classDef`, `class`, `:::`, `style`, and broken lines; there about two inputs in five are errors,
because the lexer refuses so much (a letter outside ASCII, for one). CI runs 5,000 of each on
every pull request:
"""

nbCode:
  for (kind, f) in [("er", fuzz), ("requirement", reqFuzz)]:
    echo "fuzz: ", kind, ", seed ", f["seed"].getInt, ", ", f["cases"].getInt, " cases: ",
      f["identical"].getInt, " identical, ", f["different"].getInt, " different"

nbNote """
The ER and requirement corpora, 5,000 generated diagrams of each on seed 1, and 9,000 more of
each on seeds 2 to 4: identical. The whole corpus, every ported type: no difference.
""", nkDone, "Checked"

nbNote """
- Every file is `draft` until a second reading against the TypeScript
  ([decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)).
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **ER and requirement are done** on the [roadmap](../../roadmap/) and the
  [coverage map](../../coverage/).
- Use case and agentflow come next in the same thread.

## Sources

- Pele at the pin: [`src/diagrams/er/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/er)
  and [`src/diagrams/requirement/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/requirement),
  read for this step.
- [Mermaid's entity relationship diagram syntax](https://mermaid.js.org/syntax/entityRelationshipDiagram.html)
  and [requirement diagram syntax](https://mermaid.js.org/syntax/requirementDiagram.html).
- P. P. Chen, *The Entity-Relationship Model: Toward a Unified View of Data*, ACM Transactions on
  Database Systems, 1976 ([doi:10.1145/320434.320440](https://doi.org/10.1145/320434.320440)).
  Not read for this post: cited for its date and subject only.
- The code of this step: [`src/nimaki/diagrams/er/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/er),
  [`src/nimaki/diagrams/requirement/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/requirement),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
