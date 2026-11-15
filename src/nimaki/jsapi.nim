## jsapi: nimaki's values as JavaScript's, for the JavaScript build. Not a port of a Pele file:
## Pele is JavaScript, and its options and results are JavaScript values already. Here the
## options a page or a test gives (`toOptions`: functions included, a measurer, an icon
## resolver, a typesetter) become nimaki's `RenderOptions`, a result becomes Pele's result
## object (`resultOf`), and a `PeleError` becomes a JavaScript object a caller can throw again
## as Pele's error (`peleErrorObject`). Used by src/nimaki/web.nim (the page's `nimaki`) and by
## tools/peletests/bridge.nim (Pele's tests).
when not defined(js):
  {.error: "src/nimaki/jsapi.nim is for the JavaScript build".}

import std/[jsffi, options, tables]
import ../nimaki
import util/yaml
import js

export jsffi

proc isUndef*(x: JsObject): bool {.importjs: "(# == null)".}
proc isFunction*(x: JsObject): bool {.importjs: "(typeof # === 'function')".}
proc isString*(x: JsObject): bool {.importjs: "(typeof # === 'string')".}
proc isNumber*(x: JsObject): bool {.importjs: "(typeof # === 'number')".}
proc isBool(x: JsObject): bool {.importjs: "(typeof # === 'boolean')".}
proc isArray(x: JsObject): bool {.importjs: "Array.isArray(#)".}
proc isObject*(x: JsObject): bool {.importjs: "(typeof # === 'object')".}
proc isDate*(x: JsObject): bool {.importjs: "(# instanceof Date)".}
proc dateValue*(x: JsObject): float {.importjs: "#.getTime()".}
proc keysOf(x: JsObject): seq[cstring] {.importjs: "Object.keys(#)".}
proc call1(f: JsObject, a: cstring): JsObject {.importjs: "#(#)".}
proc call2(f: JsObject, a: cstring, b: float): JsObject {.importjs: "#(#, #)".}
proc callWidth(m: JsObject, text: cstring, size: float, style: int): float {.importjs: "#.width(#, #, #)".}
proc jsThrow*(x: JsObject) {.importjs: "throw #".}

proc jsLen(s: cstring): int {.importjs: "#.length".}
proc unitAt(s: cstring, i: int): int {.importjs: "#.charCodeAt(#)".}

proc wtf8*(s: cstring): string =
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

proc str*(x: JsObject): string = wtf8(x.to(cstring))
proc num*(x: JsObject): float = x.to(float)

proc toYaml*(x: JsObject): YamlValue =
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

proc strings*(x: JsObject): seq[string] =
  for i in 0 ..< x["length"].to(int): result.add x[i].str

proc toOptions*(o: JsObject): RenderOptions =
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

proc orNull*(s: string): JsObject =
  if s.len == 0: jsNull else: toJs(toJsString(s))

proc peleErrorObject*(e: ref PeleError): JsObject =
  ## The error as `{peleError: true, message, code, type, mermaidType, line, column, snippet}`.
  let j = newJsObject()
  j["peleError"] = true
  j["message"] = toJsString(e.msg)
  j["code"] = cstring(e.code)
  j["type"] = orNull(e.diagramType)
  j["mermaidType"] = orNull(e.mermaidType)
  j["line"] = e.line
  j["column"] = e.column
  j["snippet"] = toJsString(e.snippet)
  j

proc throwPele*(e: ref PeleError) =
  jsThrow(peleErrorObject(e))

proc resultOf*(r: RenderResult): JsObject =
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

