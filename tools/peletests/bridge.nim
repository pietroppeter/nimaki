## bridge: nimaki compiled to JavaScript with Pele's API, so that Pele's own test suites can run
## on the port (tools/peletests.nim). `nim js -d:nodejs` turns this file into a CommonJS module
## whose `nimakiRender(source, options)` takes Pele's options as JavaScript values, functions
## included (a measurer, an icon resolver, a typesetter), and returns Pele's result, or throws
## `{peleError: true, message, code, ...}`, which tools/peletests/index.js turns into a PeleError.
## `nimakiParse(source, options)` returns the model as Pele's `parse` does, written by
## tools/models.nim as a JavaScript object (a table is a Map, a set a Set), and
## `nimakiRenderModel(model, options)` draws one.
import std/[jsffi, options, tables, json]
import nimaki
import nimaki/util/yaml
import nimaki/js
import ../models
import nimaki/[jsapi, mount, zoom]
from nimaki/diagrams/agentflow/db import AgentflowDb, vertexKind, semanticModel
from nimaki/diagrams/agentflow/types import AgentNode
from nimaki/diagrams/gantt/db import GanttDb, getTasks
from nimaki/diagrams/state/db import StateDb, direction

when not defined(js):
  {.error: "the bridge is compiled with nim js".}

proc newMap(): JsObject {.importjs: "new Map()".}
proc newSet(): JsObject {.importjs: "new Set()".}
proc mapSet(m: JsObject, k: cstring, v: JsObject) {.importjs: "#.set(#, #)".}
proc setAdd(s: JsObject, v: JsObject) {.importjs: "#.add(#)".}
proc newWeakMap(): JsObject {.importjs: "new WeakMap()".}
proc weakGet(m, k: JsObject): JsObject {.importjs: "#.get(#)".}
proc weakSet(m, k, v: JsObject) {.importjs: "#.set(#, #)".}

var parsedModels = newWeakMap()
  ## the Nim model behind each JavaScript model nimakiParse returned, for nimakiRenderModel

proc newIdTable(): JsObject {.importjs: "new Map()".}
proc idGet(m: JsObject, k: int): JsObject {.importjs: "#.get(#)".}
proc idSet(m: JsObject, k: int, v: JsObject) {.importjs: "#.set(#, #)".}

proc toJsValue(j: JsonNode, ids: JsObject): JsObject =
  ## JSON from tools/models.nim (written with `share`) as Pele's JavaScript: `{"$map": ...}` a
  ## Map, `{"$set": [...]}` a Set, `{"$ref": n}` the object written with `"$id": n` (the same
  ## object, cycles included), null as undefined (Pele's undefined).
  case j.kind
  of JNull: result = jsUndefined
  of JBool: result = toJs(j.getBool)
  of JInt: result = toJs(j.getInt)
  of JFloat: result = toJs(j.getFloat)
  of JString: result = toJs(toJsString(j.getStr))
  of JArray:
    var items: seq[JsObject]
    for v in j: items.add toJsValue(v, ids)
    result = toJs(items)
  of JObject:
    if j.len == 1 and j.hasKey("$map"):
      result = newMap()
      # `fields.mpairs`, not json's `pairs`, which copies the table in nim js
      for k, v in j["$map"].fields.mpairs: result.mapSet(cstring(k), toJsValue(v, ids))
    elif j.len == 1 and j.hasKey("$set"):
      result = newSet()
      for v in j["$set"]: result.setAdd(toJsValue(v, ids))
    elif j.len == 1 and j.hasKey("$ref"):
      result = ids.idGet(j["$ref"].getInt)
    else:
      result = newJsObject()
      if j.hasKey("$id"): ids.idSet(j["$id"].getInt, result)
      for k, v in j.fields.mpairs:
        # A field the model has but leaves empty is there, undefined, as a field Pele's class
        # declares and does not set: `toEqual` reads it as missing, `toMatchObject` finds it.
        if k != "$id": result[cstring(k)] = toJsValue(v, ids)

proc nimakiParse(source: cstring, options: JsObject): JsObject {.exportc.} =
  var m: ParsedModel
  try:
    m = parse(wtf8(source), toOptions(options))
  except PeleError as e:
    throwPele(e)
  try:
    result = toJsValue(dumpModel(m, share = true, budget = 2_000_000), newIdTable())
  except:
    # A model nested thousands deep, or of millions of characters (the stress tests), is deeper
    # than JavaScript's stack lets the walk go, or larger than its memory holds twice: the test
    # gets the model without its fields, and can still draw it.
    result = nil
  if result == nil or result.isUndef or not result.isObject: result = newJsObject()
  result["type"] = cstring(m.diagramType)
  result["mermaidType"] = cstring(m.mermaidType)
  # Pele's `direction` getter.
  if m.diagramType == "state": result["direction"] = cstring(StateDb(m.model).direction)
  parsedModels.weakSet(result, toJs(m))

proc newDate(ms: float): JsObject {.importjs: "new Date(#)".}

proc nimakiModelCall(model: JsObject, name: cstring, arg: JsObject): JsObject {.exportc.} =
  ## A method of Pele's model (`getTasks`, `semanticModel`, `vertexKind`), run on the nimaki model
  ## `model` was written from. tools/peletests/index.mjs puts these on the models.
  let found = parsedModels.weakGet(model)
  if found.isUndef: return jsUndefined
  let m = found.to(ParsedModel)
  case $name
  of "getTasks":
    let now = if arg.isDate: arg.dateValue elif arg.isNumber: arg.num else: 0.0
    result = toJsValue(dumpValue(GanttDb(m.model).getTasks(now)), newIdTable())
    # Pele's dates are Date objects; the model's JSON holds their time.
    for i in 0 ..< result["length"].to(int):
      let task = result[i]
      for k in ["startTime", "endTime", "renderEndTime"]:
        if task[k].isNumber: task[k] = newDate(task[k].num)
  of "semanticModel":
    result = toJsValue(dumpValue(AgentflowDb(m.model).semanticModel()), newIdTable())
  of "vertexKind":
    let kind = if arg.isUndef or arg["type"].isUndef: "" else: arg["type"].str
    result = toJs(cstring(AgentflowDb(m.model).vertexKind(AgentNode(kind: kind))))
  else: result = jsUndefined

proc nimakiRenderModel(model: JsObject, options: JsObject): JsObject {.exportc.} =
  ## nil when `model` is not one that nimakiParse returned.
  let found = parsedModels.weakGet(model)
  if found.isUndef: return jsNull
  try:
    result = resultOf(render(found.to(ParsedModel), toOptions(options)))
  except PeleError as e:
    throwPele(e)

proc nimakiRender(source: cstring, options: JsObject): JsObject {.exportc.} =
  try:
    result = resultOf(render(wtf8(source), toOptions(options)))
  except PeleError as e:
    throwPele(e)

proc nimakiDetectType(text: cstring): JsObject {.exportc.} = orNull(detectType(wtf8(text)))
proc nimakiSupports(text: cstring): bool {.exportc.} = supports(wtf8(text))

# Pele's browser side, ported (src/nimaki/mount.nim, zoom.nim, text/measurer.nim).
proc nimakiMountWith(engine, element: JsObject, text: cstring, options: JsObject): JsObject {.exportc.} =
  mountWith(engine, element, text, options)
proc nimakiZoomWith(element, options: JsObject, observe: bool): JsObject {.exportc.} =
  zoomWith(element, options, observe)
proc nimakiEnableZoom(element, options: JsObject): JsObject {.exportc.} = enableZoom(element, options)
proc nimakiFrame(natural, box: JsObject, scale, x, y: float): JsObject {.exportc.} =
  frameJs(natural, box, scale, x, y)
proc nimakiForgetTextWidths() {.exportc.} = forgetTextWidths()
proc nimakiRegistered(kind: cstring): bool {.exportc.} = registered($kind)
type MeasurerBox = ref object
  m: TextMeasurer
proc nimakiCanvasWidth(m: JsObject, text: cstring, size: float, style: int): float {.exportc.} =
  m.to(MeasurerBox).m.width(wtf8(text), size, style)
proc nimakiCanvasMeasurer(fontFamily, monoFamily: cstring): JsObject {.exportc.} =
  ## The port's canvas measurer, as an opaque value nimakiCanvasWidth measures with; null where
  ## there is no canvas.
  let m = canvasMeasurer(wtf8(fontFamily), wtf8(monoFamily))
  if m.width == nil: jsNull else: toJs(MeasurerBox(m: m))

{.emit: """module.exports = { nimakiRender, nimakiParse, nimakiRenderModel, nimakiModelCall, nimakiDetectType,
  nimakiSupports, nimakiMountWith, nimakiZoomWith, nimakiEnableZoom, nimakiFrame, nimakiForgetTextWidths,
  nimakiCanvasMeasurer, nimakiCanvasWidth, nimakiRegistered };""".}
