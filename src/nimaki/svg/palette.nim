## port-of: src/svg/palette.ts
## port-status: draft
import std/[strutils, sets, tables]
import ../util/yaml
import builder, ink
import ../js

type PaletteSpec = tuple[prefix: string, first: int, repeat: bool]

const PALETTES: Table[string, PaletteSpec] = {
  # Mermaid's palette theme variables, which set a diagram's own series colors. `first` is the
  # number of the variable for the first series. Mindmap branches start at cScale1, as cScale0
  # is the root's in Mermaid's styles. A venn palette repeats the colors it sets, as in Mermaid.
  "pie": ("pie", 1, false),
  "gitGraph": ("git", 0, false),
  "timeline": ("cScale", 0, false),
  "radar": ("cScale", 0, false),
  "treemap": ("cScale", 0, false),
  "mindmap": ("cScale", 1, false),
  "venn": ("venn", 1, true),
}.toTable

const SLOTS = 8
const FUNCTIONS = toHashSet(["rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch",
                             "color", "color-mix", "light-dark", "var"])

func record(value: YamlValue): YamlValue = (if isRecord(value): value else: ymap())

func charsOk(color: string): bool =
  ## /^[\w\s#%.,+\-/()]{1,200}$/
  let n = utf16Len(color)
  if n < 1 or n > 200: return false
  var i = 0
  while i < color.len:
    let s = spaceLenAt(color, i)
    if s > 0:
      i += s
      continue
    if not (isWordChar(color[i]) or color[i] in {'#', '%', '.', ',', '+', '-', '/', '(', ')'}): return false
    inc i
  true

func functionNames(color: string): seq[string] =
  ## the names of /([\w-]*)\s*\(/g
  var p = 0
  while p < color.len:
    var j = p
    while j < color.len and (isWordChar(color[j]) or color[j] == '-'): inc j
    var k = j
    while true:
      let n = spaceLenAt(color, k)
      if n == 0: break
      k += n
    if k < color.len and color[k] == '(':
      result.add color[p ..< j]
      p = k + 1
    else:
      inc p

func varNames(color: string): seq[string] =
  ## the names of /var\(\s*([\w-]*)/gi
  let lower = color.toLowerAscii
  var p = lower.find("var(")
  while p != -1:
    var j = p + 4
    while true:
      let n = spaceLenAt(color, j)
      if n == 0: break
      j += n
    let start = j
    while j < color.len and (isWordChar(color[j]) or color[j] == '-'): inc j
    result.add color[start ..< j]
    p = lower.find("var(", j)

func safeColor(value: YamlValue): (bool, string) =
  ## A color that can't load a resource, end its declaration or read the page's own variables.
  ## Values outside functions are checked as colors, so a typo keeps the theme color.
  if value == nil or value.kind != yString: return
  let color = jsTrim(value.s)
  if not charsOk(color): return
  if '(' notin color: return (if plainColor(color): (true, color) else: (false, ""))
  var depth = 0
  for c in color:
    if c == '(': inc depth
    elif c == ')':
      dec depth
      if depth < 0: return
  if depth != 0: return
  for name in functionNames(color):
    if name.toLowerAscii notin FUNCTIONS: return
  for name in varNames(color):
    if not name.startsWith("--pele-"): return
  (true, color)

func splitList(value: string): seq[string] =
  ## Splits at the commas between colors, not those inside rgb() and other functions.
  var depth = 0
  var start = 0
  for i, c in value:
    if c == '(': inc depth
    elif c == ')': dec depth
    elif c == ',' and depth == 0:
      result.add value[start ..< i]
      start = i + 1
  result.add value[start .. ^1]
  for part in result.mitems: part = jsTrim(part)

func entries(kind: string, vars: YamlValue): (bool, seq[YamlValue], bool) =
  if kind == "xychart":
    let list = record(vars["xyChart"])["plotColorPalette"]
    if list != nil and list.kind == yString:
      var items: seq[YamlValue]
      for s in splitList(list.s): items.add ystr(s)
      return (true, items, true)
    return
  if kind notin PALETTES: return
  let palette = PALETTES[kind]
  var list: seq[YamlValue]
  for i in 0 ..< SLOTS: list.add vars[palette.prefix & $(palette.first + i)]
  if palette.repeat:
    var kept: seq[YamlValue]
    for value in list:
      if value != nil and value.kind != yNull and not (value.kind == yString and value.s == ""): kept.add value
    list = kept
  (true, list, palette.repeat)

type Palette* = object
  style*: string
  inks*: array[SLOTS, string]
    ## Label colors for text on each series, where the contrast of its color is known ("" not).

const NONE = Palette()

proc palette*(kind: string, config: YamlValue): Palette =
  ## The --pele-series-* declarations for the palette a diagram's theme variables set. An entry
  ## that isn't a usable color leaves its series in the theme's color.
  let (found, list, repeat) = entries(kind, record(config["themeVariables"]))
  if not found or list.len == 0: return NONE
  var style = ""
  var inks: array[SLOTS, string]
  for i in 0 ..< SLOTS:
    if not repeat and i >= list.len: break
    let (ok, color) = safeColor(list[i mod list.len])
    if not ok: continue
    style.add ";--pele-series-" & $(i + 1) & ":" & color
    let (inked, c) = ink(";fill:" & color)
    inks[i] = if inked: c else: ""
  if style == "": NONE else: Palette(style: esc(style), inks: inks)

var current = NONE

proc withPalette*[T](next: Palette, run: proc (): T): T =
  let outer = current
  current = next
  try:
    result = run()
  finally:
    current = outer

proc paletteStyle*(): string = current.style

proc seriesInkFill*(index: int): string =
  ## A fill for a label on the series color, when the palette sets one that needs it.
  let color = current.inks[((index mod SLOTS) + SLOTS) mod SLOTS]
  if color != "": " fill=\"" & color & "\"" else: ""
