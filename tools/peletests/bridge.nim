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
from nimaki/diagrams/agentflow/db import AgentflowDb, vertexKind, semanticModel
from nimaki/diagrams/agentflow/types import AgentNode
from nimaki/diagrams/gantt/db import GanttDb, getTasks
from nimaki/diagrams/state/db import StateDb, direction

when not defined(js):
  {.error: "the bridge is compiled with nim js".}

proc isUndef(x: JsObject): bool {.importjs: "(# == null)".}
proc isFunction(x: JsObject): bool {.importjs: "(typeof # === 'function')".}
proc isString(x: JsObject): bool {.importjs: "(typeof # === 'string')".}
proc isNumber(x: JsObject): bool {.importjs: "(typeof # === 'number')".}
proc isBool(x: JsObject): bool {.importjs: "(typeof # === 'boolean')".}
proc isArray(x: JsObject): bool {.importjs: "Array.isArray(#)".}
proc isObject(x: JsObject): bool {.importjs: "(typeof # === 'object')".}
proc isDate(x: JsObject): bool {.importjs: "(# instanceof Date)".}
proc dateValue(x: JsObject): float {.importjs: "#.getTime()".}
proc keysOf(x: JsObject): seq[cstring] {.importjs: "Object.keys(#)".}
proc call1(f: JsObject, a: cstring): JsObject {.importjs: "#(#)".}
proc call2(f: JsObject, a: cstring, b: float): JsObject {.importjs: "#(#, #)".}
proc callWidth(m: JsObject, text: cstring, size: float, style: int): float {.importjs: "#.width(#, #, #)".}
proc jsThrow(x: JsObject) {.importjs: "throw #".}

proc jsLen(s: cstring): int {.importjs: "#.length".}
proc unitAt(s: cstring, i: int): int {.importjs: "#.charCodeAt(#)".}

proc wtf8(s: cstring): string =
  ## A JavaScript string as the port's: UTF-8, a lone surrogate kept as its three bytes, as the
  ## port reads one from JSON (decision 0011). Nim's own `$` pairs a lone surrogate with the next
  ## character.
  let n = s.jsLen
  result = newStringOfCap(n)
  var i = 0
  while i < n:
    var c = s.unitAt(i)
    inc i
    # comparisons, not `in a .. b`: nim js builds the range as an object, at every character
    if c >= 0xD800 and c <= 0xDBFF and i < n and s.unitAt(i) >= 0xDC00 and s.unitAt(i) <= 0xDFFF:
      c = 0x10000 + ((c - 0xD800) shl 10) + (s.unitAt(i) - 0xDC00)
      inc i
    if c < 0x80: result.add char(c)
    elif c < 0x800:
      result.add char(0xC0 or (c shr 6))
      result.add char(0x80 or (c and 0x3F))
    elif c < 0x10000:
      result.add char(0xE0 or (c shr 12))
      result.add char(0x80 or ((c shr 6) and 0x3F))
      result.add char(0x80 or (c and 0x3F))
    else:
      result.add char(0xF0 or (c shr 18))
      result.add char(0x80 or ((c shr 12) and 0x3F))
      result.add char(0x80 or ((c shr 6) and 0x3F))
      result.add char(0x80 or (c and 0x3F))

proc str(x: JsObject): string = wtf8(x.to(cstring))
proc num(x: JsObject): float = x.to(float)

proc toYaml(x: JsObject): YamlValue =
  if x.isUndef: return ynull()
  if x.isBool: return ybool(x.to(bool))
  if x.isNumber: return ynum(x.num)
  if x.isString: return YamlValue(kind: yString, s: x.str)
  if x.isArray:
    result = YamlValue(kind: ySeq)
    for i in 0 ..< x["length"].to(int): result.items.add toYaml(x[i])
    return
  result = YamlValue(kind: yMap)
  for k in keysOf(x): result.fields[$k] = toYaml(x[k])

proc strings(x: JsObject): seq[string] =
  for i in 0 ..< x["length"].to(int): result.add x[i].str

proc toOptions(o: JsObject): RenderOptions =
  if o.isUndef: return
  template has(k: string): bool = not o[k].isUndef
  if has"measurer":
    let m = o["measurer"]
    result.measurer = TextMeasurer(width: proc (text: string, size: float, style: int): float {.noSideEffect, gcsafe.} =
      {.cast(noSideEffect), cast(gcsafe).}:
        callWidth(m, cstring(text), size, style))
  if has"fontFamily": result.fontFamily = o["fontFamily"].str
  if has"fontFamilyMono": result.fontFamilyMono = o["fontFamilyMono"].str
  if has"monospace": result.monospace = strings(o["monospace"])
  if has"fontSize": result.fontSize = some(o["fontSize"].num)
  if has"idPrefix": result.idPrefix = some(o["idPrefix"].str)
  if has"responsive": result.responsive = some(o["responsive"].to(bool))
  if has"maxWidth": result.maxWidth = some(o["maxWidth"].num)
  if has"autoDirection": result.autoDirection = some(o["autoDirection"].to(bool))
  if has"directionBreakpoint": result.directionBreakpoint = some(o["directionBreakpoint"].num)
  if has"padding": result.padding = some(o["padding"].num)
  if has"limit": result.limit = some(o["limit"].to(int))
  if has"outputLimit": result.outputLimit = some(o["outputLimit"].to(int))
  if has"maxEdges": result.maxEdges = some(o["maxEdges"].to(int))
  if has"linkSchemes": result.linkSchemes = some(strings(o["linkSchemes"]))
  if has"imageSchemes": result.imageSchemes = some(strings(o["imageSchemes"]))
  if has"links": result.links = some(o["links"].to(bool))
  if has"images": result.images = some(o["images"].to(bool))
  if has"linkRel": result.linkRel = some(o["linkRel"].str)
  if has"icons" and o["icons"].isFunction:
    let f = o["icons"]
    result.icons = proc (name: string): string =
      let r = call1(f, cstring(name))
      if r.isUndef: "" else: r.str
  if has"math" and o["math"].isFunction:
    let f = o["math"]
    result.math = proc (tex: string, size: float): MathMarkup =
      let r = call2(f, cstring(tex), size)
      if r.isUndef: return nil
      if not r["svg"].isUndef:
        MathMarkup(isSvg: true, markup: r["svg"].str, width: r["width"].num, height: r["height"].num)
      else:
        MathMarkup(isSvg: false, markup: r["html"].str, width: r["width"].num, height: r["height"].num)
  if has"config": result.config = toYaml(o["config"])
  if has"now":
    result.now = some(if o["now"].isDate: o["now"].dateValue else: o["now"].num)

proc orNull(s: string): JsObject =
  if s.len == 0: jsNull else: toJs(toJsString(s))

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

proc throwPele(e: ref PeleError) =
  let j = newJsObject()
  j["peleError"] = true
  j["message"] = toJsString(e.msg)
  j["code"] = cstring(e.code)
  j["type"] = orNull(e.diagramType)
  j["mermaidType"] = orNull(e.mermaidType)
  j["line"] = e.line
  j["column"] = e.column
  j["snippet"] = toJsString(e.snippet)
  jsThrow(j)

proc resultOf(r: RenderResult): JsObject =
  result = newJsObject()
  result["type"] = cstring(r.diagramType)
  result["mermaidType"] = cstring(r.mermaidType)
  result["svg"] = cstring(r.svg)
  result["width"] = r.width
  result["height"] = r.height
  var list: seq[JsObject]
  for l in r.links:
    let j = newJsObject()
    j["id"] = cstring(l.id)
    j["href"] = cstring(l.href)
    j["internal"] = l.internal
    list.add j
  result["links"] = toJs(list)

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

{.emit: "module.exports = { nimakiRender, nimakiParse, nimakiRenderModel, nimakiModelCall, nimakiDetectType, nimakiSupports };".}
