## nimaki in a browser: the entry point of the JavaScript build for pages (decision 0013).
## Not a port of a Pele file: it plays the part of Pele's browser bundle (`pele.global.js`, built
## from src/index.ts and src/lazy.ts), and gives a page the same functions under the name
## `nimaki` that the bundle gives under `pele`.
##
##   nim js -d:danger -o:docs/assets/nimaki.js src/nimaki/web.nim
##
## - `nimaki.render(source, options)`: the SVG of Mermaid text, or of a model `parse` returned,
##   as `{type, mermaidType, svg, width, height, links}`. Text that cannot be drawn throws a
##   `nimaki.PeleError` with Pele's `code`, `line`, `column` and `snippet`.
## - `nimaki.parse(text, options)`: the model, in the shape of Pele's, to read or to draw later.
## - `nimaki.mount(element, text, options)`: draws into an element and keeps the drawing fitted
##   to it (src/nimaki/mount.nim); `nimaki.enableZoom(element, options)` (src/nimaki/zoom.nim).
## - `nimaki.detectType`, `supports`, `registered`, `forgetTextWidths`, and Pele's lazy entry
##   point's `load`, `renderAsync` and `mountAsync`: nimaki.js holds every type already, so
##   `load` only says whether a type is drawn.
## - `nimaki.metricsMeasurer`: the measurer of the build and of Node. In a browser the default
##   measurer is the canvas, as in Pele; a page that must draw the same bytes as a build passes
##   this one.
## - `nimaki.version`, and `nimaki.peleVersion`, the Pele it draws as.
import std/jsffi
import ../nimaki
import jsapi, mount, zoom
import text/measurer

when not defined(js):
  {.error: "src/nimaki/web.nim is compiled with nim js".}

proc newWeakMap(): JsObject {.importjs: "new WeakMap()".}
proc weakGet(m, k: JsObject): JsObject {.importjs: "#.get(#)".}
proc weakSet(m, k, v: JsObject) {.importjs: "#.set(#, #)".}

var parsedModels = newWeakMap()
  ## the Nim model behind each model `parse` returned, for `render`

proc webParse(text: cstring, options: JsObject): JsObject {.exportc: "nimakiWebParse".} =
  ## The model, as Pele's `parse` returns it (src/nimaki/modeljson.nim); what nimaki parsed
  ## stays behind it, for `render`.
  var m: ParsedModel
  try:
    m = parse(wtf8(text), toOptions(options))
  except PeleError as e:
    throwPele(e)
  result = modelObject(m)
  parsedModels.weakSet(result, toJs(m))

proc webRender(source: JsObject, options: JsObject): JsObject {.exportc: "nimakiWebRender".} =
  ## Text or a model in, Pele's result out; null for a value that is neither.
  try:
    if source.isString:
      return resultOf(render(wtf8(source.to(cstring)), toOptions(options)))
    if source.isUndef or not source.isObject: return jsNull
    let found = parsedModels.weakGet(source)
    if found.isUndef: return jsNull
    result = resultOf(render(found.to(ParsedModel), toOptions(options)))
  except PeleError as e:
    throwPele(e)

proc webDetectType(text: cstring): JsObject {.exportc: "nimakiWebDetectType".} = orNull(detectType(wtf8(text)))
proc webSupports(text: cstring): bool {.exportc: "nimakiWebSupports".} = supports(wtf8(text))
proc webRegistered(kind: cstring): bool {.exportc: "nimakiWebRegistered".} = registered($kind)
proc webForget() {.exportc: "nimakiWebForget".} = forgetTextWidths()
proc webMetricsWidth(text: cstring, size: float, style: int): float {.exportc: "nimakiWebMetricsWidth".} =
  metricsMeasurer.width(wtf8(text), size, style)
proc webMount(engine, element: JsObject, text: cstring, options: JsObject): JsObject {.exportc: "nimakiWebMount".} =
  mountWith(engine, element, text, options)
proc webEnableZoom(element, options: JsObject): JsObject {.exportc: "nimakiWebEnableZoom".} =
  enableZoom(element, options)
proc webFrame(natural, box: JsObject, scale, x, y: float): JsObject {.exportc: "nimakiWebFrame".} =
  frameJs(natural, box, scale, x, y)
proc webVersion(): cstring {.exportc: "nimakiWebVersion".} = cstring(nimakiVersion)
proc webPeleVersion(): cstring {.exportc: "nimakiWebPeleVersion".} = cstring(peleVersion)

{.emit: """
(() => {
  // Pele's PeleError (src/errors.ts): an Error with the code, and where the text is wrong.
  class PeleError extends Error {
    constructor(message, code, at = {}) {
      super(message);
      this.name = 'PeleError';
      this.code = code;
      for (const k of ['type', 'mermaidType', 'line', 'column', 'snippet']) {
        if (at[k] !== undefined && at[k] !== null) this[k] = at[k];
      }
    }
  }
  const call = (f) => {
    try {
      return f();
    } catch (e) {
      if (e && e.peleError) throw new PeleError(e.message, e.code, e);
      throw e;
    }
  };
  const render = (source, options = {}) => {
    const drawn = call(() => nimakiWebRender(source, options ?? {}));
    if (drawn === null) throw new TypeError('render() takes diagram text or a model that parse() returned.');
    return drawn;
  };
  const parse = (text, options = {}) => call(() => nimakiWebParse(String(text), options ?? {}));
  const engine = { parse, render };
  const mount = (element, text, options = {}) => nimakiWebMount(engine, element, String(text), options ?? {});
  const detectType = (text) => nimakiWebDetectType(String(text));
  const load = (type) => Promise.resolve(type !== null && type !== undefined && nimakiWebRegistered(String(type)));
  globalThis.nimaki = {
    PeleError,
    render,
    parse,
    mount,
    enableZoom: (element, options = {}) => nimakiWebEnableZoom(element, options ?? {}),
    frame: (natural, box, scale, x, y) => nimakiWebFrame(natural, box, scale, x, y),
    detectType,
    supports: (text) => nimakiWebSupports(String(text)),
    registered: (type) => nimakiWebRegistered(String(type)),
    forgetTextWidths: () => nimakiWebForget(),
    metricsMeasurer: { width: (text, size, style) => nimakiWebMetricsWidth(String(text), size, style) },
    // Pele's lazy entry point (src/lazy.ts): every type is in this file, so there is nothing to load.
    load,
    renderAsync: async (text, options = {}) => render(text, options),
    mountAsync: async (element, text, options = {}) => mount(element, text, options),
    version: nimakiWebVersion(),
    peleVersion: nimakiWebPeleVersion(),
  };
})();
""".}
