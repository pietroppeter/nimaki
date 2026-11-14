## nimaki in a browser: the entry point of the JavaScript build for pages (decision 0013).
## Not a port of a Pele file: it plays the part of Pele's browser bundle, which exposes `render`.
##
##   nim js -d:danger -o:docs/assets/nimaki.js src/nimaki/web.nim
##
## The script defines `globalThis.nimaki.render(text, options)`. `options` is a plain object
## with Pele's render options (`maxWidth`, `now`, `idPrefix`, `fontSize`, `padding`,
## `responsive`...). It returns `{ok: true, svg, width, height}`, or `{ok: false, code, message}`
## when nimaki cannot draw the text (a syntax error, or a type not ported yet: `unsupported`).
import std/[json, options]
import ../nimaki

when not defined(js):
  {.error: "src/nimaki/web.nim is compiled with nim js".}

proc toOptions(j: JsonNode): RenderOptions =
  if j.kind != JObject: return
  if j.hasKey("fontSize"): result.fontSize = some(j["fontSize"].getFloat)
  if j.hasKey("padding"): result.padding = some(j["padding"].getFloat)
  if j.hasKey("maxWidth"): result.maxWidth = some(j["maxWidth"].getFloat)
  if j.hasKey("idPrefix"): result.idPrefix = some(j["idPrefix"].getStr)
  if j.hasKey("responsive"): result.responsive = some(j["responsive"].getBool)
  if j.hasKey("fontFamily"): result.fontFamily = j["fontFamily"].getStr
  if j.hasKey("autoDirection"): result.autoDirection = some(j["autoDirection"].getBool)
  if j.hasKey("directionBreakpoint"): result.directionBreakpoint = some(j["directionBreakpoint"].getFloat)
  if j.hasKey("monospace"):
    for m in j["monospace"]: result.monospace.add m.getStr
  if j.hasKey("now"): result.now = j["now"].getFloat

proc renderJson(text, options: cstring): cstring {.exportc: "nimakiRenderJson".} =
  ## The text and the options (as JSON) in, the answer (as JSON) out.
  var answer: JsonNode
  try:
    let r = render($text, toOptions(parseJson($options)))
    answer = %*{"ok": true, "svg": r.svg, "width": r.width, "height": r.height}
  except PeleError as e:
    answer = %*{"ok": false, "code": e.code, "message": e.msg}
  except CatchableError as e:
    answer = %*{"ok": false, "code": "internal", "message": e.msg}
  cstring($answer)

{.emit: """
globalThis.nimaki = {
  render(text, options) {
    return JSON.parse(nimakiRenderJson(String(text), JSON.stringify(options ?? {})));
  },
};
""".}
