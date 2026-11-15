## nimaki in a browser: the entry point of the JavaScript build for pages (decision 0013).
## Not a port of a Pele file: it plays the part of Pele's browser bundle (`pele.global.js`, built
## from src/index.ts and src/lazy.ts), and gives a page the same functions under the name
## `nimaki` that the bundle gives under `pele`.
##
##   nim js -d:danger -o:nimaki.js src/nimaki/web.nim                          every type
##   nim js -d:danger -d:nimakiTypes=flowchart -o:nimaki-flowchart.js src/nimaki/web.nim
##   nim js -d:danger -d:nimakiTypes=none -o:nimaki-core.js src/nimaki/web.nim  no type
##
## - `nimaki.render(source, options)`: the SVG of Mermaid text, or of a model `parse` returned,
##   as `{type, mermaidType, svg, width, height, links}`. Text that cannot be drawn throws a
##   `nimaki.PeleError` with Pele's `code`, `line`, `column` and `snippet`.
## - `nimaki.parse(text, options)`: the model, in the shape of Pele's, to read or to draw later.
## - `nimaki.mount(element, text, options)`: draws into an element and keeps the drawing fitted
##   to it (src/nimaki/mount.nim); `nimaki.enableZoom(element, options)` (src/nimaki/zoom.nim).
## - `nimaki.detectType`, `supports`, `registered`, `forgetTextWidths`, and Pele's lazy entry
##   point's `load`, `renderAsync` and `mountAsync`.
## - `nimaki.metricsMeasurer`: the measurer of the build and of Node. In a browser the default
##   measurer is the canvas, as in Pele; a page that must draw the same bytes as a build passes
##   this one.
## - `nimaki.version`, and `nimaki.peleVersion`, the Pele it draws as.
##
## A build draws the types of `-d:nimakiTypes` (`nimaki/selection`; all by default). Several
## builds can share a page: the first one makes `globalThis.nimaki`, and each later one joins it,
## so that `render`, `parse` and `mount` go to the build that draws the text's type. `load(type)`
## is Pele's lazy loading: for a type that no build on the page draws, it adds the script
## `nimaki-<type>.js` from the folder of the first build's own script, and resolves when that
## build has joined. This is how a page draws a flowchart with only the flowchart's file, as Pele's
## `dist/esm/` does with its chunks (post *Why nimaki.js is big*).
import std/jsffi
import ../nimaki
import jsapi, mount, zoom, detect
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

proc newArray(): JsObject {.importjs: "([])".}
proc push(a: JsObject, v: cstring) {.importjs: "#.push(#)".}
proc webTypes(): JsObject {.exportc: "nimakiWebTypes".} =
  ## The diagram types this build draws, as a JavaScript array.
  result = newArray()
  for t in diagramTypes():
    if registered(t): result.push cstring(t)
proc webKnownTypes(): JsObject {.exportc: "nimakiWebKnownTypes".} =
  ## Every diagram type there is a build of: the names `load` may fetch.
  result = newArray()
  for t in diagramTypes(): result.push cstring(t)

{.emit: """
(() => {
  // The page's nimaki: made by the first build that runs, joined by the others.
  const hub = globalThis.nimaki && globalThis.nimaki.nimakiBuilds ? globalThis.nimaki : (() => {
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
    const builds = [];
    const models = new WeakMap();   // a model parse returned -> the build that parsed it
    const pending = new Map();      // a type being loaded -> its promise
    let folder = null;              // where the first build's script came from
    try {
      const src = document.currentScript && document.currentScript.src;
      if (src) folder = src.slice(0, src.lastIndexOf('/') + 1);
    } catch (e) { /* not in a page */ }
    const first = () => builds[0];
    const typeOf = (text) => { try { return first().detectType(text); } catch (e) { return null; } };
    const buildFor = (type) => (type === null ? null : builds.find((b) => b.registered(type))) ?? first();
    const render = (source, options = {}) => {
      if (typeof source === 'string') return buildFor(typeOf(source)).render(source, options);
      const b = source !== null && typeof source === 'object' ? models.get(source) : undefined;
      return (b ?? first()).render(source, options);
    };
    const parse = (text, options = {}) => {
      const b = buildFor(typeOf(String(text)));
      const model = b.parse(text, options);
      if (model !== null && typeof model === 'object') models.set(model, b);
      return model;
    };
    const engine = { parse, render };
    const registered = (type) => builds.some((b) => b.registered(type));
    const load = (type) => {
      if (type === null || type === undefined) return Promise.resolve(false);
      type = String(type);
      if (registered(type)) return Promise.resolve(true);
      if (folder === null || !first().knownTypes.includes(type)) return Promise.resolve(false);
      let promise = pending.get(type);
      if (promise === undefined) {
        promise = new Promise((resolve, reject) => {
          const script = document.createElement('script');
          script.src = folder + 'nimaki-' + type + '.js';
          script.onload = () => resolve(registered(type));
          script.onerror = () => { pending.delete(type); reject(new Error('Could not load ' + script.src)); };
          document.head.appendChild(script);
        });
        pending.set(type, promise);
      }
      return promise;
    };
    const hub = {
      nimakiBuilds: builds,
      join: (build) => { builds.push(build); },
      PeleError,
      render,
      parse,
      mount: (element, text, options = {}) => first().mount(engine, element, text, options),
      enableZoom: (element, options = {}) => first().enableZoom(element, options),
      frame: (natural, box, scale, x, y) => first().frame(natural, box, scale, x, y),
      detectType: (text) => first().detectType(text),
      supports: (text) => builds.some((b) => b.supports(text)),
      registered,
      forgetTextWidths: () => { for (const b of builds) b.forgetTextWidths(); },
      // Pele's lazy entry point (src/lazy.ts).
      load,
      renderAsync: async (text, options = {}) => { await load(typeOf(String(text))); return render(text, options); },
      mountAsync: async (element, text, options = {}) => { await load(typeOf(String(text))); return hub.mount(element, text, options); },
    };
    return hub;
  })();
  const call = (f) => {
    try {
      return f();
    } catch (e) {
      if (e && e.peleError) throw new hub.PeleError(e.message, e.code, e);
      throw e;
    }
  };
  const build = {
    types: nimakiWebTypes(),
    knownTypes: nimakiWebKnownTypes(),
    render: (source, options) => {
      const drawn = call(() => nimakiWebRender(source, options ?? {}));
      if (drawn === null) throw new TypeError('render() takes diagram text or a model that parse() returned.');
      return drawn;
    },
    parse: (text, options) => call(() => nimakiWebParse(String(text), options ?? {})),
    mount: (engine, element, text, options) => nimakiWebMount(engine, element, String(text), options ?? {}),
    enableZoom: (element, options) => nimakiWebEnableZoom(element, options ?? {}),
    frame: (natural, box, scale, x, y) => nimakiWebFrame(natural, box, scale, x, y),
    detectType: (text) => nimakiWebDetectType(String(text)),
    supports: (text) => nimakiWebSupports(String(text)),
    registered: (type) => nimakiWebRegistered(String(type)),
    forgetTextWidths: () => nimakiWebForget(),
  };
  hub.join(build);
  if (hub.nimakiBuilds.length === 1) {
    hub.metricsMeasurer = { width: (text, size, style) => nimakiWebMetricsWidth(String(text), size, style) };
    hub.version = nimakiWebVersion();
    hub.peleVersion = nimakiWebPeleVersion();
    globalThis.nimaki = hub;
  }
})();
""".}
