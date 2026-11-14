## bridge: nimaki compiled to JavaScript with Pele's API, so that Pele's own test suites can run
## on the port (tools/peletests.nim). `nim js -d:nodejs` turns this file into a CommonJS module
## whose `nimakiRender(source, options)` takes Pele's options as JavaScript values, functions
## included (a measurer, an icon resolver, a typesetter), and returns Pele's result, or throws
## `{peleError: true, message, code, ...}`, which tools/peletests/index.js turns into a PeleError.
import std/[jsffi, options, tables]
import nimaki
import nimaki/util/yaml

when not defined(js):
  {.error: "the bridge is compiled with nim js".}

proc isUndef(x: JsObject): bool {.importjs: "(# == null)".}
proc isFunction(x: JsObject): bool {.importjs: "(typeof # === 'function')".}
proc isString(x: JsObject): bool {.importjs: "(typeof # === 'string')".}
proc isNumber(x: JsObject): bool {.importjs: "(typeof # === 'number')".}
proc isBool(x: JsObject): bool {.importjs: "(typeof # === 'boolean')".}
proc isArray(x: JsObject): bool {.importjs: "Array.isArray(#)".}
proc isDate(x: JsObject): bool {.importjs: "(# instanceof Date)".}
proc dateValue(x: JsObject): float {.importjs: "#.getTime()".}
proc keysOf(x: JsObject): seq[cstring] {.importjs: "Object.keys(#)".}
proc call1(f: JsObject, a: cstring): JsObject {.importjs: "#(#)".}
proc call2(f: JsObject, a: cstring, b: float): JsObject {.importjs: "#(#, #)".}
proc callWidth(m: JsObject, text: cstring, size: float, style: int): float {.importjs: "#.width(#, #, #)".}
proc jsThrow(x: JsObject) {.importjs: "throw #".}

proc str(x: JsObject): string = $x.to(cstring)
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
  if s.len == 0: jsNull else: toJs(cstring(s))

proc nimakiRender(source: cstring, options: JsObject): JsObject {.exportc.} =
  try:
    let r = render($source, toOptions(options))
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
  except PeleError as e:
    let j = newJsObject()
    j["peleError"] = true
    j["message"] = cstring(e.msg)
    j["code"] = cstring(e.code)
    j["type"] = orNull(e.diagramType)
    j["mermaidType"] = orNull(e.mermaidType)
    j["line"] = e.line
    j["column"] = e.column
    j["snippet"] = cstring(e.snippet)
    jsThrow(j)

proc nimakiDetectType(text: cstring): JsObject {.exportc.} = orNull(detectType($text))
proc nimakiSupports(text: cstring): bool {.exportc.} = supports($text)

{.emit: "module.exports = { nimakiRender, nimakiDetectType, nimakiSupports };".}
