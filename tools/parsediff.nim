## parsediff: the referee for models. Pele's `parse(text)` returns the diagram's model, an object
## its tests read (`parse(text).nodes.get("A").label`); nimaki's `parse` returns the same model,
## as a Nim object. This tool writes both out as JSON and compares them, case by case, on the
## corpus:
##
## - Pele's side: tools/oracle.mjs with `"parse": true` (`canonical`: a Map is `{"$map": ...}`,
##   a Set `{"$set": [...]}`, undefined is left out);
## - nimaki's side: `dump` below, which walks the Nim object field by field (`fieldPairs`): a
##   table is a `$map`, a set a `$set`, a `ref` met again inside itself `"$cycle"`;
## - then both are normalized the same way (`normal`): a key whose value is null, "" or NaN is
##   dropped (nimaki writes "" or NaN where Pele leaves a field undefined), and so is an empty
##   list or table (nimaki's are never missing), numbers are compared as
##   numbers, a Map and an object with the same entries are the same, a set's elements are
##   sorted, and the model's own `type` and `mermaidType` are compared apart. Of nimaki's names,
##   a field named after a Nim keyword (`kind` for `type`, `stop` for `end`) and an enum's prefix
##   (`skState` for `"state"`) are read as Pele's.
##
## A model is the same when the two JSON values are equal: the same keys, the same values. The
## names of nimaki's fields are Pele's, except where Nim forbids them; a field named otherwise,
## an enum written as a name where Pele has a string or a number, a field Pele has and nimaki
## does not, all show as differences, and the first one of each case is printed.
##
##   nim r tools/parsediff.nim                every case of every ported type
##   nim r tools/parsediff.nim pie timeline   only these types
##   options:
##     --show:N        print at most N differences as ERROR lines (default 10)
##     --package:PATH  the oracle package (default reference/npm/package or $PELE_PACKAGE)
##
## It writes its summary in docs/data/parsediff.json, and every difference in
## build/parsediff/report.json.
import std/[os, osproc, json, tables, sets, strutils, algorithm, parseopt, options, strtabs, typetraits]
import common
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

const fixedNow = 1767225600000.0   ## as in tools/difftest.nim

# ------------------------------------------------------------------------------ nimaki's side

proc dump[T](x: T, path: var HashSet[pointer]): JsonNode

func enumName(s: string): string =
  ## An enum's name as Pele's string: Nim's enums carry a prefix (`skState`, `nkTerminal`), which
  ## Pele's string unions do not (`"state"`, `"terminal"`). An enum with string values is written
  ## as its value.
  var i = 0
  while i < s.len and s[i] in {'a'..'z'}: inc i
  if i in 1..3 and i < s.len and s[i] in {'A'..'Z'}: toLowerAscii(s[i]) & s[i + 1 .. ^1] else: s

const renamed = {"kind": "type", "stop": "end"}.toTable
  ## Pele's field names that are Nim keywords, and the names the port gives those fields.

const renamedIn = {"sequence": {"start": "from"}.toTable}.toTable
  ## The same, for one diagram type only (`start` is a field of its own in other types).

proc rename(j: JsonNode, names: Table[string, string]): JsonNode =
  case j.kind
  of JObject:
    result = newJObject()
    for k, v in j: result[names.getOrDefault(k, k)] = rename(v, names)
  of JArray:
    result = newJArray()
    for v in j: result.add rename(v, names)
  else: result = j

proc dumpFields[T: object | tuple](x: T, path: var HashSet[pointer]): JsonNode =
  result = newJObject()
  for name, value in fieldPairs(x):
    when value is proc or value is YamlValue or value is pointer:
      discard   # functions are left out, as JSON leaves them out; config is not the model
    else:
      result[renamed.getOrDefault(name, name)] = dump(value, path)

proc dump[T](x: T, path: var HashSet[pointer]): JsonNode =
  when T is ref:
    if x == nil: return newJNull()
    let p = cast[pointer](x)
    if p in path: return %"$cycle"
    path.incl p
    result = dump(x[], path)
    path.excl p
  elif T is string: %x
  elif T is bool: %x
  elif T is enum: %enumName($x)
  elif T is SomeNumber:
    when T is SomeFloat:
      if x != x: return newJNull()   # NaN: the port's undefined number
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

proc dumpModel*(m: ParsedModel): JsonNode =
  ## nimaki's model as JSON, for the diagram types nimaki draws.
  var path: HashSet[pointer]
  template asT(T: typedesc): JsonNode = dump(T(m.model), path)
  case m.diagramType
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

# ------------------------------------------------------------------------------- both sides

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

proc firstDifference*(a, b: JsonNode, at = "model"): string =
  ## Where two JSON values first differ, and how ("" when they are equal). `a` is Pele's.
  if a == b: return ""
  if a.kind != b.kind:
    return at & ": Pele has " & ($a)[0 ..< min(60, ($a).len)] & ", nimaki " & ($b)[0 ..< min(60, ($b).len)]
  case a.kind
  of JObject:
    var keys: seq[string]
    for k, _ in a: keys.add k
    for k, _ in b:
      if k notin keys: keys.add k
    for k in keys:
      if not b.hasKey(k): return at & "." & k & ": only Pele has it"
      if not a.hasKey(k): return at & "." & k & ": only nimaki has it"
      let d = firstDifference(a[k], b[k], at & "." & k)
      if d.len > 0: return d
  of JArray:
    if a.len != b.len: return at & ": Pele has " & $a.len & " items, nimaki " & $b.len
    for i in 0 ..< a.len:
      let d = firstDifference(a[i], b[i], at & "[" & $i & "]")
      if d.len > 0: return d
  else: discard
  at & ": Pele has " & ($a)[0 ..< min(60, ($a).len)] & ", nimaki " & ($b)[0 ..< min(60, ($b).len)]

# ------------------------------------------------------------------------------------- main

type Outcome = object
  id, diagramType, verdict, detail: string   ## verdict: same, different, error, unsupported

proc main() =
  var only: seq[string]
  var show = 10
  var packageArg = ""
  for kind, key, val in getopt():
    case kind
    of cmdArgument: only.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "show": show = parseInt(val)
      of "package": packageArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdEnd: discard
  let pkg = packageDirFrom(packageArg)
  var cases: seq[JsonNode]
  for c in parseFile(repoDir / "corpus" / "cases.json")["cases"]:
    if only.len == 0 or c["type"].getStr in only: cases.add c

  # Pele's models, in one run of the oracle.
  var input = ""
  for c in cases:
    input.add $(%*{"id": c["id"], "source": c["source"], "parse": true, "options": {"now": fixedNow}}) & "\n"
  let (output, code) = execCmdEx("node " & quoteShell(repoDir / "tools" / "oracle.mjs") & " " & quoteShell(pkg),
                                 env = newStringTable({"TZ": "UTC", "PATH": getEnv("PATH")}), input = input)
  if code != 0: quit "ERROR the oracle failed:\n" & output, 2
  var pele: Table[string, JsonNode]
  for line in output.splitLines:
    if line.len > 0:
      let j = parseJson(line)
      pele[j["id"].getStr] = j

  var outcomes: seq[Outcome]
  for c in cases:
    let id = c["id"].getStr
    let p = pele[id]
    var o = Outcome(id: id, diagramType: c["type"].getStr)
    try:
      let m = parse(c["source"].getStr, RenderOptions(now: some(fixedNow)))
      if not p["ok"].getBool:
        o.verdict = "different"
        o.detail = "Pele throws " & p["code"].getStr & ", nimaki parses"
      else:
        var theirs = normal(p["model"])
        var ours = normal(dumpModel(m))
        if m.diagramType in renamedIn: ours = rename(ours, renamedIn[m.diagramType])
        if theirs.kind == JObject:
          theirs.delete("type")
          if theirs.hasKey("mermaidType"): theirs.delete("mermaidType")
        if ours.kind == JObject and ours.hasKey("type"): ours.delete("type")
        if p["model"]{"mermaidType"}.getStr != m.mermaidType:
          o.verdict = "different"
          o.detail = "mermaidType " & p["model"]{"mermaidType"}.getStr & ", nimaki " & m.mermaidType
        else:
          o.detail = firstDifference(theirs, ours)
          o.verdict = if o.detail.len == 0: "same" else: "different"
    except PeleError as e:
      if e.code == "unsupported": o.verdict = "unsupported"
      elif not p["ok"].getBool and p["code"].getStr == e.code: o.verdict = "error"   # both throw
      else:
        o.verdict = "different"
        o.detail = "nimaki throws " & e.code & (if p["ok"].getBool: ", Pele parses" else: ", Pele " & p["code"].getStr)
    outcomes.add o

  var byType: OrderedTable[string, CountTable[string]]
  var shown = 0
  for o in outcomes:
    byType.mgetOrPut(o.diagramType, initCountTable[string]()).inc o.verdict
    if o.verdict == "different" and shown < show:
      echo "ERROR ", o.id, ": ", o.detail
      inc shown
  byType.sort(proc (a, b: (string, CountTable[string])): int = cmp(a[0], b[0]))
  var types = newJArray()
  var total: CountTable[string]
  for t, counts in byType:
    echo "  ", t.alignLeft(15), align($counts["same"], 5), " same", align($counts["different"], 5), " different",
      align($counts["error"], 5), " both throw", align($counts["unsupported"], 5), " not ported"
    types.add %*{"type": t, "same": counts["same"], "different": counts["different"],
                 "error": counts["error"], "unsupported": counts["unsupported"]}
    for k, n in counts: total.inc(k, n)
  if only.len == 0:
    writeFile repoDir / "docs" / "data" / "parsediff.json", (%*{
      "about": "Pele's parse() against nimaki's, on corpus/cases.json, by tools/parsediff.nim. Do not edit by hand.",
      "pin": readPin()["TAG"], "cases": outcomes.len, "same": total["same"], "different": total["different"],
      "error": total["error"], "unsupported": total["unsupported"], "types": types}).pretty & "\n"
  createDir repoDir / "build" / "parsediff"
  var report = newJArray()
  for o in outcomes:
    if o.verdict == "different": report.add %*{"id": o.id, "type": o.diagramType, "detail": o.detail}
  writeFile repoDir / "build" / "parsediff" / "report.json", report.pretty & "\n"
  echo "parsediff: pele ", readPin()["TAG"], ", ", outcomes.len, " cases of ", byType.len, " types: ",
    total["same"], " same model, ", total["different"], " different, ", total["error"], " both throw, ",
    total["unsupported"], " not ported"

when isMainModule:
  main()
