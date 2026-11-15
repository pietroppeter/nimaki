## devlog: 14 Nov 2026 R | Where each statement sits | The last eight diagram types now hold their models in Pele's shape, so every model of the corpus is Pele's; on the way, nimaki learned to record where each statement sits and what Pele warns about.
## kind: port
import std/[strformat, strutils, json, osproc]
import nimib
import ../blocks
import nimaki
from nimaki/diagrams/usecase/types import UsecaseModel
from nimaki/diagrams/agentflow/db import AgentflowDb

nbInit
nb.usePost()

let modelData = parseFile(docsDir / "data" / "parsediff.json")
var whole: seq[string]
for t in modelData["types"]:
  if t["different"].getInt == 0 and t["same"].getInt > 0: whole.add t["type"].getStr
let tests = parseFile(docsDir / "data" / "peletests.json")["counts"]
proc count(k: string): int = tests{k}.getInt
# The counts before this part, from the commit it started from (the head of part 2).
let before = parseJson(execCmdEx("git show 59da7544e3f6eaa78f87475d402e7298ceadf15d:docs/data/peletests.json",
                                 workingDir = docsDir / "..").output)["counts"]
let beforeModels = parseJson(execCmdEx("git show 59da7544e3f6eaa78f87475d402e7298ceadf15d:docs/data/parsediff.json",
                                       workingDir = docsDir / "..").output)
proc was(k: string): int = before{k}.getInt

nbText: &"""
## The findings, first

- **Every model of the corpus is Pele's.** All {whole.len} types hold their models in Pele's
  shape: {modelData["same"].getInt} models of the corpus are the same as Pele's, and
  {modelData["different"].getInt} differ (before this part, {beforeModels["same"].getInt} and
  {beforeModels["different"].getInt}). The other {modelData["error"].getInt} inputs are
  refused by both, with the same error.
- **Pele's own tests agree**: {count("passed")} pass on nimaki (there were {was("passed")}), and
  {count("model")} wait for a model not yet in Pele's shape (there were {was("model")}).
- **Two things Pele records for editors are now ported**: where each statement of a use case
  diagram sits in the text, and where each element of an agentflow sits, with the warnings Pele
  gives about it (a shape agentflow does not draw, a loop of containers). The port had left them
  out, because nothing drawn reads them; Pele's model has them, and so its tests read them.
- The other six types needed only the five fixes of the
  [previous post](../five-ways-a-model-differs/), as
  [decision 0018](../../decisions/#0018-a-model-is-pele-s-field-for-field-or-says-how-it-differs)
  says.

## What an editor needs

A program that shows a diagram beside its text, as Obsidian does, wants more than the drawing.
When the reader clicks a box, the editor should jump to the line that made it; when the text has
a problem, it should underline the place. For that, the parser must remember *where* each part of
the text was: a *position*, often given as a pair of numbers, the offset where it starts and the
one where it ends.

Pele keeps such positions on two models. A use case diagram's model has `statements`, one entry
per line of the text, each with its `span` (start and end offsets) and the spans of its parts: the
name of an actor, its label, the label of an arrow. An agentflow's model has `mappings`, where
each element starts and ends, as a line and a column.

The port now records both. Here is a small use case diagram and its statements:
"""

nbCode:
  let text = "usecase-beta\nPay[Pay 5 €]\nUser --> Pay"
  let useCases = UsecaseModel(parse(text).model)
  for s in useCases.statements:
    echo s.statementKind, " from ", s.span[0], " to ", s.span[1]
  echo "bytes before the third line: ", text.find("User")

nbText: """
## Counting like JavaScript

The edge starts at 26, yet 28 bytes come before it. Both numbers are right, in their own units.

Text in a computer is a list of numbers. Nim keeps a string as UTF-8, where a character takes one
to four *bytes*: `P` takes one, `€` takes three. JavaScript keeps a string as UTF-16, where a
character takes one or two *code units* of 16 bits each: `P` takes one, and so does `€`. An offset
in Pele is a count of code units, so the euro sign counts once there and three times in Nim.

The port's parser reads bytes, as all of its parsers do. Once the text is read, the positions it
recorded are turned into Pele's: a table gives, for each byte, how many code units come before
it. Text that is all ASCII (one byte, one code unit) skips the step.

The agentflow positions needed no such step: they count lines and columns, and the port's lexer
already counted columns in code units, as Pele's error messages need.

## Warnings on the model

Pele does not stop at every problem. When an agentflow names a shape it does not draw, it draws
the default one and records a *diagnostic* on the model: what went wrong, how bad it is (a
warning or an error), on which element, and where that element sits in the text. The port drew the
same default and kept quiet; now it records the same diagnostic:
"""

nbCode:
  let flow = AgentflowDb(parse("agentflow-beta\nflow f[\"F\"]\n  a[\"A\"]@{ shape: rounded }\nend\n").model)
  for d in flow.diagnostics:
    echo d.severity, " ", d.id, " on ", d.nodeId, " (line ", d.position.startLine, "): ", d.message
  for m in flow.mappings:
    echo m.kind, " ", m.id, ": lines ", m.position.startLine, " to ", m.position.endLine

nbText: """
Pele builds the drawing's graph while parsing, and building it is what finds these problems: so
`parse()` already returns them, before anything is drawn. The port does the same.

## The other six

The rest was the five kinds of difference again:

- **A union held as one object with a kind.** A state diagram's statements are, in Pele, one of
  eight shapes (a state, a relation, a class definition, a direction...) or a bare string; a
  sequence diagram's messages are a signal, a note or an autonumber statement. The port holds
  each as one object with a tag, so `tools/models.nim` has a writer of Pele's shapes for them. A c4
  element keeps its optional texts (`descr`, `techn`, the colours) in a table; its writer puts them
  back as fields, with the named arguments Pele keeps aside in `extra`, which the port now keeps too.
- **A stand-in value.** A class relation's end is a number or the text `'none'`; the port held
  `'none'` as -1, and now writes `'none'`. Flags that Pele sets only when true (a class's
  `haveCallback`, an agentflow connector's `isConnector`) became `Option[bool]`.
- **A set.** Pele keeps, for each style class, the `Set` of classes that use it. A set needs to
  tell its members apart; for objects, Nim's sets would hash their addresses in memory, which the
  JavaScript build does not have. A class's id is unique, so the classes are hashed by their id.
- **The empty text for "none".** Many fields that Pele leaves undefined were `""` in the port
  (an actor's icon, a relation's label, a state's direction): they got `{.undefinedIfEmpty.}`.
- **Names.** A use case statement has a `kind` of Pele's own, next to elements whose Pele `type`
  the port names `kind`: the statement's is `statementKind`, renamed back by the table of the type.

## A model that does things

Once every model was the same as Pele's, a dozen of Pele's tests failed that had been waiting
for one. They did not read the model: they *called* it. In TypeScript a model can be an object of
a class, with *methods*, functions that belong to it: a gantt's `getTasks(now)` schedules its
tasks for a given day, an agentflow's `semanticModel()` gives what the diagram means without how
it looks, and a state diagram's `direction` is worked out when asked.

The model a test gets is JSON turned into a JavaScript object, which has fields and no methods.
So the bridge to Pele's tests now gives those models their methods: each one calls the port's own
procedure on the Nim model the JSON was written from, and writes its answer back (a gantt's dates
as JavaScript `Date` objects, as Pele's are). The agentflow's semantic model, which the port had
left out, is ported for it. One of Pele's tests even runs Pele's own graph builder on the model,
which calls the model's `subgraph`, `vertexKind` and `emitWarning`: those are there too, and it
passes.
"""

nbNote """
- `src/nimaki/diagrams/usecase/parser.nim`: the statements with their positions, in UTF-16 code
  units. `labelType` ('text' or 'markdown') where the port had a `markdown` flag.
- `src/nimaki/diagrams/agentflow/`: the element mappings, the diagnostics (with Pele's rule of
  recording each finding once), the semantic model, and Pele's `type: 'flow'` on a container.
  An edge's `style`, the default edge style and a node's `props` are `Option`s, as Pele leaves
  them undefined until a statement sets them.
- `tools/peletests/`: the methods of Pele's models, through `nimakiModelCall` in the bridge.
- `tools/models.nim`: writers of Pele's shapes for the state statement, the sequence message and
  note, the c4 element and relation, the class relation, the usecase JSON value and style list, and
  the agentflow set of mappings.
- Smaller: gantt and architecture (their unions and dates), class's constants `lineType` and
  `relationType`, which Pele keeps on the model.
""", nkNim, "In the port"

nbNote """
- difftest, in C and in JavaScript: every drawing still the same bytes as Pele's.
- The referee for models on the whole corpus, and Pele's test suites, with the counts above, from
  the run this page was built with.
""", nkDone, "Checked"

nbNote """
- `parsediff --strict`, which tells an empty text from a missing one as Pele's tests do, still
  finds differences in some of the types of the earlier parts. Pele's tests have not failed on
  them; the next one that does says which.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- Every diagram type's `parse()` returns Pele's model, field for field, or says how it differs,
  as decision 0018 says. The roadmap step *Models as Pele's* is done.
- The positions and diagnostics make the port ready for an editor: the
  [proposal for diagrammari](../a-proposal-for-diagrammari/) can count on them.

## Sources

- Pele's use case statements, [`src/diagrams/usecase/types.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/usecase/types.ts),
  and the agentflow's mappings and diagnostics,
  [`src/diagrams/agentflow/db.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/agentflow/db.ts).
- How JavaScript counts a string: [MDN, UTF-16 characters](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String#utf-16_characters_unicode_code_points_and_grapheme_clusters).
- The code: [`tools/models.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/modeljson.nim) (since 15 November `src/nimaki/modeljson.nim`).
"""

nbSave
