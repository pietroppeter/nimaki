## modeljson: nimaki's model of a diagram as JSON, in the shape of Pele's. Not a port of a Pele
## file: Pele's `parse(text)` returns a JavaScript object (its types are in src/models.ts, which
## the port does not need), and nimaki's `parse` returns a Nim object. `modelJson` writes that
## object as Pele's would be written: the same keys, a Map as an object, a Set as an array.
##
## `dumpModel` walks the model field by field (`fieldPairs`) into the JSON tools/oracle.mjs
## writes for Pele's: a table is `{"$map": ...}`, a set `{"$set": [...]}`, a `ref` met again
## inside itself `"$cycle"`, NaN (the port's undefined number) null. A field named after a Nim
## keyword (`kind`, `typ` for `type`, `stop` for `end`) and an enum's prefix (`skState` for
## `"state"`) are written as Pele's.
##
## Used by `modelJson` (the C ABI's `nimaki_parse`), by tools/parsediff.nim, the referee for
## models, and by the JavaScript build (src/nimaki/jsapi.nim, tools/peletests/bridge.nim), which
## hands these models to a page and to Pele's tests; so it compiles with `nim js` too.
## Until 15 November 2026 it was tools/models.nim, the name decision 0018 uses.
import std/[json, tables, sets, strutils, options, algorithm, macros, typetraits]
import ../nimaki
import util/yaml
import js
import model
import selection
from diagrams/agentflow/db import AgentflowDb
from diagrams/agentflow/types import MappingSet
from diagrams/architecture/db import ArchitectureDb, ArchNode
from "diagrams/block/db" import BlockDb
from diagrams/c4/db import C4Db, C4Element, C4Rel, C4Attr
from diagrams/class/db import ClassDb
from diagrams/class/types import Relation, NONE
from diagrams/cynefin/model import CynefinModel
from diagrams/er/db import ErDb
from diagrams/eventmodeling/model import EventModelingModel
from diagrams/flowchart/db import FlowDb
from diagrams/gantt/db import GanttDb
from diagrams/gantt/types import GanttTask
from diagrams/git/db import GitModel
from diagrams/info/model import InfoModel
from diagrams/ishikawa/db import IshikawaDb
from diagrams/journey/db import JourneyModel
from diagrams/kanban/db import KanbanModel
from diagrams/mindmap/db import MindmapModel
from diagrams/packet/model import PacketModel, PacketLabel
from diagrams/pie/model import PieModel
from diagrams/quadrant/db import QuadrantModel, QuadrantText
from diagrams/radar/model import RadarModel
from diagrams/railroad/types import RailroadModel, RailroadNode, NodeKind
from diagrams/requirement/db import RequirementDb
from diagrams/sankey/db import SankeyModel
from diagrams/sequence/db import SeqDb
from diagrams/sequence/types import SeqMessage, SeqNote, LINETYPE_NOTE, PLACEMENT_OVER, NO_TYPE
from diagrams/state/db import StateDb
from diagrams/state/types import Stmt, StmtKind, DescrKind
from diagrams/timeline/db import TimelineModel
from diagrams/treemap/model import TreemapModel
from diagrams/treeview/model import TreeViewModel
from diagrams/usecase/types import UsecaseModel, SharedStyles
from diagrams/usecase/json import JsonValue, JsonKind
from diagrams/venn/db import VennDb
from diagrams/wardley/model import WardleyModel
from diagrams/xychart/db import XyChartDb, Axis, Plot

when defined(js):
  import std/jsffi
  type Mark = JsObject
  proc mark[T](x: T): Mark = toJs(x)
  proc same(a, b: JsObject): bool {.importjs: "(# === #)".}
  proc newIds(): JsObject {.importjs: "new Map()".}
  proc idOf(ids: JsObject, x: Mark): JsObject {.importjs: "#.get(#)".}
  proc setId(ids: JsObject, x: Mark, id: int) {.importjs: "#.set(#, #)".}
  proc isUndef(x: JsObject): bool {.importjs: "(# === undefined)".}
  type Ids = JsObject
else:
  type Mark = pointer
  proc mark[T](x: T): Mark = cast[pointer](x)
  proc same(a, b: Mark): bool = a == b
  type Ids = Table[pointer, int]

type Walk* = object
  ## How a model is being written. With `share` (for JavaScript, tools/peletests/bridge.nim), a
  ## `ref` met a second time anywhere is `{"$ref": n}`, where its first writing carries
  ## `"$id": n`, so that the objects of the model are shared as in Pele's, and a model whose
  ## parts point at each other stays as small as the Nim one. Without it (tools/parsediff.nim),
  ## each is written in full, and only a cycle is cut, as `"$cycle"`, as tools/oracle.mjs does.
  share*: bool
  budget*: int      ## with share: how much may be written (a node, or a character of a string,
                    ## is one), past which ModelTooLarge is raised; 0 for no limit
  path: seq[Mark]   ## the refs above the one being written
  ids: Ids
  next: int

type ModelTooLarge* = object of CatchableError

func sizedObject(n: int): JsonNode =
  ## A JSON object with room for `n` keys from the start: one that grows to thousands of keys
  ## copies them all at each doubling, slowly in nim js.
  JsonNode(kind: JObject, fields: initOrderedTable[string, JsonNode](max(n, 2)))

proc spend(w: var Walk, n: int) =
  if w.budget > 0:
    w.budget -= n
    if w.budget <= 0: raise newException(ModelTooLarge, "the model is too large to write")

proc onPath(w: Walk, p: Mark): bool =
  for q in w.path:
    if same(q, p): return true

proc dump[T](x: T, path: var Walk): JsonNode

# Where the port holds a value in a shape of its own, and Pele another. These write plain values
# themselves: a call of the generic `dump` from here would be compiled before its body is.

proc number(x: float, path: Walk): JsonNode =
  ## A number as tools/oracle.mjs writes it: NaN is undefined, an infinity "Infinity". For the
  ## bridge (`share`), the number itself.
  if path.share: newJFloat(x)
  elif x != x: newJNull()
  elif x == Inf: %"Infinity"
  elif x == -Inf: %"-Infinity"
  else: %x

proc dump(x: QuadrantText, path: var Walk): JsonNode =
  ## Pele's optional label, held as an object with a flag for "defined" and one for its type.
  if not x.defined: newJNull()
  else: %*{"text": x.text, "type": (if x.markdown: "markdown" else: "text")}

proc dump(x: Axis, path: var Walk): JsonNode =
  ## Pele's union of a band axis and a linear one, held as one object with a flag.
  if x.band: %*{"type": "band", "title": x.title, "categories": x.categories}
  else: %*{"type": "linear", "title": x.title, "min": number(x.min, path), "max": number(x.max, path)}

proc dump(x: Plot, path: var Walk): JsonNode =
  ## Pele's plot, its type held as a flag, its optional point labels with another.
  var data = newJArray()
  for (label, value) in x.data: data.add %*[label, number(value, path)]
  result = %*{"type": (if x.bar: "bar" else: "line"), "title": x.title, "data": data}
  if x.hasPointLabels: result["pointLabels"] = %x.pointLabels

proc text(x: Option[string]): JsonNode = (if x.isSome: %x.get else: newJNull())

proc dump(x: GanttTask, path: var Walk): JsonNode =
  ## Pele's task, whose dates and previous task may be undefined: the port holds each with a
  ## flag beside it (`hasStart`...), read in many places of the scheduling. A date is its time in
  ## milliseconds, as tools/oracle.mjs writes a Date.
  if x == nil: return newJNull()
  template date(set: bool, t: float): JsonNode = (if set: number(t, path) else: newJNull())
  %*{"id": x.id, "task": x.task, "section": x.section,
     "startTime": date(x.hasStart, x.startTime), "endTime": date(x.hasEnd, x.endTime),
     "renderEndTime": date(x.hasRenderEnd, x.renderEndTime),
     "manualEndTime": x.manualEndTime, "processed": x.processed, "active": x.active,
     "done": x.done, "crit": x.crit, "milestone": x.milestone, "vert": x.vert,
     "order": x.order, "classes": x.classes,
     "prevTaskId": (if x.hasPrev: %x.prevTaskId else: newJNull()),
     "raw": {"data": x.raw.data, "start": (if x.raw.hasStart: %x.raw.start else: newJNull()),
             "end": x.raw.stop}}

proc dump(x: ArchNode, path: var Walk): JsonNode =
  ## Pele's union of a service and a junction, held as one object with a flag; `parent` is
  ## Pele's `in`, a Nim keyword.
  if x.junction: %*{"id": x.id, "type": "junction", "in": text(x.parent)}
  else: %*{"id": x.id, "type": "service", "icon": text(x.icon), "iconText": text(x.iconText),
           "title": text(x.title), "in": text(x.parent)}

proc dump(x: RailroadNode, path: var Walk): JsonNode =
  ## Pele's union of seven shapes, which the port holds as one object with a kind.
  if x == nil: return newJNull()
  var kids = newJArray()
  for k in x.kids: kids.add dump(k, path)
  case x.kind
  of nkTerminal: %*{"type": "terminal", "value": x.text}
  of nkNonterminal: %*{"type": "nonterminal", "name": x.text}
  of nkSpecial: %*{"type": "special", "text": x.text}
  of nkSequence: %*{"type": "sequence", "elements": kids}
  of nkChoice: %*{"type": "choice", "alternatives": kids}
  of nkOptional: %*{"type": "optional", "element": (if kids.len > 0: kids[0] else: newJNull())}
  of nkRepetition:
    %*{"type": "repetition", "element": (if kids.len > 0: kids[0] else: newJNull()),
       "min": number(x.min, path), "max": number(x.max, path)}

proc c4Common(x: C4Element | C4Rel, path: var Walk): JsonNode =
  ## What an element and a relationship share; their optional texts are held in a table.
  template attr(a: Option[C4Attr]): JsonNode =
    (if a.isSome and a.get.isNamed: %*{"key": a.get.key, "value": a.get.value} else: newJNull())
  result = %*{"label": x.label, "labelAttr": attr(x.labelAttr)}
  for k, v in x.fields: result[k] = %v
  if x.extra.len > 0:
    var m = newJObject()
    for k, v in x.extra: m[k] = %v
    result["extra"] = %*{"$map": m}
  when x is C4Element:
    result["alias"] = %x.alias
    result["aliasAttr"] = attr(x.aliasAttr)
  else:
    result["fromAttr"] = attr(x.fromAttr)
    result["toAttr"] = attr(x.toAttr)

proc dump(x: C4Element, path: var Walk): JsonNode =
  ## Pele's shape or boundary: its optional texts held in a table, and a `uid` of the port's
  ## own, so that tables can key elements by identity in either backend.
  if x == nil: return newJNull()
  result = c4Common(x, path)
  result["parent"] = dump(x.parent, path)
  if x.kind != "": result["kind"] = %x.kind
  if x.nodeType != "": result["nodeType"] = %x.nodeType

proc dump(x: C4Rel, path: var Walk): JsonNode =
  ## Pele's relationship: its optional texts held in a table; `typ` and `start` are Pele's
  ## `type` and `from`.
  if x == nil: return newJNull()
  result = c4Common(x, path)
  result["type"] = %x.typ
  result["from"] = %x.start
  result["to"] = %x.to
  if x.offsetX == x.offsetX: result["offsetX"] = number(x.offsetX, path)
  if x.offsetY == x.offsetY: result["offsetY"] = number(x.offsetY, path)

proc dump(x: Stmt, path: var Walk): JsonNode =
  ## Pele's union of statements (and a bare string), which the port holds as one object with a
  ## tag, shared and changed in place; flags beside it say which optional fields Pele's has.
  if x == nil: return newJNull()
  template list(xs: seq[Stmt]): JsonNode =
    (var a = newJArray(); (for s in xs: a.add dump(s, path)); a)
  case x.stmt
  of skText: result = %x.text
  of skState:
    result = %*{"stmt": "state", "id": x.id}
    if x.kind != "": result["type"] = %x.kind
    case x.descr
    of dkNone: discard
    of dkText: result["description"] = %x.description
    of dkList: result["description"] = %x.descriptionList
    if x.record:
      result["descriptions"] = %x.descriptions
      result["styles"] = %x.styles
      result["textStyles"] = %x.textStyles
    if x.hasDoc: result["doc"] = list(x.doc)
    if x.hasNote: result["note"] = %*{"position": x.note.position, "text": x.note.text}
    if x.start.isSome: result["start"] = %x.start.get
    if x.hasClasses: result["classes"] = %x.classes
  of skRelation:
    result = %*{"stmt": "relation", "state1": dump(x.state1, path), "state2": dump(x.state2, path)}
    if x.relDescription.isSome: result["description"] = %x.relDescription.get
  of skClassDef: result = %*{"stmt": "classDef", "id": x.id, "classes": x.classesText}
  of skStyle: result = %*{"stmt": "style", "id": x.id, "styleClass": x.styleClass}
  of skApplyClass: result = %*{"stmt": "applyClass", "id": x.id, "styleClass": x.styleClass}
  of skDir: result = %*{"stmt": "dir", "value": x.value}
  of skClick:
    result = %*{"stmt": "click", "id": dump(x.clickId, path), "url": x.url, "tooltip": x.tooltip}
  of skRoot: result = %*{"stmt": "root", "id": x.id, "doc": list(x.doc)}

proc dump(x: JsonNode, path: var Walk): JsonNode =
  ## A value read from JSON in the text (a sequence actor's links and properties), as Pele holds it.
  if x == nil: newJNull() else: x.copy

proc dump(x: SeqMessage, path: var Walk): JsonNode =
  ## Pele's message, one of three shapes (a signal, a note, an autonumber statement), which the
  ## port holds as one object with a flag.
  result = %*{"id": x.id, "from": text(x.start), "to": text(x.to), "wrap": x.wrap}
  if x.kind != NO_TYPE: result["type"] = %x.kind
  if x.isNumbering:
    result["message"] = %*{"start": number(x.numbering.start, path), "step": number(x.numbering.step, path),
                           "visible": x.numbering.visible}
  else: result["message"] = %x.message
  if x.kind == LINETYPE_NOTE and x.placement != NO_TYPE: result["placement"] = %x.placement
  elif not x.isNumbering:
    result["activate"] = %x.activate
    result["centralConnection"] = %x.centralConnection

proc dump(x: SeqNote, path: var Walk): JsonNode =
  ## Pele's note names one participant, or a pair when it is over two: the port holds a pair.
  %*{"actor": (if x.placement == PLACEMENT_OVER: %x.actor else: %x.actor[0]),
     "placement": x.placement, "message": x.message, "wrap": x.wrap}

proc dump(x: Relation, path: var Walk): JsonNode =
  ## Pele's ends are a number or 'none', which the port holds as NONE.
  template side(t: int): JsonNode = (if t == NONE: %"none" else: %t)
  %*{"type1": side(x.type1), "type2": side(x.type2), "lineType": x.lineType}

proc dump(x: MappingSet, path: var Walk): JsonNode =
  ## Pele's `Set` of mappings, held as a list (a set of references would hash their addresses).
  var s = newJArray()
  for m in x.items:
    let p = m.position
    s.add %*{"id": m.id, "type": m.kind,
             "position": {"startLine": p.startLine, "startColumn": p.startColumn, "endLine": p.endLine,
                          "endColumn": p.endColumn, "startIndex": p.startIndex, "endIndex": p.endIndex}}
  %*{"$set": s}

proc dump(x: SharedStyles, path: var Walk): JsonNode =
  ## Pele's list of a classDef's styles, boxed so that the ids of one classDef share it.
  if x == nil: newJNull() else: %x.items

proc dump(x: JsonValue, path: var Walk): JsonNode =
  ## A value of `JSON.parse`, which the port holds as a union with its keys in order.
  if x == nil: return newJNull()
  case x.kind
  of jNull: result = newJNull()
  of jBool: result = %x.b
  of jNumber: result = number(x.n, path)
  of jString: result = %x.s
  of jArray:
    result = newJArray()
    for v in x.items: result.add dump(v, path)
  of jObject:
    result = sizedObject(x.keys.len)
    for k, key in x.keys: result[key] = dump(x.values[k], path)

proc dump(x: PacketLabel, path: var Walk): JsonNode =
  ## A label boxed so that the pieces of a field share it, as JavaScript shares a string.
  if x == nil: newJNull() else: %x.text

func enumName(s: string): string =
  ## An enum's name as Pele's string: Nim's enums carry a prefix (`skState`, `nkTerminal`), which
  ## Pele's string unions do not (`"state"`, `"terminal"`). An enum with string values is written
  ## as its value.
  var i = 0
  while i < s.len and s[i] in {'a'..'z'}: inc i
  if i in 1..3 and i < s.len and s[i] in {'A'..'Z'}: toLowerAscii(s[i]) & s[i + 1 .. ^1] else: s

const renamed = {"kind": "type", "typ": "type", "stop": "end"}.toTable
  ## Pele's field names that are Nim keywords, and the names the port gives those fields.

const renamedIn* = {"cynefin": {"start": "from"}.toTable,
                    "eventmodeling": {"type": "kind"}.toTable,
                    "architecture": {"parent": "in"}.toTable,
                    "usecase": {"statementKind": "kind"}.toTable}.toTable
  ## (eventmodeling's `kind` is Pele's own `kind`, which the general rule would rename; usecase
  ## has Pele's `type` and, in its statements, Pele's `kind`.)
  ## The same, for one diagram type only (`start` is a field of its own in other types).

proc rename*(j: JsonNode, names: Table[string, string]): JsonNode =
  case j.kind
  of JObject:
    result = sizedObject(j.len)
    for k, v in j.fields.mpairs: result[names.getOrDefault(k, k)] = rename(v, names)  # mpairs: pairs copies the table in nim js
  of JArray:
    result = newJArray()
    for v in j: result.add rename(v, names)
  else: result = j

proc dumpFields[T: object | tuple](x: T, path: var Walk): JsonNode =
  result = newJObject()
  for name, value in fieldPairs(x):
    when value is proc or value is pointer:
      discard   # functions are left out, as JSON leaves them out
    elif value.hasCustomPragma(portOnly):
      discard   # a field of the port's own (src/nimaki/model.nim)
    elif value.hasCustomPragma(undefinedIfEmpty):
      # "" for Pele's undefined (src/nimaki/model.nim)
      result[renamed.getOrDefault(name, name)] = (if value.len > 0: dump(value, path) else: newJNull())
    elif value.hasCustomPragma(spread):
      let inner = dump(value, path)
      if inner.kind == JObject:
        for k, v in inner:
          if k != "$id": result[k] = v
    else:
      result[renamed.getOrDefault(name, name)] = dump(value, path)

proc dumpYaml(v: YamlValue): JsonNode =
  ## A value read from YAML or JSON in the text (metadata, a config), as Pele holds it: a plain
  ## object, not a Map.
  if v == nil: return newJNull()
  case v.kind
  of yNull: newJNull()
  of yBool: %v.b
  of yNumber: (if v.n != v.n: newJNull() else: %v.n)
  of yString: %v.s
  of ySeq:
    var a = newJArray()
    for item in v.items: a.add dumpYaml(item)
    a
  of yMap:
    var o = sizedObject(v.fields.len)
    for k, item in v.fields: o[k] = dumpYaml(item)
    o

proc dump[T](x: T, path: var Walk): JsonNode =
  when T is string or T is StrKey: path.spend(string(x).len + 1)
  else: path.spend(1)
  when T is YamlValue: dumpYaml(x)
  elif T is ref:
    if x == nil: return newJNull()
    let p = mark(x)
    if path.share:
      when defined(js):
        let known = path.ids.idOf(p)
        if not known.isUndef: return %*{"$ref": known.to(int)}
      else:
        if p in path.ids: return %*{"$ref": path.ids[p]}
      inc path.next
      let id = path.next
      when defined(js): path.ids.setId(p, id)
      else: path.ids[p] = id
      result = dump(x[], path)
      if result.kind == JObject: result["$id"] = %id
      return
    if path.onPath(p): return %"$cycle"
    path.path.add p
    result = dump(x[], path)
    discard path.path.pop()
  elif T is string: %x
  elif T is StrKey: %string(x)   # a string key that hashes quickly (js.nim)
  elif T is bool: %x
  elif T is enum: %enumName($x)
  elif T is SomeNumber:
    when T is SomeFloat: number(x.float, path)   # NaN: the port's undefined number
    else: %x.float
  elif T is char: %($x)
  elif T is Option:
    if x.isSome: dump(x.get, path) else: newJNull()
  elif T is Table or T is OrderedTable:
    var m = sizedObject(x.len)
    for k, v in x.pairs: m[$k] = dump(v, path)
    %*{"$map": m}
  elif T is HashSet or T is OrderedSet:
    var s = newJArray()
    for v in x.items: s.add dump(v, path)
    %*{"$set": s}
  elif T is seq or T is array:
    var a = newJArray()
    for v in x: a.add dump(v, path)
    a
  elif T is tuple and not isNamedTuple(T):
    var a = newJArray()   # Pele's pair, [label, value]: an array in JavaScript
    for v in x.fields: a.add dump(v, path)
    a
  elif T is object or T is tuple: dumpFields(x, path)
  else: %($x)

proc dumpValue*[T](x: T): JsonNode =
  ## Any value of a model (what a method of Pele's model returns), as `dumpModel` writes it.
  var path = Walk()
  dump(x, path)

proc dumpModel*(m: ParsedModel, share = false, budget = 0): JsonNode =
  ## nimaki's model as JSON, for the diagram types nimaki draws (`share`, `budget`: see `Walk`).
  var path = Walk(share: share, budget: budget)
  when defined(js):
    if share: path.ids = newIds()
  template asT(T: typedesc): JsonNode = dump(T(m.model), path)
  # Only the types this build draws (`nimaki/selection`): the walk is written out for each type of
  # model it meets, so a type left out of the build leaves its walk out too.
  result = newJNull()
  when drawn("agentflow"):
    if m.diagramType == "agentflow": result = asT(AgentflowDb)
  when drawn("architecture"):
    if m.diagramType == "architecture": result = asT(ArchitectureDb)
  when drawn("block"):
    if m.diagramType == "block": result = asT(BlockDb)
  when drawn("c4"):
    if m.diagramType == "c4": result = asT(C4Db)
  when drawn("class"):
    if m.diagramType == "class": result = asT(ClassDb)
  when drawn("cynefin"):
    if m.diagramType == "cynefin": result = asT(CynefinModel)
  when drawn("er"):
    if m.diagramType == "er": result = asT(ErDb)
  when drawn("eventmodeling"):
    if m.diagramType == "eventmodeling": result = asT(EventModelingModel)
  when drawn("flowchart") or drawn("swimlane"):
    if m.diagramType == "flowchart" or m.diagramType == "swimlane": result = asT(FlowDb)
  when drawn("gantt"):
    if m.diagramType == "gantt": result = asT(GanttDb)
  when drawn("gitGraph"):
    if m.diagramType == "gitGraph": result = asT(GitModel)
  when drawn("info"):
    if m.diagramType == "info": result = asT(InfoModel)
  when drawn("ishikawa"):
    if m.diagramType == "ishikawa": result = asT(IshikawaDb)
  when drawn("journey"):
    if m.diagramType == "journey": result = asT(JourneyModel)
  when drawn("kanban"):
    if m.diagramType == "kanban": result = asT(KanbanModel)
  when drawn("mindmap"):
    if m.diagramType == "mindmap": result = asT(MindmapModel)
  when drawn("packet"):
    if m.diagramType == "packet": result = asT(PacketModel)
  when drawn("pie"):
    if m.diagramType == "pie": result = asT(PieModel)
  when drawn("quadrantChart"):
    if m.diagramType == "quadrantChart": result = asT(QuadrantModel)
  when drawn("radar"):
    if m.diagramType == "radar": result = asT(RadarModel)
  when drawn("railroad"):
    if m.diagramType == "railroad": result = asT(RailroadModel)
  when drawn("requirement"):
    if m.diagramType == "requirement": result = asT(RequirementDb)
  when drawn("sankey"):
    if m.diagramType == "sankey": result = asT(SankeyModel)
  when drawn("sequence"):
    if m.diagramType == "sequence": result = asT(SeqDb)
  when drawn("state"):
    if m.diagramType == "state": result = asT(StateDb)
  when drawn("timeline"):
    if m.diagramType == "timeline": result = asT(TimelineModel)
  when drawn("treemap"):
    if m.diagramType == "treemap": result = asT(TreemapModel)
  when drawn("treeView"):
    if m.diagramType == "treeView": result = asT(TreeViewModel)
  when drawn("usecase"):
    if m.diagramType == "usecase": result = asT(UsecaseModel)
  when drawn("venn"):
    if m.diagramType == "venn": result = asT(VennDb)
  when drawn("wardley"):
    if m.diagramType == "wardley": result = asT(WardleyModel)
  when drawn("xychart"):
    if m.diagramType == "xychart": result = asT(XyChartDb)
  if m.diagramType in renamedIn: result = rename(result, renamedIn[m.diagramType])
  if result.kind == JObject and m.diagramType != "usecase":   # usecase's Pele starts them as ""
    for k in ["title", "accTitle", "accDescr"]:
      # "" for undefined in every model (src/nimaki/model.nim)
      if result{k} != nil and result[k].kind == JString and result[k].getStr == "": result[k] = newJNull()


proc normal*(j: JsonNode, strict = false): JsonNode =
  ## What is compared: keys with null or "" dropped, numbers as floats, sets sorted. With
  ## `strict`, "" is kept: an empty text and a missing one differ, as they do to Pele's tests.
  case j.kind
  of JInt: result = %j.getInt.float
  of JFloat: result = j
  of JObject:
    if j.len == 1 and j.hasKey("$map"): return normal(j["$map"], strict)   # a Map reads as an object
    if j.len == 1 and j.hasKey("$set"):
      var items: seq[JsonNode]
      for v in j["$set"]: items.add normal(v, strict)
      items.sort(proc (a, b: JsonNode): int = cmp($a, $b))
      return %*{"$set": items}
    result = newJObject()
    for k, v in j:
      if v.kind == JNull or (not strict and v.kind == JString and v.getStr == ""): continue
      let n = normal(v, strict)
      if n.kind in {JArray, JObject} and n.len == 0: continue   # an empty list is a missing one
      result[k] = n
  of JArray:
    result = newJArray()
    for v in j: result.add normal(v, strict)
  else: result = j


proc plain(j: JsonNode): JsonNode =
  ## `{"$map": {...}}` as the object, `{"$set": [...]}` as the array.
  case j.kind
  of JObject:
    if j.len == 1 and j.hasKey("$map"): return plain(j["$map"])
    if j.len == 1 and j.hasKey("$set"): return plain(j["$set"])
    result = sizedObject(j.len)
    for k, v in j.fields.mpairs: result.fields[k] = plain(v)
  of JArray:
    result = newJArray()
    for v in j.elems.mitems: result.add plain(v)
  else: result = j

proc modelJson*(m: ParsedModel): JsonNode =
  ## The model `parse` returned, as JSON in the shape of Pele's model: a Map is an object, a Set
  ## an array, a part met again inside itself `"$cycle"`, an undefined number null. With
  ## `type` and `mermaidType`, as Pele's `parse` adds them.
  result = plain(dumpModel(m))
  if result.kind != JObject: result = newJObject()
  result["type"] = %m.diagramType
  result["mermaidType"] = %m.mermaidType
