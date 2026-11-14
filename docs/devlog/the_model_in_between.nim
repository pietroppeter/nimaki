## devlog: 14 Nov 2026 K | The model in between | nimaki now exports parse() and render(model) as Pele does, and a new referee compares the models the two read from the same text, and lists what differs.
## kind: port
import std/[strformat, strutils, json, os, osproc]
import nimib
import ../blocks, ../pele
import nimaki
from nimaki/diagrams/pie/model import PieModel
import ../../tools/parsediff

nbInit
nb.usePost()

let data = parseFile(docsDir / "data" / "parsediff.json")
let cases = data["cases"].getInt
var whole, partly, none: seq[string]
for t in data["types"]:
  let name = t["type"].getStr
  let same = t["same"].getInt
  let different = t["different"].getInt
  if different == 0 and same > 0: whole.add name
  elif same > 0: partly.add name
  else: none.add name

nbText: &"""
## The findings, first

- **parse() and render(model).** Pele's API has two steps that its `render(text)` hides:
  `parse(text)` reads the text into the diagram's *model*, and `render(model)` draws a model.
  nimaki's entry point now has both, as Pele's has. On every input of the corpus,
  {cases} of them, drawing the parsed model gives the same SVG (or the same error) as drawing
  the text.
- **A referee for models.** `tools/parsediff.nim` asks Pele for the model of every input, asks
  nimaki for its own, writes both as JSON and compares them. {data["same"].getInt} models are the
  same, {data["error"].getInt} inputs are refused by both with the same error, and
  {data["different"].getInt} models differ.
- **{whole.len} types already match in full.** For {whole.join(", ")}, every model is Pele's.
  {partly.len} more match in part, and {none.len} not at all yet.
- **The differences are shapes, not mistakes.** The drawings are the same bytes, so the
  differences are in how the port holds a model: a field it adds, a union of shapes written as
  one object with a `kind`, a field it names otherwise. The referee lists
  them, so that each type can be brought to Pele's shape, which is what Pele's tests read.

## What a model is

Drawing a diagram is two jobs. The first is *reading*: the text is cut into words, the words into
statements, and the statements build a structure that says what the diagram holds, the
**model**: for a pie, its title and its slices; for a flowchart, its nodes, its edges and its
subgraphs. The second is *drawing*: the model is laid out and written as SVG. The model is the
line between the two.

Pele's `render(text)` does both jobs at once. Its `parse(text)` does only the first and gives
the model back, so a program can look inside it: count the nodes, check a label, or change
nothing and draw it later, many times, without reading the text again. Pele's own tests do
that a lot. In nimaki the model was always there, inside `render`; now it comes out:
"""

nbCode:
  let m = parse("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n")
  echo m.diagramType, " (Mermaid calls it ", m.mermaidType, ")"
  let pie = PieModel(m.model)
  echo "title: ", pie.title
  for label, value in pie.sections: echo "  ", label, ": ", value
  echo "drawn: ", render(m).svg.len, " bytes of SVG, the same as from the text: ",
    render(m).svg == render("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n").svg

nbText: """
The model has the type its diagram declares, here a `PieModel` (in `diagrams/pie/model.nim`), as
Pele's has the `PieModel` of `diagrams/pie/model.ts`. Pele returns the model itself, with its
Mermaid type added to it; nimaki returns a `ParsedModel` that holds it, beside the diagram's type
and Mermaid type. The options read while parsing (`limit`, `maxEdges`, `config`) count in `parse`,
and are not read again by `render(model)`, as in Pele.

## Two models, compared

To compare two models they must be written the same way. Pele's is a JavaScript object, and
JSON is its natural form, except that `JSON.stringify` loses what JSON has no word for: a `Map`
comes out as `{}`. So the oracle, `tools/oracle.mjs`, writes a model with a small function of its
own, which keeps a Map's entries and a Set's items. nimaki's model is a Nim object, and the
referee walks it field by field (Nim's `fieldPairs`, which visits every field of an object at
compile time) into the same JSON. Then a few rules make the two comparable:

- a field that is empty on one side and missing on the other is the same (nimaki writes `""` for
  a text Pele leaves undefined, `NaN` for a number, and an empty list for a missing one);
- a field Nim cannot name as Pele does is read with Pele's name: `type` is a Nim keyword, so the
  port says `kind`; `end` is one too, so the port says `stop`;
- an enum's value is read without its prefix: Nim's `skState` is Pele's `"state"`.

Here is a model as Pele writes it, and as nimaki does, after the rules:
"""

nbCode:
  let text = "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n"
  echo "nimaki: ", normal(dumpModel(parse(text)))

let peleModel = parseJson(execCmdEx("node " & (docsDir / ".." / "tools" / "oracle.mjs"),
  input = $(%*{"id": "pie", "source": "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n",
               "parse": true}) & "\n").output)["model"]
nbText: &"""
```json
{normal(peleModel)}
```

The first is nimaki's, the second Pele's (with its own `type` and `mermaidType`, which the
referee compares apart). They are the same.
"""

var rows: seq[string]
for t in data["types"]:
  rows.add &"| {t[\"type\"].getStr} | {t[\"same\"].getInt} | {t[\"different\"].getInt} | {t[\"error\"].getInt} |"

nbText: &"""
## What the referee says

Per type: the models that are the same, those that differ, and the inputs both sides refuse with
the same error.

| type | same | different | both refuse |
|---|---|---|---|
{rows.join("\n")}
"""

nbText: """
The first difference of each model is in `build/parsediff/report.json`. The most common, in the
run this post was built with:

- **a field the port adds.** Sequence messages carry `isNumbering`, where Pele's `message` holds
  either a text or a numbering object (a JavaScript field can hold either; a Nim field cannot).
- **one object for a union.** A railroad node is, in Pele, one of seven shapes (a terminal with a
  `value`, a sequence with `elements`, a choice with `alternatives`...); the port holds all seven
  as one object with a `kind`, and the children in one field, `kids`. The porting notes of the
  file say so.
- **a name moved.** Where a type's own words were taken by Nim, or the port chose a shorter one.

None of these changes a drawing: the referee for drawings finds every case identical. They
matter for what reads a model, which so far is only the port itself.
"""

nbNote """
- `parse(text, options)` and `render(model, options)` are in `src/nimaki/core.nim` (the port of
  Pele's `src/core.ts`); `tests/test_parse.nim` checks, on every corpus input, that drawing the
  parsed model is drawing the text, and that drawing a model twice gives the same SVG twice.
- The referee is `tools/parsediff.nim`; its summary is `docs/data/parsediff.json`.
""", nkNim, "In the port"

nbNote &"""
- `render(parse(text))` gives what `render(text)` gives on all {cases} corpus inputs.
- The model referee's counts above, from the run this page was built with.
""", nkDone, "Checked"

nbNote """
- The referee compares a model's fields and values, not their JavaScript types: a Map and an
  object with the same entries are the same to it, and an empty text equals a missing one.
- Pele's tests that read a model do not run on the port yet: for the types whose models differ,
  each needs its model brought to Pele's shape first, which is a step per type.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- diagrammari, and any program, can read a diagram without drawing it, through `parse`.
- The roadmap has a new step, *Models as Pele's*: bring each type's model to Pele's shape, type
  by type, until `tools/parsediff.nim` finds every model the same. Then Pele's tests that read
  models can run on the port.

## Sources

- Pele's `parse` and `render`: [`src/core.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/core.ts).
- The port: [`src/nimaki/core.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/core.nim),
  the referee [`tools/parsediff.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/parsediff.nim),
  the test [`tests/test_parse.nim`](https://github.com/pietroppeter/nimaki/blob/main/tests/test_parse.nim).
"""

nbSave
