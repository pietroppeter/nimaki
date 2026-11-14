## port-of: src/diagrams/eventmodeling/model.ts
## port-status: draft
import std/[algorithm, sets, strutils, tables]
import ../../errors
import ../../js
import ../common/tokens
import parser
import ../../jsregex

type
  EntityKind* = string   ## "ui" | "processor" | "command" | "readmodel" | "event"
  LaneGroup* = string    ## "trigger" | "state" | "stream"

  EmLane* = ref object
    index*: int
      ## Mermaid's ordering key: 0 for UI/Automation, 100 for Command/Read Model, 200 for Events,
      ## and the next free number after those for each namespace.
    label*: string
    group*: LaneGroup
    namespace*: string   ## "" for undefined

  EmBox* = ref object
    id*: string
      ## The frame number as written, such as "01".
    kind*: EntityKind
    entity*: string
    name*: string
    namespace*: string   ## "" for undefined
    reset*: bool
    lane*: EmLane
    data*: string
      ## Example data from the frame or from the data block it refers to; "" for none.
    dataType*: string
    order*: int
      ## Its place in `boxes`: nimaki's key where Pele keys a Map by the box itself.

  EmRelation* = object
    source*, target*: EmBox

  EmNote* = object
    frame*, text*, dataType*: string

  EmSpecification* = object
    frame*: string
    given*, `when`*, then*: seq[string]

  EventModelingModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    boxes*: seq[EmBox]
    lanes*: seq[EmLane]
      ## Sorted from top to bottom.
    relations*: seq[EmRelation]
    notes*: seq[EmNote]
    specifications*: seq[EmSpecification]
    entities*: seq[string]

let KINDS = {
  "ui": "ui", "pcr": "processor", "processor": "processor", "rmo": "readmodel", "readmodel": "readmodel",
  "cmd": "command", "command": "command", "evt": "event", "event": "event",
}.toTable

let GROUPS = {
  # [first index, label, label prefix for a namespace]
  "trigger": (0, "UI/Automation", "UI/A: "),
  "state": (100, "Command/Read Model", "C/RM: "),
  "stream": (200, "Events", "Stream: "),
}.toTable

func groupOf(kind: EntityKind): LaneGroup =
  if kind == "ui" or kind == "processor": "trigger" elif kind == "event": "stream" else: "state"

func leadingSpaceUnits(line: string): int =
  ## line.length - line.trimStart().length: every JavaScript space is one code unit.
  var i = 0
  while true:
    let n = spaceLenAt(line, i)
    if n == 0: break
    i += n
    inc result

func blockText(raw: string): string =
  ## The text between the outer braces, without the indentation its lines share.
  let open = raw.find('{')
  let close = raw.rfind('}')
  let inner = if open != -1 and close > open: raw[open + 1 ..< close]
              elif open == -1 and raw.len >= 2: raw[1 ..< raw.len - 1]   # the quotes are one byte each
              else: ""
  var lines = inner.replace("\r", "").split('\n')
  while lines.len > 0 and jsTrim(lines[0]) == "": lines.delete(0)
  while lines.len > 0 and jsTrim(lines[^1]) == "": discard lines.pop()
  var indent = high(int)
  for line in lines:
    if jsTrim(line) == "": continue
    indent = min(indent, leadingSpaceUnits(line))
  var output: seq[string]
  for line in lines: output.add jsTrimEnd(substringFrom(line, min(indent, utf16Len(line))))
  output.join("\n")

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc buildEventModel*(ast: EventModelAst, title: string): EventModelingModel =
  var ids = initHashSet[string]()
  for frame in ast.frames:
    if frame.name in ids:
      let line = locate(ast.source, frame.offset).line
      raise newPeleError("Duplicate event modeling frame ID \"" & frame.name & "\" on line " & $line, "semantic",
                         ErrorInfo(diagramType: "eventmodeling", line: line))
    ids.incl frame.name

  var data = initTable[string, string]()
  for entity in ast.dataEntities:
    if entity.name notin data: data[entity.name] = entity.dataBlockValue

  # One lane per group, and one more per namespace within a group.
  var laneOf = initOrderedTable[string, EmLane]()
  var next = initTable[LaneGroup, int]()
  proc lane(kind: EntityKind, namespace: string): EmLane =
    let group = groupOf(kind)
    let key = if namespace == "": group else: group & " " & namespace
    if key in laneOf: return laneOf[key]
    let (first, label, prefix) = GROUPS[group]
    var index = first
    if namespace != "":
      index = next.getOrDefault(group, first + 1)
      next[group] = index + 1
    result = EmLane(index: index, label: (if namespace == "": label else: prefix & namespace), group: group,
                    namespace: namespace)
    laneOf[key] = result

  var boxes: seq[EmBox]
  var relations: seq[EmRelation]
  for index, frame in ast.frames:
    # Only a two-part name has a namespace.
    let parts = frame.entityIdentifier.split('.')
    let namespace = if parts.len == 2: parts[0] else: ""
    let kind = KINDS.getOrDefault(frame.modelEntityType, "event")
    var text = if frame.hasInline: blockText(frame.dataInlineValue) else: ""
    if frame.hasDataReference and frame.dataReference in data:
      text = blockText(data[frame.dataReference])
    let box = EmBox(
      id: frame.name,
      kind: kind,
      entity: frame.entityIdentifier,
      name: if parts.len == 2: parts[1] else: frame.entityIdentifier,
      namespace: namespace,
      reset: frame.reset,
      lane: lane(kind, namespace),
      data: text,
      dataType: frame.dataType,
      order: boxes.len)
    boxes.add box

    if frame.sourceFrames.len > 0:
      # Sources connect in frame order, and only frames that already have a box.
      let wanted = frame.sourceFrames.toHashSet
      for source in boxes:
        if source.id in wanted: relations.add EmRelation(source: source, target: box)
    elif index > 0 and not box.reset:
      # Otherwise the nearest earlier frame in another lane feeds this one.
      for i in countdown(index - 1, 0):
        if boxes[i].lane != box.lane:
          relations.add EmRelation(source: boxes[i], target: box)
          break

  var lanes: seq[EmLane]
  for l in laneOf.values: lanes.add l
  lanes.sort(proc (a, b: EmLane): int = a.index - b.index)
  var notes: seq[EmNote]
  for note in ast.noteEntities:
    notes.add EmNote(frame: note.sourceFrame, text: blockText(note.dataBlockValue), dataType: note.dataType)
  var specifications: seq[EmSpecification]
  for gwt in ast.gwtEntities:
    specifications.add EmSpecification(frame: gwt.sourceFrame, given: gwt.givenStatements,
                                       `when`: gwt.whenStatements, then: gwt.thenStatements)
  let titled = if ast.title != "": titleValue(ast.title) else: ""
  EventModelingModel(
    title: if titled != "": titled else: title,
    accTitle: if ast.accTitle != "": accTitleValue(ast.accTitle).replace(jsre"/^\s+/g", "") else: "",
    accDescr: if ast.accDescr != "": collapseIndents(accDescrValue(ast.accDescr)) else: "",
    boxes: boxes,
    lanes: lanes,
    relations: relations,
    notes: notes,
    specifications: specifications,
    entities: ast.modelEntities)
