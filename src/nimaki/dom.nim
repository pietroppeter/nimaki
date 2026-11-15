## dom: the few JavaScript operations that the browser side (window.nim, zoom.nim, mount.nim)
## needs on values it does not know the type of: an element, a style, an event. Not a port of a
## Pele file: Pele's TypeScript writes these with its own operators (`===`, `?.`, `??`, `in`).
## Each one keeps JavaScript's meaning, so that a fake element of a test, which has only some of
## an element's fields, is treated as Pele treats it.
when not defined(js):
  {.error: "src/nimaki/dom.nim is for the JavaScript build".}

import std/jsffi
export jsffi

proc isUndefined*(x: JsObject): bool {.importjs: "(# === undefined)".}
proc isNullish*(x: JsObject): bool {.importjs: "(# == null)".}
proc isFalse*(x: JsObject): bool {.importjs: "(# === false)".}
proc isTrue*(x: JsObject): bool {.importjs: "(# === true)".}
proc isObject*(x: JsObject): bool {.importjs: "((x) => typeof x === 'object' && x !== null)(#)".}
proc isFunction*(x: JsObject): bool {.importjs: "(typeof # === 'function')".}
proc same*(a, b: JsObject): bool {.importjs: "(# === #)".}
proc positive*(x: JsObject): bool {.importjs: "(# > 0)".}
  ## `x > 0`, false for undefined and NaN, as JavaScript says.
proc truthy*(x: JsObject): bool {.importjs: "(!!#)".}
proc orElse*(a, b: JsObject): JsObject {.importjs: "(# ?? #)".}
proc num*(x: JsObject): float {.importjs: "Number(#)".}
proc numOr0*(x: JsObject): float {.importjs: "(Number(#) || 0)".}
proc floatOr0*(x: JsObject): float {.importjs: "(parseFloat(#) || 0)".}
proc str*(x: JsObject): cstring {.importjs: "String(#)".}
proc jsTrimmed*(x: JsObject): cstring {.importjs: "String(#).trim()".}
proc firstChild*(element: JsObject): JsObject {.importjs: "(#.firstElementChild ?? null)".}
proc copyOf*(x: JsObject): JsObject {.importjs: "({ ...# })".}
  ## A shallow copy, as `{ ...x }`.
proc without*(x: JsObject, a, b, c: cstring): JsObject {.importjs:
  "((o, a, b, c) => { const r = { ...o }; delete r[a]; delete r[b]; delete r[c]; return r; })(#, #, #, #)".}
  ## `const { a, b, c, ...rest } = x`: the rest.
proc errorMessage*(error: JsObject): cstring {.importjs: "((e) => e instanceof Error ? e.message : String(e))(#)".}
proc caughtError*(): JsObject {.importjs: "(lastJSError)".}
  ## What the `except` being run caught, as JavaScript threw it: a Nim exception or any other
  ## value (Nim's own `getCurrentException` is nil for one that is not Nim's).
proc jsThrow*(x: JsObject) {.importjs: "throw #".}
proc invoke*(obj: JsObject, name: cstring): JsObject {.importjs: "#[#]()", discardable.}
  ## `obj.name()`, for a method whose name is also a proc or a variable here.
proc invoke*(obj: JsObject, name: cstring, a: JsObject): JsObject {.importjs: "#[#](#)", discardable.}
proc call0*(f: JsObject): JsObject {.importjs: "#()".}
proc call1*(f, a: JsObject): JsObject {.importjs: "#(#)".}
proc newWeakMap*(): JsObject {.importjs: "new WeakMap()".}
proc newWeakRef*(x: JsObject): JsObject {.importjs: "new WeakRef(#)".}
proc deref*(x: JsObject): JsObject {.importjs: "#.deref()".}
proc newMap*(): JsObject {.importjs: "new Map()".}
proc construct1*(ctor, a: JsObject): JsObject {.importjs: "new #(#)".}
proc randomId*(): cstring {.importjs: "Math.random().toString(36).slice(2, 7)".}
proc globalThisObject*(): JsObject {.importjs: "(globalThis)".}
proc instanceOfNode*(view, target: JsObject): bool {.importjs: "((v, t) => t instanceof v.Node)(#, #)".}

template fn*(body: untyped): JsObject =
  ## A Nim closure as a JavaScript function value, for a listener or a callback.
  toJs(body)
proc mathMax*(a, b: float): float {.importjs: "Math.max(#, #)".}
proc mathMin*(a, b: float): float {.importjs: "Math.min(#, #)".}
proc mathHypot*(a, b: float): float {.importjs: "Math.hypot(#, #)".}
proc mathAbs*(a: float): float {.importjs: "Math.abs(#)".}
proc pow2*(x: float): float {.importjs: "(2 ** #)".}
proc numStr*(x: float): cstring {.importjs: "String(#)".}
  ## A number as a template literal writes it: `${x}`.
proc numberOr*(x: JsObject, default: float): float {.importjs: "(# ?? #)".}
proc toArray*(x: JsObject): JsObject {.importjs: "[...#]".}
proc len*(x: JsObject): int {.importjs: "#.length".}
proc optCall*(obj: JsObject, name: cstring, arg: JsObject) {.importjs: "#[#]?.(#)".}
  ## `obj.name?.(arg)`.
proc defineGetter*(obj: JsObject, name: cstring, getter: JsObject) {.importjs:
  "Object.defineProperty(#, #, { get: #, enumerable: true, configurable: true })".}
proc setAttr*(x: JsObject, name: cstring, value: cstring) {.importjs: "#.setAttribute(#, #)".}
proc listen*(x: JsObject, kind: cstring, f: JsObject, how: JsObject) {.importjs: "#.addEventListener(#, #, #)".}
proc unlisten*(x: JsObject, kind: cstring, f: JsObject, how: JsObject) {.importjs: "#.removeEventListener(#, #, #)".}
proc jsObj*(): JsObject {.importjs: "({})".}
