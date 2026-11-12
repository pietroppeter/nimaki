## The data the living pages share: the coverage map (`docs/data/coverage.json`, seeded by
## `tools/coverage_seed.nim`) and the roadmap (`docs/data/roadmap.json`). Pages read them here,
## so the home page, the roadmap and the coverage map always agree.
import std/[json, os, strutils]
import blocks

type
  Part* = object
    ## One cell of the coverage map: a stage of a diagram type, or a part of the core.
    code*: int
    status*: Status
  CorePart* = object
    ## A part of Pele shared by every diagram type (text, svg, layout...).
    id*, what*, nim*, post*, notes*: string
    code*: int
    status*: Status
  DiagramType* = object
    ## A diagram type of Pele, in three stages.
    id*, nim*, post*, notes*: string
    code*, tests*, corpus*: int
    parse*, layout*, render*: Part
  Coverage* = object
    pin*: Pin
    core*: seq[CorePart]
    diagrams*: seq[DiagramType]
  Step* = object
    ## A step of the roadmap: a well defined task that ships with an explainer.
    id*, kind*, title*, what*, post*, pr*: string
    doneWhen*: string   ## the test the step must pass, or ""
    owner*: string      ## the thread that claimed the step, or ""
    status*: Status
  Phase* = object
    id*, title*, goal*: string
    steps*: seq[Step]
  Milestone* = object
    ## A point where the port can prove something about itself: reached `after` a phase, by `proof`.
    id*, title*, after*, proof*: string

const dataDir = docsDir / "data"

proc toPart(j: JsonNode): Part = Part(code: j["code"].getInt, status: toStatus(j{"status"}.getStr))

proc loadCoverage*(): Coverage =
  let j = parseFile(dataDir / "coverage.json")
  result.pin = pin
  for c in j["core"]:
    result.core.add CorePart(id: c["id"].getStr, what: c["what"].getStr, nim: c{"nim"}.getStr, post: c{"post"}.getStr,
                             notes: c{"notes"}.getStr, code: c["code"].getInt, status: toStatus(c{"status"}.getStr))
  for d in j["diagrams"]:
    result.diagrams.add DiagramType(id: d["id"].getStr, nim: d{"nim"}.getStr, post: d{"post"}.getStr,
                                    notes: d{"notes"}.getStr, code: d["code"].getInt, tests: d["tests"].getInt,
                                    corpus: d["corpus"].getInt, parse: d["parse"].toPart,
                                    layout: d["layout"].toPart, render: d["render"].toPart)

func status*(d: DiagramType): Status =
  ## A type is done when its three stages are; started when any is begun.
  if d.parse.status == stDone and d.layout.status == stDone and d.render.status == stDone: stDone
  elif stBlocked in [d.parse.status, d.layout.status, d.render.status]: stBlocked
  elif [d.parse.status, d.layout.status, d.render.status] != [stPlanned, stPlanned, stPlanned]: stStarted
  else: stPlanned

func tsCode*(c: Coverage): int =
  ## Lines of TypeScript to port: the core and every diagram type.
  for p in c.core: result += p.code
  for d in c.diagrams: result += d.code
func portedCode*(c: Coverage): int =
  ## Lines of the parts and stages that are done.
  for p in c.core:
    if p.status == stDone: result += p.code
  for d in c.diagrams:
    for s in [d.parse, d.layout, d.render]:
      if s.status == stDone: result += s.code

func pipeline*(c: Coverage): seq[(string, Status)] =
  ## The core parts, then the diagram types, and their status, for `nbPipeline`.
  for p in c.core: result.add (p.id, p.status)
  for d in c.diagrams: result.add (d.id, d.status)
proc loadRoadmap*(): seq[Phase] =
  let j = parseFile(dataDir / "roadmap.json")
  for p in j["phases"]:
    var phase = Phase(id: p["id"].getStr, title: p["title"].getStr, goal: p{"goal"}.getStr)
    for s in p["steps"]:
      let kind = s{"kind"}.getStr("port")
      doAssert kind in postKinds, "roadmap.json: step " & s["id"].getStr & ": kind must be one of " & postKinds.join(", ")
      phase.steps.add Step(id: s["id"].getStr, kind: kind, title: s["title"].getStr, what: s{"what"}.getStr,
                           post: s{"post"}.getStr, pr: s{"pr"}.getStr, status: toStatus(s{"status"}.getStr),
                           doneWhen: s{"done_when"}.getStr, owner: s{"owner"}.getStr)
    result.add phase

proc loadMilestones*(): seq[Milestone] =
  ## The milestones of the roadmap (`milestones` in roadmap.json), or none.
  let j = parseFile(dataDir / "roadmap.json")
  for m in j{"milestones"}.getElems:
    result.add Milestone(id: m["id"].getStr, title: m["title"].getStr, after: m{"after"}.getStr, proof: m{"proof"}.getStr)

func done*(p: Phase): int =
  ## How many steps of the phase are done.
  for s in p.steps:
    if s.status == stDone: inc result

func thousands*(n: int): string =
  ## 137715 as `137,715`.
  let s = $n
  for i, c in s:
    if i > 0 and (s.len - i) mod 3 == 0: result.add ','
    result.add c
