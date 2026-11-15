## port-of: src/text/measurer.ts
## port-status: conformant
##
## Both of Pele's measurers. `metricsMeasurer` estimates widths from a table of Arial's advances
## and runs everywhere. `canvasMeasurer` asks a browser's canvas for the width of the text in
## the page's own font; it exists only in the JavaScript build, and there `defaultMeasurer` takes
## it when there is a canvas (in a browser), as Pele does. In the C build, and in Node, the
## default is `metricsMeasurer`.
import std/strutils
when defined(js):
  import std/[jsffi, tables]
import metrics
import ../js

type
  TextMeasurer* = object
    width*: proc (text: string, size: float, style: int): float {.noSideEffect, gcsafe.}

const
  # Pele's `const enum Style`: bits, combined as an `int`.
  Bold* = 1
  Italic* = 2
  Mono* = 4
  Sub* = 8
  Sup* = 16
  Underline* = 32

const SMALLER = 1.2 ## Approximate divisor for CSS font-size="smaller".

func parseInt36(s: string): int =
  for c in s:
    result = result * 36 + (if c in Digits: ord(c) - ord('0') else: ord(c) - ord('a') + 10)

func unpack(packed: string): array[95, uint16] =
  for i in 0 ..< 95:
    result[i] = uint16(parseInt36(packed[i * 2 .. i * 2 + 1]))

const regular = unpack(metrics.REGULAR)
const bold = unpack(metrics.BOLD)

func isWide(c: int): bool =
  (c >= 0x1100 and c <= 0x115f) or
    (c >= 0x2e80 and c <= 0xa4cf) or
    (c >= 0xac00 and c <= 0xd7a3) or
    (c >= 0xf900 and c <= 0xfaff) or
    (c >= 0xfe30 and c <= 0xfe4f) or
    (c >= 0xff00 and c <= 0xff60) or
    (c >= 0xffe0 and c <= 0xffe6) or
    (c >= 0xd800 and c <= 0xdbff)

func isZeroWidth(c: int): bool =
  c == 0xad or
    (c >= 0x300 and c <= 0x36f) or
    (c >= 0x200b and c <= 0x200f) or
    (c >= 0xdc00 and c <= 0xdfff) or
    (c >= 0xfe00 and c <= 0xfe0f) or
    c == 0xfeff

func metricsWidth(text: string, size: float, style: int): float =
  ## Estimates widths from a table of Arial advances. Used where no canvas is available.
  let mono = (style and Mono) != 0
  let eff = if (style and (Sub or Sup)) != 0: size / SMALLER else: size
  let table = if (style and Bold) != 0: bold else: regular
  var units = 0.0
  for c in codeUnits(text):
    if c < 32: continue
    if c < 127: units += (if mono: 600.0 else: float(table[c - 32]))
    elif isZeroWidth(c): continue
    elif isWide(c): units += (if mono: 1200.0 else: 1000.0)
    else: units += (if mono: 600.0 else: 580.0)
  (units * eff) / 1000

let metricsMeasurer* = TextMeasurer(width: metricsWidth)

when defined(js):
  proc isNil(x: JsObject): bool {.importjs: "(# == null)".}
  proc canvasContext(): JsObject {.importjs: """(() => {
    const g = globalThis;
    try {
      if (g.OffscreenCanvas) return new g.OffscreenCanvas(1, 1).getContext('2d');
      if (g.document) return g.document.createElement('canvas').getContext('2d');
    } catch {
      return null;
    }
    return null;
  })()""".}
    ## Pele's `context()`: a 2D context of an OffscreenCanvas, or of a canvas of the document.
  proc canvasFonts(): JsObject {.importjs: "(globalThis.document?.fonts ?? globalThis.fonts)".}
  proc faceCount(fonts: JsObject): JsObject {.importjs: "(#?.size)".}
  proc sameCount(a, b: JsObject): bool {.importjs: "(# === #)".}
  proc hasFont(fonts: JsObject, font, text: cstring): bool {.importjs: """((fonts, font, text) => {
    try {
      return fonts?.check(font, text) ?? true;
    } catch {
      return true;
    }
  })(#, #, #)""".}
    ## Whether the canvas has the font the text is in, rather than a fallback while it loads. A
    ## width measured with a fallback is not kept. One whose font cannot be checked is.
  proc setFont(ctx: JsObject, font: cstring) {.importjs: "#.font = #".}
  proc measureText(ctx: JsObject, text: cstring): float {.importjs: "#.measureText(#).width".}
  proc jsNumberText(x: float): cstring {.importjs: "String(#)".}

  const MAX_CACHED = 20000

  type CanvasCache = ref object
    ctx: JsObject
    fontFamily, monoFamily: string
    caches: Table[string, Table[string, float]]
    currentFont: string
    faces: JsObject   ## the number of fonts the document had when the widths were measured

  proc canvasWidth(m: CanvasCache, text: string, size: float, style: int): float =
    let fonts = canvasFonts()
    let count = faceCount(fonts)
    if not sameCount(count, m.faces):
      # A font that was not in the document was measured with a fallback, though it counts as
      # loaded: a new font makes every width measured before it suspect.
      m.faces = count
      m.caches.clear()
    let eff = if (style and (Sub or Sup)) != 0: size / SMALLER else: size
    let font =
      (if (style and Italic) != 0: "italic " else: "") &
      (if (style and Bold) != 0: "bold " else: "") &
      $jsNumberText(eff) & "px " &
      (if (style and Mono) != 0: m.monoFamily else: m.fontFamily)
    if font notin m.caches: m.caches[font] = initTable[string, float]()
    if text in m.caches[font]: return m.caches[font][text]
    if font != m.currentFont:
      m.currentFont = font
      setFont(m.ctx, cstring(font))
    result = measureText(m.ctx, cstring(text))
    if hasFont(fonts, cstring(font), cstring(text)):
      if m.caches[font].len >= MAX_CACHED: m.caches[font].clear()
      m.caches[font][text] = result

  proc canvasMeasurer*(fontFamily: string, monoFamily = "monospace"): TextMeasurer =
    ## Widths from the browser's canvas, in the page's own fonts, kept until the fonts change.
    ## `width` is nil where there is no canvas (Pele returns null).
    let ctx = canvasContext()
    if ctx.isNil: return
    let m = CanvasCache(ctx: ctx, fontFamily: fontFamily, monoFamily: monoFamily,
                        faces: faceCount(canvasFonts()))
    TextMeasurer(width: proc (text: string, size: float, style: int): float {.noSideEffect, gcsafe.} =
      {.cast(noSideEffect), cast(gcsafe).}:
        canvasWidth(m, text, size, style))

  var shared: Table[string, TextMeasurer]

  proc defaultMeasurer*(fontFamily = "sans-serif", monoFamily = "monospace"): TextMeasurer =
    ## The canvas where there is one, otherwise the metrics, one for each pair of fonts. An
    ## empty name is Pele's undefined, the default.
    let family = if fontFamily.len == 0: "sans-serif" else: fontFamily
    let mono = if monoFamily.len == 0: "monospace" else: monoFamily
    {.cast(noSideEffect), cast(gcsafe).}:
      let key = family & "\n" & mono
      if key notin shared:
        let canvas = canvasMeasurer(family, mono)
        shared[key] = if canvas.width != nil: canvas else: metricsMeasurer
      result = shared[key]

  proc forgetTextWidths*() =
    ## Widths measured before a font finished loading are those of its fallback.
    shared.clear()
else:
  proc defaultMeasurer*(fontFamily = "sans-serif", monoFamily = "monospace"): TextMeasurer =
    ## No canvas outside a browser: the metrics, as Pele's default is in Node.
    metricsMeasurer

  proc forgetTextWidths*() =
    ## Nothing to forget: the metrics do not depend on the page's fonts.
    discard
