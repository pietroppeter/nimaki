## port-of: src/svg/ink.ts
## port-status: draft
import std/[strutils, sets, tables]
from std/math import PI, isNaN, `mod`
import ../jsmath
import ../js, ../jsregex

const DARK = toHashSet("black blue blueviolet brown crimson darkblue darkcyan darkgreen darkmagenta darkolivegreen darkorchid darkred darkslateblue darkslategray darkviolet dimgray firebrick forestgreen green indigo maroon mediumblue mediumslateblue mediumvioletred midnightblue navy olive purple rebeccapurple royalblue saddlebrown seagreen sienna slateblue steelblue teal".split(' '))
  ## Named colors that #fff contrasts with more than #1f1f1f does, and the rest.
const LIGHT = toHashSet("aliceblue antiquewhite aqua aquamarine azure beige bisque blanchedalmond burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk cyan darkgoldenrod darkgray darkkhaki darkorange darksalmon darkseagreen darkturquoise deeppink deepskyblue dodgerblue floralwhite fuchsia gainsboro ghostwhite gold goldenrod gray greenyellow honeydew hotpink indianred ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightpink lightsalmon lightseagreen lightskyblue lightslategray lightsteelblue lightyellow lime limegreen linen magenta mediumaquamarine mediumorchid mediumpurple mediumseagreen mediumspringgreen mediumturquoise mintcream mistyrose moccasin navajowhite oldlace olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue red rosybrown salmon sandybrown seashell silver skyblue slategray snow springgreen tan thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen".split(' '))

const ON_LIGHT* = "var(--pele-fg-on-light,#1f1f1f)"
const ON_DARK* = "var(--pele-fg-on-dark,#fff)"

const
  RE_FILL = jsre"""/[";]fill:([^;"]*)/"""
  RE_OPACITIES = jsre"""/[";](?:fill-)?opacity:([^;"]*)/g"""
  RE_HEX = jsre"/^#(?:[\da-f]{3,4}|[\da-f]{6}|[\da-f]{8})$/i"
  RE_FUNCTION = jsre"/^(rgba?|hsla?)\(([^()]*)\)$/i"
  RE_NUMBER = jsre"/^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?(%|deg|grad|rad|turn)?$/i"

func linear(c: float): float = (if c <= 0.04045: c / 12.92 else: pow((c + 0.055) / 1.055, 2.4))
func luminance(r, g, b: float): float = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
func clamp01(n: float): float = jsMin(jsMax(n, 0), 1)

let EVEN = sqrt(1.05 * (luminance(31 / 255, 31 / 255, 31 / 255) + 0.05)) - 0.05
  ## Luminance where #1f1f1f and #fff have equal contrast.

func amount(raw: string, full: float): float =
  let m = RE_NUMBER.exec(raw)
  if not m.found or (m[1] != "" and m[1] != "%"): return NaN
  clamp01(jsParseFloat(raw) / (if m[1] != "": 100.0 else: full))

func hue(raw: string): float =
  let m = RE_NUMBER.exec(raw)
  if not m.found or m[1] == "%": return NaN
  let unit = m[1].toLowerAscii
  let n = jsParseFloat(raw)
  if unit == "turn": n * 360 elif unit == "rad": (n * 180) / PI elif unit == "grad": n * 0.9 else: n

func args(body: string, hsl: bool): (bool, seq[string]) =
  ## The comma syntax takes no `none`, rgb() channels all or none in %, and hsl() saturation and
  ## lightness in %.
  let legacy = ',' in body
  var main = body
  var alpha = ""
  var hasAlpha = false
  if not legacy:
    let parts = body.split('/')
    if parts.len > 2: return
    main = parts[0]
    if parts.len == 2:
      alpha = parts[1]
      hasAlpha = true
  var list = jsTrim(main).split(if legacy: jsre"/\s*,\s*/" else: jsre"/\s+/")
  if (if legacy: list.len < 3 or list.len > 4 else: list.len != 3): return
  if hasAlpha: list.add jsTrim(alpha)
  if not legacy:
    for c in list.mitems:
      if c == "none": c = "0"
    return (true, list)
  var percent = 0
  for c in list[(if hsl: 1 else: 0) ..< 3]:
    if c.endsWith("%"): inc percent
  if percent == (if hsl: 2 else: 3) or (not hsl and percent == 0): (true, list) else: (false, @[])

func plainColor*(raw: string): bool =
  ## A hex color or one of CSS's named colors.
  let value = jsTrim(raw).toLowerAscii
  let name = value.replace("grey", "gray")
  RE_HEX.test(value) or name in DARK or name in LIGHT or value == "transparent" or value == "currentcolor"

proc color(raw: string): (bool, float, float) =
  ## Luminance and alpha; named colors use 0 or 1 to preserve the contrast choice.
  let value = jsTrim(raw).toLowerAscii
  let name = value.replace("grey", "gray")
  if name in DARK: return (true, 0.0, 1.0)
  if name in LIGHT: return (true, 1.0, 1.0)
  if RE_HEX.test(value):
    let digits = if value.len < 6: value[1 .. ^1].replace(jsre"/./g", "$&$&") else: value[1 .. ^1]
    proc n(i: int): float = float(parseHexInt(digits[2 * i ..< 2 * i + 2])) / 255
    return (true, luminance(n(0), n(1), n(2)), if digits.len == 8: n(3) else: 1.0)
  let fn = RE_FUNCTION.exec(value)
  if not fn.found: return
  let hsl = fn[1].startsWith("hsl")
  let (ok, list) = args(fn[2], hsl)
  if not ok: return
  let alpha = if list.len == 4: amount(list[3], 1) else: 1.0
  var rgb: array[3, float]
  if not hsl:
    for i in 0 ..< 3: rgb[i] = amount(list[i], 255)
  else:
    let hh = (((hue(list[0]) mod 360) + 360) mod 360) / 30
    let s = amount(list[1], 100)
    let l = amount(list[2], 100)
    let a = s * jsMin(l, 1 - l)
    for i, k in [0.0, 8.0, 4.0]:
      let t = (k + hh) mod 12
      rgb[i] = l - a * jsMax(-1, jsMin(jsMin(t - 3, 9 - t), 1))
  let lum = luminance(rgb[0], rgb[1], rgb[2])
  if (lum + alpha).isNaN: return
  (true, lum, alpha)

func opacity(shape: string): float =
  ## How opaque a style's fill-opacity and opacity leave its fill, or NaN when either isn't a
  ## plain number.
  result = 1
  for m in RE_OPACITIES.matches(shape): result *= amount(jsTrim(m[1]), 1)

var known = initTable[string, (bool, string)]()

proc pick(shape, text: string): (bool, string) =
  let fill = RE_FILL.exec(shape)
  if not fill.found or RE_FILL.test(text): return
  let (found, lum, alpha) = color(fill[1])
  if not found: return
  # An opacity that isn't a plain number, such as calc() or var(), may still be low.
  if not (alpha * opacity(shape) >= 0.5): return
  (true, if lum > EVEN: ON_LIGHT else: ON_DARK)

proc ink*(shape: string, text = ""): (bool, string) =
  ## Styles come from resolveStyle(). Fills below half opacity depend on an unknown background.
  ## (false, "") for undefined.
  let key = shape & "\0" & text
  if key in known: return known[key]
  if known.len > 1000: known.clear()
  result = pick(shape, text)
  known[key] = result

proc paints*(shape: string): bool =
  ## Unknown fill colors and opacities are treated as opaque.
  let fill = jsTrim(RE_FILL.exec(shape).groupOr(1, "")).toLowerAscii
  if fill == "" or fill == "none" or fill == "transparent": return false
  let scale = opacity(shape)
  let (found, _, alpha) = color(fill)
  (if found: alpha else: 1.0) * (if scale.isNaN: 1.0 else: scale) > 0

proc inkFill*(shape, text: string, fallback = ""): string =
  let (ok, c) = ink(shape, text)
  let color = if ok: c else: fallback
  if color != "": " fill=\"" & color & "\"" else: ""
