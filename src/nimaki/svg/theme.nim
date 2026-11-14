## port-of: src/svg/theme.ts
## port-status: draft
import std/[strutils, tables, unicode]
import builder
import ../js, ../jsregex

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

const RE_FILL = jsre"""/[";]fill:/"""

func setsFill*(shape: string): bool =
  ## Expects a shape style from resolveStyle().
  RE_FILL.test(shape)

func rounded*(attrs: string): string =
  let at = attrs.find(" style=\"")
  if at < 0: attrs & ROUNDED
  else: attrs[0 ..< at + 8] & "rx:var(--_r);" & attrs[at + 8 .. ^1]

const CRITICAL* = "var(--pele-critical,#e45756)"
  ## The color of what a diagram marks as critical. It is not one of the series colors, as a
  ## theme may put those in any order.

const FAMILY = r"""(?:"[^"'\\\n<>{}();:@]*"|'[^"'\\\n<>{}();:@]*'|[\p{L}\p{N}_-][\p{L}\p{N}_ .-]*)"""
  ## A list of font names, quoted or not, and nothing that could end the declaration it is put in.
const RE_FAMILIES = jsre(r"^\s*" & FAMILY & r"(?:\s*,\s*" & FAMILY & r")*\s*$", "u")

func families(list: string, generic: string): string =
  ## "" stands for undefined.
  if list.len > 0 and RE_FAMILIES.test(list): list else: generic

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

const RE_UNSAFE = jsre"/url\s*\(|expression\s*\(|javascript:|[<>{};\\]|@import|image-set|\/\*/i"

type ResolvedStyle* = object
  shape*, line*, text*: string
  stroke*: string     ## "" for undefined
  bold*, italic*: bool
  fontSize*: float    ## 0 for undefined

proc resolveStyle*(declarations: seq[string]): ResolvedStyle =
  ## Splits Mermaid style declarations into what applies to a shape and what applies to its text.
  if declarations.len == 0: return
  var shape = initOrderedTable[string, string]()
  var text = initOrderedTable[string, string]()
  for decl in declarations:
    let at = decl.find(':')
    if at <= 0: continue
    let prop = jsTrim(decl[0 ..< at]).toLowerAscii
    let value = jsTrim(decl[at + 1 .. ^1].replace(jsre"/!important/gi", ""))
    if value == "" or RE_UNSAFE.test(value) or hasInvalidXml(value): continue
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
  let px = if size != "" and jsre"/^[\d.]+(px)?$/".test(size): jsParseFloat(size) else: -1.0
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

const RE_CLASS = jsre"/[^\w-]+/g"

func classNames*(raw: string): string =
  let cleaned = jsTrim(raw.replace(RE_CLASS, " "))
  if cleaned == "": "" else: " " & cleaned

const SERIES = ["#4c78a8", "#f58518", "#54a24b", "#e45756", "#72b7b2", "#eeca3b", "#b279a2", "#9d755d"]

func seriesColor*(index: int): string =
  ## Color for the nth data series in a chart, cycling through eight tokens.
  let k = ((index mod 8) + 8) mod 8
  "var(--pele-series-" & $(k + 1) & "," & SERIES[k] & ")"
