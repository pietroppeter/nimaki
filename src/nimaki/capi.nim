## nimaki as a shared library with a C ABI, for other languages: Python through ctypes, or
## anything that can call C. Not a port of a file of Pele. Build it with
##
##   nim c --app:lib -d:release --mm:orc --threads:on -o:build/cabi/libnimaki.so src/nimaki/capi.nim
##
## (`tools/cabi.nim` does that and runs the Python smoke test). The header is `capi.h`, beside
## this file. Four functions, JSON in and JSON out, as diagrammari's own C ABI is:
##
##   nimaki_render(request) -> answer     both UTF-8 JSON text; free the answer with nimaki_free
##   nimaki_free(answer)
##   nimaki_pele_version() -> "1.13.0"    the Pele this build draws as (reference/PIN)
##
## request: {"source": "<Mermaid text>", "options": {...}}, with Pele's render options by their
##          names: fontSize, fontFamily, fontFamilyMono, monospace, padding, maxWidth, idPrefix,
##          responsive, autoDirection, directionBreakpoint, limit, outputLimit, maxEdges, links,
##          images, linkRel, linkSchemes, imageSchemes, now, config.
## answer:  {"ok": true, "type", "mermaidType", "svg", "width", "height", "links": [...]}
##          or {"ok": false, "type", "code", "message", "line", "column", "snippet"}
##
## Same names as the answers of Pele run in Node by diagrammari (`src/mari/pele.nim`), so a host
## can swap one for the other. The text is measured with Pele's default, `metricsMeasurer`, as in
## Node. Icons and math, which Pele takes as callbacks, are not offered here yet.
##
## Every call takes one lock: nimaki keeps some state in globals while it draws (the palette, the
## icon and math resolvers), so two threads must not draw at once. ctypes lets go of the GIL
## during a call, so Python threads may call it; they wait their turn.

import std/[json, options, locks, strutils]
import ../nimaki
from preprocess import fromJson

const
  pin = staticRead("../../reference/PIN")

func pinValue(key: string): string =
  for line in pin.splitLines:
    if line.startsWith(key & "="): return line[key.len + 1 .. ^1]

const peleVersion = pinValue("TAG")

proc strings(j: JsonNode): seq[string] =
  for it in j: result.add it.getStr

proc toOptions*(j: JsonNode): RenderOptions =
  ## Pele's render options, from their JSON. Unknown keys are ignored, as Pele ignores them.
  if j.isNil or j.kind != JObject: return
  if j.hasKey("fontFamily"): result.fontFamily = j["fontFamily"].getStr
  if j.hasKey("fontFamilyMono"): result.fontFamilyMono = j["fontFamilyMono"].getStr
  if j.hasKey("monospace"): result.monospace = strings(j["monospace"])
  if j.hasKey("fontSize"): result.fontSize = some(j["fontSize"].getFloat)
  if j.hasKey("idPrefix"): result.idPrefix = some(j["idPrefix"].getStr)
  if j.hasKey("responsive"): result.responsive = some(j["responsive"].getBool)
  if j.hasKey("maxWidth"): result.maxWidth = some(j["maxWidth"].getFloat)
  if j.hasKey("autoDirection"): result.autoDirection = some(j["autoDirection"].getBool)
  if j.hasKey("directionBreakpoint"): result.directionBreakpoint = some(j["directionBreakpoint"].getFloat)
  if j.hasKey("padding"): result.padding = some(j["padding"].getFloat)
  if j.hasKey("limit"): result.limit = some(j["limit"].getInt)
  if j.hasKey("outputLimit"): result.outputLimit = some(j["outputLimit"].getInt)
  if j.hasKey("maxEdges"): result.maxEdges = some(j["maxEdges"].getInt)
  if j.hasKey("linkSchemes"): result.linkSchemes = some(strings(j["linkSchemes"]))
  if j.hasKey("imageSchemes"): result.imageSchemes = some(strings(j["imageSchemes"]))
  if j.hasKey("links"): result.links = some(j["links"].getBool)
  if j.hasKey("images"): result.images = some(j["images"].getBool)
  if j.hasKey("linkRel"): result.linkRel = some(j["linkRel"].getStr)
  if j.hasKey("now"): result.now = j["now"].getFloat
  if j.hasKey("config") and j["config"].kind == JObject: result.config = fromJson(j["config"])

proc answer*(request: JsonNode): JsonNode =
  ## The answer to one request, as JSON: never raises.
  let source = request{"source"}
  if source.isNil or source.kind != JString:
    return %*{"ok": false, "type": nil, "code": "request", "message": "the request has no \"source\" string",
              "line": 0, "column": 0, "snippet": ""}
  try:
    let r = render(source.getStr, toOptions(request{"options"}))
    var links = newJArray()
    for l in r.links: links.add %*{"id": l.id, "href": l.href, "internal": l.internal}
    %*{"ok": true, "type": r.diagramType, "mermaidType": r.mermaidType, "svg": r.svg,
       "width": r.width, "height": r.height, "links": links}
  except PeleError as e:
    %*{"ok": false, "type": (if e.diagramType.len > 0: %e.diagramType else: newJNull()),
       "code": e.code, "message": e.msg, "line": e.line, "column": e.column, "snippet": e.snippet}
  except CatchableError as e:
    %*{"ok": false, "type": nil, "code": "internal", "message": e.msg, "line": 0, "column": 0, "snippet": ""}

var drawing: Lock
initLock drawing

proc shared(s: string): cstring =
  ## A copy of `s` the caller owns until it gives it back to nimaki_free.
  result = cast[cstring](allocShared0(s.len + 1))
  if s.len > 0: copyMem(result, unsafeAddr s[0], s.len)

proc nimaki_render(request: cstring): cstring {.exportc, dynlib, cdecl.} =
  var text: string
  try:
    let req = if request.isNil: newJNull() else: parseJson($request)
    withLock drawing:
      text = $answer(req)
  except CatchableError as e:
    text = $(%*{"ok": false, "type": nil, "code": "request", "message": "the request is not JSON: " & e.msg,
                "line": 0, "column": 0, "snippet": ""})
  shared(text)

proc nimaki_free(answer: cstring) {.exportc, dynlib, cdecl.} =
  if not answer.isNil: deallocShared(answer)

proc nimaki_pele_version(): cstring {.exportc, dynlib, cdecl.} = peleVersion
