## devlog: 12 Nov 2026 T | Boxes with sections: class diagrams | nimaki draws Mermaid's class diagrams byte for byte as Pele does: a lexer with thirteen states, a model of classes, members and namespaces, ends spread along the sides of a box, and a narrow screen that gets the diagram in rows.
## kind: port
import std/[strformat, strutils, json, tables, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/diagrams/class/[lexer, members, tokens]
import nimaki/diagrams/common/generics

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
for r in difftest["types"]: cases[r["type"].getStr] = r["cases"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]

nbText: &"""
## The findings, first

- **Class diagrams are done.** The {cases["class"]} corpus cases of class come out of nimaki
  identical to Pele's, byte for byte, and so do {fuzz["class"]["cases"].getInt.thousands} generated
  ones that CI now writes on every pull request.
- **It ported in one pass.** Ten files, about 2,100 lines of TypeScript: lexer, parser, model,
  graph, markers and renderer, plus two shared files, `layout/components.ts` and
  `common/generics.ts`. The renderer sits on the compound layout the flowchart thread ported, so
  nothing below it was new.
- **The lexer is a machine with thirteen states.** What a character means depends on where it
  is: inside a class body every line is a member, inside `~` a generic type, after `call` a
  callback name. Pele writes it as one loop with a switch on the state, and so does the port.
- **Two Nim surprises, both about names.** `LINE` (the colour of a line) and `Line` (a member's
  line of text) are the same name to Nim, which ignores case after the first letter; and
  `include` is a keyword. Both became compile errors, not wrong output.

## What a class diagram is

A *class diagram* comes from UML, the Unified Modeling Language: it draws the types of a program
and how they relate. Each class is a box in three sections: its name, its *attributes* (the
data it holds) and its *methods* (what it can do). A sign before a member says who may use it:
`+` public, `-` private, `#` protected, `~` package. The lines between boxes say how two classes
relate: a hollow triangle is *inheritance* (a duck is an animal), a filled diamond is
*composition* (an order is made of its lines, which do not outlive it), a hollow diamond is
*aggregation*, a dashed arrow a *dependency*. The numbers at the ends, the *cardinalities*, say
how many of each take part.
"""

let classText = """classDiagram
  class Animal {
    +String name
    +int age
    +makeSound() void
  }
  class Duck {
    +swim()
  }
  class Fish {
    -int sizeInFeet
    -canEat() bool
  }
  Animal <|-- Duck
  Animal <|-- Fish
  class Order
  class Line
  Order "1" *-- "many" Line : contains
  class Payment~T~
  class Card
  Payment <|.. Card
"""

nbText: &"""
```mermaid
{classText.strip}
```
"""

nbCode:
  let classSvg = render(classText).svg
  echo "identical to Pele's: ", classSvg == peleSvg(classText)

nbSvg classSvg, "Three small families of classes, drawn by nimaki; Pele draws the same bytes."

nbText: """
## Reading it: a lexer with states

The [flowchart post](../layered-layout-and-flowchart/) and the [timeline post](../timeline/)
explained a *lexer*: the first stage of reading, which cuts the text into *tokens*, words with
a kind. Mermaid's class grammar is written for Jison, a parser generator, and its lexer has
*start conditions*: states in which different rules apply. The same character means different
things in different states. A `}` closes a class body; inside a string it is just a character.
A line inside `class Duck { ... }` is a member, whatever it holds, so `+swim()` is one token,
not a plus, a word and two brackets.

Pele's `lexer.ts` writes the thirteen states as one loop that looks at the current state and the
next character, and a stack of states to return to. Here are the tokens of a small class, from
the port:
"""

nbCode:
  let small = "classDiagram\nclass Duck~T~ {\n  +swim() bool\n}\nDuck <|-- Mallard : is a"
  let toks = tokenize(small)
  for k in 0 ..< toks.types.len:
    let text = toks.texts[k].replace("\n", "\\n")
    echo TOKEN_NAMES[toks.types[k]].alignLeft(16), " ", text

nbText: """
The `~` in `Duck~T~` switched to the *generic* state, which read `T` as one `GENERICTYPE`; the
`{` switched to the class body, where the whole line `+swim() bool` became one `MEMBER`. The
parser then splits a member the way Mermaid does: a sign, a name, parameters in brackets, and a
return type after them. A `$` at the end makes it *static* (underlined), a `*` *abstract*
(italic):
"""

nbCode:
  for text in ["+swim() bool", "-int sizeInFeet", "+getAll(List~T~ items) Map~K, V~", "count()$", "+area()* double"]:
    let m = newClassMember(text, if ')' in text: "method" else: "attribute")
    let shown = m.getDisplayDetails()
    echo text.alignLeft(34), " → ", shown.displayText,
      (if shown.cssStyle != "": "   (" & shown.cssStyle & ")" else: "")

nbText: """
Mermaid writes generic types with tildes, because `<` and `>` mean other things in its
grammar; `List~int~` is drawn `List<int>`. `parseGenericTypes` pairs the tildes from the outside
in, with a few quirks around commas that Pele keeps for Mermaid's sake:
"""

nbCode:
  for text in ["List~int~", "Map~K, V~", "List~List~int~~", "~odd~one~"]:
    echo text.alignLeft(18), " → ", parseGenericTypes(text)

nbText: """
## Laying it out

A class diagram is laid out by the compound layout, the one flowchart uses for its subgraphs:
namespaces are groups, classes and notes are nodes. Two things are its own.

**Ends spread along a side.** A class with many relations would have them all meet the middle of
its top side, one on top of the other. So the renderer first widens a class until its edges, and
the cardinalities written beside their ends, fit side by side, then sets the ends apart along
the side, in the order of where each line comes from, and keeps the end of each line straight
for the length of its text, so the text sits beside a straight piece of line.

**Parts in rows, for a narrow screen.** A diagram is often several separate families of classes
with no line between them, like the one above. On a phone, laid out side by side, they would be
too wide. `layout/components.ts` finds the *connected components* (the groups of boxes that
lines join, found with a *union-find*: each box points to a representative, and joining two
groups points one representative at the other), and when the diagram does not fit the width it
moves whole components into rows, like words into lines of text, without touching the layout
inside each:
"""

nbCode:
  let narrow = render(classText, RenderOptions(maxWidth: some(390.0)))
  echo "wide: ", render(classText).width, " px; at 390: ", narrow.width, " px, identical to Pele's: ",
    narrow.svg == peleSvg(classText, %*{"maxWidth": 390})

nbSvg narrow.svg, "The same diagram for a phone: the three families in rows."

nbNote """
Pele's `ClassMember` finds the parts of a method in one pass where Mermaid uses a regular
expression, `/([#+~-])?(.+)\((.*)\)([\s$*])?(.*)([$*])?/`. The port follows Pele's pass. It
works on UTF-8 bytes; every place where Pele looks at one UTF-16 code unit (a sign, a bracket, a
`$`) looks at an ASCII character, so the bytes give the same answer, and the one place where a
character may be a space of any kind steps over the whole character. Maps are ordered tables, so
classes, notes and namespaces keep the order they were written in, as a JavaScript `Map` does.
""", nkNim, "In the port"

nbNote &"""
The {cases["class"]} corpus cases of class: identical. Generated inputs before merging: 2,000,
3,000 and twice 5,000 class diagrams on four seeds, identical, with members of every kind,
generics, every relation and cardinality, namespaces (nested and dotted), notes, lollipop
interfaces, styles, `classDef`, links and callbacks, configuration, and narrow widths that wrap
the components; about three in four draw a diagram and the rest test the error messages. CI runs
{fuzz["class"]["cases"].getInt.thousands} on every pull request.
""", nkDone, "Checked"

nbNote """
- Pele's compat specs for class (ported from Mermaid, in `tests/compat/class/`) check the model;
  they are not ported, the corpus and the fuzzer check the drawing.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Class is done** on the [coverage map](../../coverage/) and the [roadmap](../../roadmap/), and
  with lanes and components the shared layouts are all ported: layered, compound, lanes and
  components.
- **`common/generics.nim`** is ready for the other types that read `~` generics.
- **Next, in this thread:** the next unclaimed types on the roadmap.

## Sources

- Pele at the pin: [`src/diagrams/class/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/class),
  [`src/layout/components.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/layout/components.ts),
  [`src/diagrams/common/generics.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/common/generics.ts),
  read for this step.
- Mermaid's syntax: [class diagrams](https://mermaid.js.org/syntax/classDiagram.html).
- Jison's [lexical analysis and start conditions](https://gerhobbelt.github.io/jison/docs/#lexical-analysis).
- The code of this step: [`src/nimaki/diagrams/class/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/class),
  [`src/nimaki/layout/components.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/layout/components.nim),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
