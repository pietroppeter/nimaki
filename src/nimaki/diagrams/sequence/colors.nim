## port-of: src/diagrams/sequence/colors.ts
## port-status: conformant
##
## `toLowerCase()` is `unicode.toLower`: it differs from ASCII lowering only on characters that
## lower to ASCII letters (the Kelvin sign is `k`), which the keyword test must see as JavaScript does.
import std/[sets, strutils]
import std/unicode except strip, split, splitWhitespace
import ../../js

# Mermaid asks the browser whether the first word of a box title is a color. Pele has no browser,
# so it knows the color keywords and the rgb() and hsl() notations. Other functions, such as calc()
# and var(), are not recognized.
const KEYWORDS =
  "aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood " &
  "cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray " &
  "darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen " &
  "darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue " &
  "firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew " &
  "hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan " &
  "lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray " &
  "lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue " &
  "mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred " &
  "midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid " &
  "palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple " &
  "rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue " &
  "slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white " &
  "whitesmoke yellow yellowgreen transparent currentcolor inherit initial unset revert " &
  "accentcolor accentcolortext activetext buttonborder buttonface buttontext canvas canvastext field fieldtext " &
  "graytext highlight highlighttext linktext mark marktext selecteditem selecteditemtext visitedtext " &
  "activeborder activecaption appworkspace background buttonhighlight buttonshadow captiontext inactiveborder " &
  "inactivecaption inactivecaptiontext infobackground infotext menu menutext scrollbar threeddarkshadow threedface " &
  "threedhighlight threedlightshadow threedshadow window windowframe windowtext"

let keywords = toHashSet(KEYWORDS.split(' '))

const
  K_Bad = 0
  K_Number = 1
  K_Percent = 2
  K_Angle = 3
  K_None = 4

func digitsAt(s: string, i: int): int =
  var j = i
  while j < s.len and s[j] in Digits: inc j
  j

func reTerm(term: string): (bool, string) =
  ## /^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?(%|deg|grad|rad|turn)?$/i: whether it matches,
  ## and the unit as written ("" when there is none).
  var i = 0
  if i < term.len and term[i] in {'+', '-'}: inc i
  let d = digitsAt(term, i)
  if d > i:
    i = d
    if i < term.len and term[i] == '.' and digitsAt(term, i + 1) > i + 1: i = digitsAt(term, i + 1)
  elif i < term.len and term[i] == '.' and digitsAt(term, i + 1) > i + 1:
    i = digitsAt(term, i + 1)
  else:
    return (false, "")
  if i < term.len and term[i] in {'e', 'E'}:
    var j = i + 1
    if j < term.len and term[j] in {'+', '-'}: inc j
    let k = digitsAt(term, j)
    if k > j: i = k
  let rest = term[i .. ^1]
  if rest == "": return (true, "")
  if rest.toLowerAscii in ["%", "deg", "grad", "rad", "turn"]: return (true, rest)
  (false, "")

func kind(term: string): int =
  if unicode.toLower(term) == "none": return K_None
  let (ok, unit) = reTerm(term)
  if not ok: return K_Bad
  if unit == "": K_Number elif unit == "%": K_Percent else: K_Angle

func isAlpha(term: string, modern: bool): bool =
  let k = kind(term)
  k == K_Number or k == K_Percent or (modern and k == K_None)

func splitSpaces(s: string): seq[string] =
  ## s.split(/\s+/)
  var part = ""
  var i = 0
  while i < s.len:
    let n = spaceLenAt(s, i)
    if n > 0:
      result.add part
      part = ""
      i += n
      while true:
        let m = spaceLenAt(s, i)
        if m == 0: break
        i += m
    else:
      part.add s[i]
      inc i
  result.add part

func isFunction(color: string): bool =
  let hsl = color.startsWith("hsl")
  let open = color.find('(')
  let name = color[0 ..< open]
  if name != "rgb" and name != "rgba" and name != "hsl" and name != "hsla": return false
  if utf16Len(color) > 120 or color.find(')') != color.len - 1: return false
  let inner = jsTrim(color[open + 1 ..< color.len - 1])
  var parts: seq[string]
  var alpha = ""
  var hasAlpha = false
  let legacy = ',' in inner
  if legacy:
    for s in inner.split(','): parts.add jsTrim(s)
    if parts.len == 4:
      alpha = parts.pop()
      hasAlpha = true
  else:
    let slash = inner.split('/')
    if slash.len > 2: return false
    parts = splitSpaces(jsTrim(slash[0]))
    if slash.len == 2:
      alpha = jsTrim(slash[1])
      hasAlpha = true
  if parts.len != 3 or (hasAlpha and not isAlpha(alpha, not legacy)): return false
  var kinds: seq[int]
  for part in parts: kinds.add kind(part)
  if legacy:
    if hsl: return (kinds[0] == K_Number or kinds[0] == K_Angle) and kinds[1] == K_Percent and kinds[2] == K_Percent
    return (kinds[0] == K_Number or kinds[0] == K_Percent) and kinds[1] == kinds[0] and kinds[2] == kinds[0]
  for i in 0 ..< 3:
    let k = kinds[i]
    let ok = k == K_Number or k == K_None or (if hsl and i == 0: k == K_Angle else: k == K_Percent)
    if not ok: return false
  true

proc isCssColor*(color: string): bool =
  if '(' in color: return isFunction(color)
  {.cast(noSideEffect).}:
    unicode.toLower(color) in keywords
