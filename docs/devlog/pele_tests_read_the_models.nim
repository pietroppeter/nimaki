## devlog: 14 Nov 2026 L | Pele's tests read the models | Pele's own tests can now call parse() on nimaki and read the model it returns: more of them pass, the rest wait for their type's model, and three types' models became Pele's.
## kind: port
import std/[strformat, strutils, json, osproc, os, tables, options]
import nimib
import ../blocks
import nimaki
from "nimaki/diagrams/block/db" import BlockDb
import ../../tools/models

nbInit
nb.usePost()

let tests = parseFile(docsDir / "data" / "peletests.json")["counts"]
proc count(k: string): int = tests{k}.getInt
# The counts before this step, from the commit it started from.
let before = parseJson(execCmdEx("git show 7d194091f2fc422cf5abb6154973f17baa032229:docs/data/peletests.json",
                                 workingDir = docsDir / "..").output)["counts"]
proc was(k: string): int = before{k}.getInt
let models = parseFile(docsDir / "data" / "parsediff.json")
var whole: seq[string]
for t in models["types"]:
  if t["different"].getInt == 0 and t["same"].getInt > 0: whole.add t["type"].getStr
var knownModel = 0
for line in lines(docsDir / ".." / "tools" / "peletests" / "known.txt"):
  if "\tknown\tmodel:" in line: inc knownModel

nbText: &"""
## The findings, first

- **Pele's tests can call `parse()` on nimaki.** The bridge that runs Pele's test suites on
  nimaki's JavaScript build (the post [*Pele's tests on nimaki*](../pele-tests-on-nimaki/)) now
  offers `parse(text)`, which returns nimaki's model written as a JavaScript object, and
  `render(model)`, which draws it. Before, both threw, and {was("api")} tests were set aside as
  *api*; now {count("api")} are, the ones that use `mount()` or zoom.
- **{count("passed") - was("passed")} more of Pele's tests pass**: {count("passed")} of the
  {count("passed") + count("api") + count("model") + count("unported") + count("speed") + count("canvas") + count("known") + count("failed")}
  that pass on Pele, against {was("passed")} before.
- **{count("model")} wait for their model.** A test that read a model of a type whose models
  are not all Pele's yet (the referee for models, `tools/parsediff.nim`, says which) is counted
  apart, as *model*, so that a red CI still means a mistake.
- **Three more types have Pele's models**: block, mindmap and ishikawa. {whole.len} types do now:
  {whole.join(", ")}.
- **The tests saw what the referee did not.** {knownModel} tests expect a title that is
  *undefined* where nimaki's is an empty text, which the referee reads as the same. And one of
  Pele's stress tests showed that nimaki's class parser, in JavaScript, runs out of memory on a
  namespace name of 12,000 parts.

## What a test asks of a model

The previous step, [*The model in between*](../the-model-in-between/), gave nimaki Pele's
`parse(text)`: it reads the text into the diagram's *model*, the structure that says what the
diagram holds, and gives it back without drawing it. Pele's tests use it a lot, because a model
says more precisely than a drawing whether the text was read right. A test of Pele's journey
diagram, for example:

```ts
const model = parse('journey\n  title T\n  First: 2\n  section S\n    A task: 5: Bob, Alice\n');
expect(model.title).toBe('T');
expect(model.sections).toEqual(['S']);
```

Pele's tests are JavaScript, and they run on nimaki through a *bridge*: a small Nim file,
`tools/peletests/bridge.nim`, compiled to JavaScript with the port, which offers Pele's functions
under Pele's names. For these tests to run, the bridge has to give them nimaki's model as a
JavaScript object, with Pele's field names and Pele's kinds of values.

## A Nim model, written as JavaScript

The referee for models already writes a nimaki model as JSON, field by field, the way Pele's is
written. That writing moved to a module of its own, `tools/models.nim`, so that the referee and
the bridge share it. The bridge then turns the JSON into JavaScript values: a Nim table becomes a
`Map`, as Pele's are, and a set a `Set`.

One thing JSON cannot say is that two places hold *the same* object. In a block diagram, the
block `a` is in the list `blocks` and also in the table `byId`, which finds a block by its name:
in Pele's model, and in nimaki's, it is one object in two places. Written out in full, it would
be two copies, and a model where everything points at everything (a namespace inside a
namespace inside a namespace, four thousand deep, in one of Pele's stress tests) grows with the
square of its size. So, for the bridge, the writing gives each object a number the first time it
meets it, and writes a reference to that number every other time:
"""

nbCode:
  let m = parse("block-beta\n  a b\n")
  let j = dumpModel(m, share = true)
  echo "blocks[0]: id ", j["blocks"][0]["id"], ", number ", j["blocks"][0]["$id"]
  echo "byId.a:    ", j["byId"]["$map"]["a"]

nbText: """
The bridge reads `{"$ref": n}` as the object numbered `n`, so the JavaScript model has one block
`a`, in both places, as Pele's has. The referee does not number anything: it compares values, and
writes each object in full, as the oracle writes Pele's.

Two more guards keep the stress tests from taking the test run down. A model nested thousands
deep is deeper than JavaScript lets a function call itself, and a model of millions of
characters is too large to hold twice; in both cases the test gets a model with only its `type`,
which it can still draw. A stress test asks whether `parse()` finishes in time, not what is
inside.

## Sorting what fails

Pele's tests that pass on Pele are sorted by what they do on nimaki (the verdicts of
`tools/peletests.nim`). A test that read a model of a type whose models are not Pele's yet is
expected to fail: the referee for models already says, field by field, where those models
differ. So such a test gets a verdict of its own, *model*, and does not fail CI. A test that
reads a model of a type the referee finds the same in every case, and fails, is an `ERROR`, as
any other difference: it means the referee missed something.
"""

block:
  let meaning = {"passed": "passes on nimaki too",
                 "api": "uses mount() or zoom",
                 "model": "reads a model that is not Pele's yet",
                 "unported": "draws a type nimaki does not draw",
                 "speed": "misses one of Pele's time limits",
                 "canvas": "tests the canvas measurer",
                 "known": "listed in tools/peletests/known.txt",
                 "failed": "anything else: an ERROR"}.toTable
  var rows: seq[string]
  for k in ["passed", "api", "model", "unported", "speed", "canvas", "known", "failed"]:
    rows.add &"| {k} | {meaning[k]} | {was(k)} | {count(k)} |"
  nbText: &"""
| verdict | what the test does | before | now |
|---|---|---|---|
{rows.join("\n")}

*Speed* grew too: stress tests that called `parse()` were set aside as *api* in a moment, and now
run, and nimaki's JavaScript build is slower than Pele (its C build is not the one tested here).
"""

nbText: """
## Three models brought to Pele's shape

For block, mindmap and ishikawa the referee listed fields nimaki had and Pele did not. They were
all the same kind of difference: Pele leaves a field *undefined* (in TypeScript, `columns?:
number`), and nimaki held a stand-in value instead, with a flag beside it:

- a block's `columns` was -1 for "not set", and its `colorIndex` 0; a block without a name had
  `hasId` false;
- a mindmap node's `section` was 0 for the root, which has none;
- the ishikawa reader kept `baseLevel` with a flag `hasBase`.

Nim has a type for "a value, or none": `Option`. Each of these became one, `none` where Pele's is
undefined, and the flags went (a block without a name is now one whose `id` is empty, until it
gets one, as in Pele). The code that draws reads `columns.get(-1)`, the value or -1, as Pele's
`block.columns ?? -1` does. The drawings did not change: difftest finds all of them the same
bytes as Pele's, in C and in JavaScript.
"""

nbCode:
  let blocks = BlockDb(parse("block-beta\n  columns 2\n  a\n  block:g\n    b\n  end\n").model)
  echo "root columns: ", blocks.root.columns
  for b in blocks.blocks: echo b.id, ": columns ", b.columns, ", colorIndex ", b.colorIndex

nbText: &"""
The referee also learned one name: `typ`, the usual Nim spelling of a field Pele calls `type`
(`type` is a Nim keyword), is read as `type`, as `kind` already was. And it can now list every
difference of a model, not only the first (`--all`), which is what it takes to bring a type to
Pele's shape in one go.

## What the tests saw that the referee did not

The referee reads an empty text and a missing one as the same, because nimaki writes `""` for a
text Pele leaves undefined. That is true for drawing, which treats the two alike. It is not true
for Pele's tests, which sometimes check that a title is undefined: {knownModel} tests of info,
journey, radar and timeline, four types the referee calls the same in every case, fail on it.
They are listed in `tools/peletests/known.txt`, with the reason, until those titles become an
`Option` too.

The other finding is a stress test of the class diagram: a namespace named `a.a.a. ... .b`, with
12,000 parts. Pele reads it within the test's time limit; nimaki, in JavaScript, runs out of memory.
A namespace with a dotted name is a namespace inside a namespace, and each one keeps its full
name (as its key in the table of namespaces, its `id`, and its children's `parent`), so the
names hold several times 12,000 × 12,000 / 2 characters together. JavaScript's own strings can share
the characters of a longer string they are cut from; in Nim's JavaScript build, where a string is
a list of numbers, each copy is its own, and together they are more memory than Node gives. Until `parse()` reached the bridge, this test stopped at once, and the problem was
not seen. It is listed as `skip` in `known.txt`, with that reason.
"""

nbNote """
- `tools/models.nim` writes a model as JSON for both the referee (`dumpModel(m)`) and the bridge
  (`dumpModel(m, share = true, budget = ...)`); it compiles with `nim js` too.
- The bridge (`tools/peletests/bridge.nim`) keeps, for each JavaScript model it returned, the
  Nim model it came from (in a `WeakMap`), so that `render(model)` draws the Nim model, not the
  JavaScript copy.
- A NaN of the model stays NaN for the tests (Pele's journey writes a score that is not a number
  as NaN); the referee still reads it as undefined.
""", nkNim, "In the port"

nbNote &"""
- Pele's suites on nimaki's JavaScript build, with the counts above, from the run this page was
  built with (`docs/data/peletests.json`).
- difftest, C and JavaScript: the drawings of block, mindmap and ishikawa are unchanged.
- The referee for models: block, mindmap and ishikawa the same as Pele's in every case.
""", nkDone, "Checked"

nbNote """
- The other types: most of their files are being changed by the step that writes the scanners
  with regular expressions, so they wait for it, to keep the two steps apart.
- A test that reads a model of a type the referee calls the same, and fails for a reason the
  referee does not see (as the titles), shows only when Pele's tests run.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- The roadmap's *Models as Pele's* goes on, type by type: each type brought to Pele's shape moves
  its tests from *model* to *passed*.
- An optional field of Pele's is an `Option` in the port. A stand-in value with a flag beside it
  is not Pele's shape, and the referee now shows it.
- The titles of info, journey, radar and timeline, and the memory of the class parser in
  JavaScript, are next on that step's list.

## Sources

- Pele's tests that read models, for example
  [`tests/render/journey.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/render/journey.test.ts)
  and the stress tests of
  [`tests/class/stress.test.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests/class/stress.test.ts).
- The block model with its optional fields: Pele's
  [`src/diagrams/block/types.ts`](https://github.com/obsidianmd/pele/blob/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/block/types.ts).
- The code: [`tools/models.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/models.nim),
  [`tools/peletests/bridge.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/peletests/bridge.nim),
  [`tools/parsediff.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/parsediff.nim).
"""

nbSave
