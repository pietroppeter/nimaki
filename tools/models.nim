## models: nimaki's model of a diagram written as Pele's, in JSON. Pele's `parse(text)` returns
## a JavaScript object, its tests read it (`parse(text).nodes.get("A").label`); nimaki's `parse`
## returns a Nim object. `dumpModel` walks that object field by field (`fieldPairs`) into the
## JSON tools/oracle.mjs writes for Pele's: a table is `{"$map": ...}`, a set `{"$set": [...]}`, a
## `ref` met again inside itself `"$cycle"`, NaN (the port's undefined number) null. A field
## named after a Nim keyword (`kind`, `typ` for `type`, `stop` for `end`) and an enum's prefix
## (`skState` for `"state"`) are written as Pele's.
##
## Used by tools/parsediff.nim, the referee for models, and by tools/peletests/bridge.nim, which
## hands these models to Pele's tests; so it compiles with `nim js` too.
import std/[json, tables, sets, strutils, options, algorithm]
import nimaki
import nimaki/util/yaml
from nimaki/diagrams/agentflow/db import AgentflowDb
from nimaki/diagrams/architecture/db import ArchitectureDb
from "nimaki/diagrams/block/db" import BlockDb
from nimaki/diagrams/c4/db import C4Db
from nimaki/diagrams/class/db import ClassDb
from nimaki/diagrams/cynefin/model import CynefinModel
from nimaki/diagrams/er/db import ErDb
from nimaki/diagrams/eventmodeling/model import EventModelingModel
from nimaki/diagrams/flowchart/db import FlowDb
from nimaki/diagrams/gantt/db import GanttDb
from nimaki/diagrams/git/db import GitModel
from nimaki/diagrams/info/model import InfoModel
from nimaki/diagrams/ishikawa/db import IshikawaDb
from nimaki/diagrams/journey/db import JourneyModel
from nimaki/diagrams/kanban/db import KanbanModel
from nimaki/diagrams/mindmap/db import MindmapModel
from nimaki/diagrams/packet/model import PacketModel
from nimaki/diagrams/pie/model import PieModel
from nimaki/diagrams/quadrant/db import QuadrantModel
from nimaki/diagrams/radar/model import RadarModel
from nimaki/diagrams/railroad/types import RailroadModel
from nimaki/diagrams/requirement/db import RequirementDb
from nimaki/diagrams/sankey/db import SankeyModel
from nimaki/diagrams/sequence/db import SeqDb
from nimaki/diagrams/state/db import StateDb
from nimaki/diagrams/timeline/db import TimelineModel
from nimaki/diagrams/treemap/model import TreemapModel
from nimaki/diagrams/treeview/model import TreeViewModel
from nimaki/diagrams/usecase/types import UsecaseModel
from nimaki/diagrams/venn/db import VennDb
from nimaki/diagrams/wardley/model import WardleyModel
from nimaki/diagrams/xychart/db import XyChartDb

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

proc spend(w: var Walk, n: int) =
  if w.budget > 0:
    w.budget -= n
    if w.budget <= 0: raise newException(ModelTooLarge, "the model is too large to write")

proc onPath(w: Walk, p: Mark): bool =
  for q in w.path:
    if same(q, p): return true

proc dump[T](x: T, path: var Walk): JsonNode

func enumName(s: string): string =
  ## An enum's name as Pele's string: Nim's enums carry a prefix (`skState`, `nkTerminal`), which
  ## Pele's string unions do not (`"state"`, `"terminal"`). An enum with string values is written
  ## as its value.
  var i = 0
  while i < s.len and s[i] in {'a'..'z'}: inc i
  if i in 1..3 and i < s.len and s[i] in {'A'..'Z'}: toLowerAscii(s[i]) & s[i + 1 .. ^1] else: s

const renamed = {"kind": "type", "typ": "type", "stop": "end"}.toTable
  ## Pele's field names that are Nim keywords, and the names the port gives those fields.

const renamedIn* = {"sequence": {"start": "from"}.toTable}.toTable
  ## The same, for one diagram type only (`start` is a field of its own in other types).

proc rename*(j: JsonNode, names: Table[string, string]): JsonNode =
  case j.kind
  of JObject:
    result = newJObject()
    for k, v in j: result[names.getOrDefault(k, k)] = rename(v, names)
  of JArray:
    result = newJArray()
    for v in j: result.add rename(v, names)
  else: result = j

proc dumpFields[T: object | tuple](x: T, path: var Walk): JsonNode =
  result = newJObject()
  for name, value in fieldPairs(x):
    when value is proc or value is YamlValue or value is pointer:
      discard   # functions are left out, as JSON leaves them out; config is not the model
    else:
      result[renamed.getOrDefault(name, name)] = dump(value, path)

proc dump[T](x: T, path: var Walk): JsonNode =
  when T is string: path.spend(x.len + 1)
  else: path.spend(1)
  when T is ref:
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
  elif T is bool: %x
  elif T is enum: %enumName($x)
  elif T is SomeNumber:
    when T is SomeFloat:
      if x != x:   # NaN: the port's undefined number, or a NaN of Pele's
        return if path.share: newJFloat(x) else: newJNull()
    %x.float
  elif T is char: %($x)
  elif T is Option:
    if x.isSome: dump(x.get, path) else: newJNull()
  elif T is Table or T is OrderedTable:
    var m = newJObject()
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
  elif T is object or T is tuple: dumpFields(x, path)
  else: %($x)

proc dumpModel*(m: ParsedModel, share = false, budget = 0): JsonNode =
  ## nimaki's model as JSON, for the diagram types nimaki draws (`share`, `budget`: see `Walk`).
  var path = Walk(share: share, budget: budget)
  when defined(js):
    if share: path.ids = newIds()
  template asT(T: typedesc): JsonNode = dump(T(m.model), path)
  result = case m.diagramType
  of "agentflow": asT(AgentflowDb)
  of "architecture": asT(ArchitectureDb)
  of "block": asT(BlockDb)
  of "c4": asT(C4Db)
  of "class": asT(ClassDb)
  of "cynefin": asT(CynefinModel)
  of "er": asT(ErDb)
  of "eventmodeling": asT(EventModelingModel)
  of "flowchart", "swimlane": asT(FlowDb)
  of "gantt": asT(GanttDb)
  of "gitGraph": asT(GitModel)
  of "info": asT(InfoModel)
  of "ishikawa": asT(IshikawaDb)
  of "journey": asT(JourneyModel)
  of "kanban": asT(KanbanModel)
  of "mindmap": asT(MindmapModel)
  of "packet": asT(PacketModel)
  of "pie": asT(PieModel)
  of "quadrantChart": asT(QuadrantModel)
  of "radar": asT(RadarModel)
  of "railroad": asT(RailroadModel)
  of "requirement": asT(RequirementDb)
  of "sankey": asT(SankeyModel)
  of "sequence": asT(SeqDb)
  of "state": asT(StateDb)
  of "timeline": asT(TimelineModel)
  of "treemap": asT(TreemapModel)
  of "treeView": asT(TreeViewModel)
  of "usecase": asT(UsecaseModel)
  of "venn": asT(VennDb)
  of "wardley": asT(WardleyModel)
  of "xychart": asT(XyChartDb)
  else: newJNull()
  if m.diagramType in renamedIn: result = rename(result, renamedIn[m.diagramType])


proc normal*(j: JsonNode): JsonNode =
  ## What is compared: keys with null or "" dropped, numbers as floats, sets sorted.
  case j.kind
  of JInt: result = %j.getInt.float
  of JFloat: result = j
  of JObject:
    if j.len == 1 and j.hasKey("$map"): return normal(j["$map"])   # a Map reads as an object
    if j.len == 1 and j.hasKey("$set"):
      var items: seq[JsonNode]
      for v in j["$set"]: items.add normal(v)
      items.sort(proc (a, b: JsonNode): int = cmp($a, $b))
      return %*{"$set": items}
    result = newJObject()
    for k, v in j:
      if v.kind == JNull or (v.kind == JString and v.getStr == ""): continue
      let n = normal(v)
      if n.kind in {JArray, JObject} and n.len == 0: continue   # an empty list is a missing one
      result[k] = n
  of JArray:
    result = newJArray()
    for v in j: result.add normal(v)
  else: result = j
