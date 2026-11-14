## devlog: 14 Nov 2026 O | Five ways a model differs | Twelve more diagram types now hold their models in Pele's shape; the differences came in five kinds, and each kind has one way to fix it.
## kind: port
import std/[strformat, strutils, json, osproc, options]
import nimib
import ../blocks
import nimaki
from nimaki/diagrams/treemap/model import TreemapModel, leaf
import ../../tools/models

nbInit
nb.usePost()

let modelData = parseFile(docsDir / "data" / "parsediff.json")
var whole, partly: seq[string]
for t in modelData["types"]:
  if t["different"].getInt == 0 and t["same"].getInt > 0: whole.add t["type"].getStr
  elif t["different"].getInt > 0: partly.add t["type"].getStr
let tests = parseFile(docsDir / "data" / "peletests.json")["counts"]
proc count(k: string): int = tests{k}.getInt
# The counts before this part, from the commit it started from.
let before = parseJson(execCmdEx("git show 4419107296cff3c93d1d909cd55cc497a00aca57:docs/data/peletests.json",
                                 workingDir = docsDir / "..").output)["counts"]
let beforeModels = parseJson(execCmdEx("git show 4419107296cff3c93d1d909cd55cc497a00aca57:docs/data/parsediff.json",
                                       workingDir = docsDir / "..").output)
proc was(k: string): int = before{k}.getInt

nbText: &"""
## The findings, first

- **{whole.len} of 33 types hold their models in Pele's shape**: {whole.join(", ")}. Before
  this part, {beforeModels["same"].getInt} models of the corpus were the same as Pele's; now
  {modelData["same"].getInt} are, and {modelData["different"].getInt} differ.
- **Pele's own tests agree**: {count("passed")} pass on nimaki (there were {was("passed")}), and
  {count("model")} wait for a model not yet in Pele's shape (there were {was("model")}).
- **The differences came in five kinds**, and each kind now has one way to be fixed, written down
  as [decision 0017](../../decisions/#0017-models-in-pele-s-shape): an `Option` for a field Pele may leave undefined, a
  pragma on a field the port has and Pele does not, a pragma on an object Pele spreads into
  another, a writer of Pele's shape for a value the port holds otherwise on purpose, and a
  renaming for Nim's keywords.
- **Left**: {partly.join(", ")}. Their models are the largest, and the next part.

## Why the shape of a model matters

The post [*Pele's tests read the models*](../pele-tests-read-the-models/) gave Pele's own tests a
`parse()` on nimaki: it returns the *model*, the structure a diagram's text is read into, and the
tests look inside it. A test of Pele's knows Pele's model: the names of its fields, which of them
can be missing, what is a list and what is a table. Where nimaki's model is shaped otherwise, the
test fails, even when the drawing is the same bytes.

The referee for models, `tools/parsediff.nim`, says where. Its new option `--all` lists every
difference of every case, which is what it takes to fix a type in one go. Going through the types
one by one, the same five kinds of difference came back again and again.

## 1. Undefined, or a stand-in

TypeScript can say that a field may be missing: `children?: TreemapNode[]`. In a treemap, a
section has a list of children, which can be empty, and a leaf has none at all. The port had a
list for both, and a flag `leaf` to tell them apart: two fields where Pele has one.

Nim has a type for "a value, or none": `Option`. The treemap's `children` is now an
`Option[seq[TreemapNode]]`, `none` for a leaf, and `leaf` is no longer a field but a function that
asks `children.isNone`. The same change went to venn's labels, wardley's pipeline flags and
gitGraph's `customType` and `customId`, which held -1 or `false` for "not given".
"""

nbCode:
  let tree = TreemapModel(parse("treemap-beta\n\"Fruit\"\n  \"Apple\": 3\n  \"Empty\"\n").model)
  let fruit = tree.roots[0]
  echo fruit.name, ": a leaf? ", fruit.leaf, ", children ", fruit.children.get.len
  for c in fruit.children.get: echo "  ", c.name, ": a leaf? ", c.leaf, ", children ", c.children

nbText: """
## 2. A field of the port's own

Some fields Pele does not have at all, because the port added them for itself: an event modeling
box keeps `order`, its place in the list of boxes, where Pele keys a table by the box itself. Such a
field now says so, with a *pragma*, a note on a field that Nim keeps and a program can read:

```nim
order* {.portOnly.}: int
  ## Its place in `boxes`: nimaki's key where Pele keys a Map by the box itself.
```

`tools/models.nim` leaves a `portOnly` field out of the model it writes. The pragmas live in a new
file, `src/nimaki/model.nim`, which says what each means.

## 3. Spread into another

JavaScript can *spread* an object into another: `{ ...built, title }` makes one object of the
fields of `built` and a `title`. Pele's wardley model is made that way, and so is its quadrant
point, which extends its style. The port keeps the inner object as one field, so a second pragma,
`{.spread.}`, says to write its fields as the outer object's own. Wardley went from no model the
same as Pele's to all of them, with that one word.

## 4. A shape of its own, on purpose

Some differences are wanted. A railroad diagram's node is, in Pele, one of seven shapes, a
*union*: a terminal with a `value`, a sequence with `elements`, a choice with `alternatives`, a
repetition with an `element`, a `min` and a `max`. Nim's version of a union, an object whose fields
depend on its kind, cannot give two kinds a field of the same name, so the port holds all seven as
one object with a kind and its children in `kids`. Changing that would make the port harder to
read for nothing.

So `tools/models.nim` has, for such a type, a small writer of Pele's shape, with a comment saying
why the port holds it otherwise. There are five so far: the railroad node, the packet's label
(boxed so that the pieces of a field split over 10,000 rows share it, as JavaScript shares a
string), the quadrant chart's label (a flag for "defined" read in many places), and the xychart's
axis and plot (a union of a band axis and a linear one, and a flag for the plot's type):
"""

nbCode:
  let rail = dumpModel(parse("railroad-beta\nlist = item (\",\" item)*\n"))
  echo rail["rules"][0]["definition"]

nbText: """
The writer also learned two things JavaScript does. A pair, which Nim writes as a tuple, is an
array in JavaScript (the xychart's `["jan", 12]`), and a number without bound is `Infinity` (a
repetition's `max`).

## 5. Names Nim keeps for itself

`type`, `from`, `end` are words of Nim's own, so the port names those fields otherwise (`kind`,
`start`, `stop`), and `tools/models.nim` renames them back. One type had a real field named `kind`
that the general rule turned into `type`: the event modeling box, where `kind` is Pele's own name.
The table of renamings for one type now puts it back.

## The rule, written down

A later session porting a field would face the same choice: change the model, or change how it is
written. [Decision 0017](../../decisions/#0017-models-in-pele-s-shape) says which, in that order: an `Option` first, a
pragma for what is the port's own or spread, a writer in `tools/models.nim` only for a shape kept on
purpose, with its reason.
"""

nbNote """
- `src/nimaki/model.nim`: the pragmas `portOnly` and `spread`.
- `tools/models.nim`: the writers of Pele's shape (railroad node, packet label, quadrant label,
  xychart axis and plot), pairs as arrays, `Infinity`, YAML and JSON values read from the text
  (flowchart's metadata and edge animation) as plain objects.
- The models changed: treemap, venn, sankey (a link holds its nodes, as Pele's does, and the
  layout reads their `index`), wardley, gitGraph, railroad (it keeps Pele's `byName`), cynefin
  (an item is an object with a `label`), quadrant, eventmodeling.
""", nkNim, "In the port"

nbNote """
- difftest, in C and in JavaScript: every drawing still the same bytes as Pele's.
- The referee for models and Pele's test suites, with the counts above, from the run this page was
  built with.
""", nkDone, "Checked"

nbNote """
- The eight types left have the largest models (sequence, state, class...) and are the next part.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- A model's type says where it is not Pele's, and how: `Option`, `portOnly`, `spread`, or a writer
  in `tools/models.nim`, as decision 0017 says.
- *Models as Pele's* goes on with agentflow, architecture, c4, class, gantt, sequence, state and
  usecase.

## Sources

- Pele's models, for example the treemap's
  [`src/diagrams/treemap/model.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/treemap/model.ts)
  and the railroad's union, [`src/diagrams/railroad/types.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/railroad/types.ts).
- Spread syntax in JavaScript: [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax).
- The code: [`tools/models.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/models.nim),
  [`src/nimaki/model.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/model.nim).
"""

nbSave
