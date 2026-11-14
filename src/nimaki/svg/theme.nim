## port-of: src/svg/theme.ts
## port-status: conformant
import std/[strutils, tables, unicode]
import builder
import ../js

# Private aliases set once on the root element, so each use is short and the public
# --pele-* tokens keep their fallbacks. The text color is set as well: an icon is drawn in
# currentColor, which would otherwise be whatever color the page gives the diagram's
# container.
const ROOT_STYLE* =
  "--_bg:var(--pele-bg,#fff);--_fg:var(--pele-fg,#1f1f1f);--_m:var(--pele-muted,#6e6e6e);" &
  "--_l:var(--pele-line,#1f1f1f);--_s:var(--pele-surface,#f3f3f3);--_a:var(--pele-surface-alt,#e6e6e6);" &
  "--_b:var(--pele-border,#8a8a8a);--_c:var(--pele-accent,#5b7bd5);color:var(--_fg)"

const FONT_MONO* = "var(--_fm)"
const RADIUS* = "var(--pele-radius,4px)"

const ROUNDED* = " style=\"rx:var(--_r)\""
  ## Use CSS for rx variables to support older browsers. Put the default first so diagram
  ## styles can override it.

func setsFill*(shape: string): bool =
  ## Expects a shape style from resolveStyle(). /[";]fill:/
  shape.contains("\"fill:") or shape.contains(";fill:")

func rounded*(attrs: string): string =
  let at = attrs.find(" style=\"")
  if at < 0: attrs & ROUNDED
  else: attrs[0 ..< at + 8] & "rx:var(--_r);" & attrs[at + 8 .. ^1]

const CRITICAL* = "var(--pele-critical,#e45756)"
  ## The color of what a diagram marks as critical. It is not one of the series colors, as a
  ## theme may put those in any order.

func isLetterOrNumber(s: string, i: int): (bool, int) =
  ## [\p{L}\p{N}] at byte i. \p{L} is Nim's Unicode isAlpha; \p{N} is approximated by the
  ## ASCII digits and the letters' table (a gap noted in the porting guide).
  let (cp, size) = codePointAt(s, i)
  if cp < 128: return (char(cp) in {'a'..'z', 'A'..'Z', '0'..'9'}, size)
  (Rune(cp).isAlpha, size)

func familyEnd(s: string, i: int): int =
  ## FAMILY at byte i: "..." | '...' | [\p{L}\p{N}_-][\p{L}\p{N}_ .-]*; its end or -1.
  const forbidden = {'"', '\'', '\\', '\n', '<', '>', '{', '}', '(', ')', ';', ':', '@'}
  if i >= s.len: return -1
  if s[i] in {'"', '\''}:
    let q = s[i]
    var j = i + 1
    while j < s.len and s[j] notin forbidden: inc j
    if j < s.len and s[j] == q: return j + 1
    return -1
  var j = i
  var (ok, size) = isLetterOrNumber(s, j)
  if not (ok or s[j] in {'_', '-'}): return -1
  j += size
  while j < s.len:
    (ok, size) = isLetterOrNumber(s, j)
    if not (ok or s[j] in {'_', ' ', '.', '-'}): break
    j += size
  j

func skipSpaces(s: string, i: int): int =
  result = i
  while true:
    let n = spaceLenAt(s, result)
    if n == 0: break
    result += n

func isFamilies(list: string): bool =
  ## RE_FAMILIES: ^\s*FAMILY(?:\s*,\s*FAMILY)*\s*$
  var i = skipSpaces(list, 0)
  i = familyEnd(list, i)
  if i < 0: return false
  while true:
    let j = skipSpaces(list, i)
    if j < list.len and list[j] == ',':
      let k = familyEnd(list, skipSpaces(list, j + 1))
      if k < 0: return false
      i = k
    else:
      return j == list.len

func families(list: string, generic: string): string =
  ## A list of font names, quoted or not, and nothing that could end the declaration it is
  ## put in. "" stands for undefined.
  if list.len > 0 and isFamilies(list): list else: generic

func fontStyle*(size: float, family, mono: string): string =
  ## The fonts the labels were measured in are the ones they are drawn in, unless the page
  ## names others. The rest of what text inherits is pinned, as none of it was measured.
  ";--_fm:var(--pele-font-mono," & families(mono, "monospace") & ");font:" & jsString(size) &
    "px sans-serif;" &
    "letter-spacing:normal;word-spacing:normal;text-transform:none;direction:ltr;" &
    "font-family:var(--pele-font," & families(family, "sans-serif") & ")"

const SHAPE_PROPS = ["fill", "fill-opacity", "stroke", "stroke-width", "stroke-dasharray",
                     "stroke-dashoffset", "stroke-linecap", "stroke-linejoin", "stroke-opacity",
                     "opacity", "rx", "ry"]

const TEXT_PROPS = ["color", "font-size", "font-family", "font-weight", "font-style",
                    "text-decoration", "letter-spacing", "word-spacing", "opacity"]

func isUnsafe(value: string): bool =
  ## /url\s*\(|expression\s*\(|javascript:|[<>{};\\]|@import|image-set|\/\*/i
  let v = value.toLowerAscii
  for c in v:
    if c in {'<', '>', '{', '}', ';', '\\'}: return true
  for word in ["url", "expression"]:
    var at = v.find(word)
    while at != -1:
      if v.continuesWith("(", skipSpaces(v, at + word.len)): return true
      at = v.find(word, at + 1)
  "javascript:" in v or "@import" in v or "image-set" in v or "/*" in v

type ResolvedStyle* = object
  shape*, line*, text*: string
  stroke*: string     ## "" for undefined
  bold*, italic*: bool
  fontSize*: float    ## 0 for undefined

func removeImportant(s: string): string =
  ## s.replace(/!important/gi, '')
  var i = 0
  while i < s.len:
    if s[i] == '!' and cmpIgnoreCase(s[i ..< min(i + 10, s.len)], "!important") == 0:
      i += 10
      continue
    result.add s[i]
    inc i

proc resolveStyle*(declarations: seq[string]): ResolvedStyle =
  ## Splits Mermaid style declarations into what applies to a shape and what applies to its text.
  if declarations.len == 0: return
  var shape = initOrderedTable[string, string]()
  var text = initOrderedTable[string, string]()
  for decl in declarations:
    let at = decl.find(':')
    if at <= 0: continue
    let prop = jsTrim(decl[0 ..< at]).toLowerAscii
    let value = jsTrim(removeImportant(decl[at + 1 .. ^1]))
    if value == "" or isUnsafe(value) or hasInvalidXml(value): continue
    if prop in SHAPE_PROPS: shape[prop] = value
    if prop in TEXT_PROPS: text[if prop == "color": "fill" else: prop] = value
  if shape.len == 0 and text.len == 0: return
  var shapeCss = ""
  var lineCss = ""
  for prop, value in shape:
    shapeCss.add prop & ":" & value & ";"
    if prop != "fill" and prop != "fill-opacity": lineCss.add prop & ":" & value & ";"
  var textCss = ""
  for prop, value in text: textCss.add prop & ":" & value & ";"
  let weight = text.getOrDefault("font-weight", "")
  let size = text.getOrDefault("font-size", "")
  var px = -1.0
  block:
    # /^[\d.]+(px)?$/
    var k = 0
    while k < size.len and size[k] in {'0'..'9', '.'}: inc k
    if size.len > 0 and k > 0 and (k == size.len or size[k .. ^1] == "px"):
      # parseFloat: the longest prefix that is a number
      var stop = 0
      var dot = false
      while stop < k:
        if size[stop] == '.':
          if dot: break
          dot = true
        inc stop
      let prefix = size[0 ..< stop]
      px = if prefix == "." or prefix == "": NaN else: parseFloat(if prefix.endsWith("."): prefix & "0" else: (if prefix.startsWith("."): "0" & prefix else: prefix))
  var weightNum = NaN
  if weight.len > 0:
    try: weightNum = parseFloat(jsTrim(weight))
    except ValueError: discard
  result = ResolvedStyle(
    shape: if shapeCss != "": " style=\"" & esc(shapeCss) & "\"" else: "",
    line: if lineCss != "": " style=\"" & esc(lineCss) & "\"" else: "",
    text: if textCss != "": " style=\"" & esc(textCss) & "\"" else: "",
    stroke: shape.getOrDefault("stroke", ""),
    bold: weight == "bold" or weight == "bolder" or weightNum >= 600,
    italic: text.getOrDefault("font-style", "") == "italic",
    fontSize: if px > 0 and px <= 200: px else: 0)

func classNames*(raw: string): string =
  ## raw.replace(/[^\w-]+/g, ' ').trim()
  var cleaned = ""
  var inRun = false
  for c in raw:
    if isWordChar(c) or c == '-':
      cleaned.add c
      inRun = false
    elif not inRun:
      cleaned.add ' '
      inRun = true
  cleaned = jsTrim(cleaned)
  if cleaned == "": "" else: " " & cleaned

const SERIES = ["#4c78a8", "#f58518", "#54a24b", "#e45756", "#72b7b2", "#eeca3b", "#b279a2", "#9d755d"]

func seriesColor*(index: int): string =
  ## Color for the nth data series in a chart, cycling through eight tokens.
  let k = ((index mod 8) + 8) mod 8
  "var(--pele-series-" & $(k + 1) & "," & SERIES[k] & ")"
