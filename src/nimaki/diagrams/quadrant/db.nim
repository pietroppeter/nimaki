## port-of: src/diagrams/quadrant/db.ts
## port-status: draft
import std/[options, tables, strutils]
import ../../errors
import ../../js
import ../../jsregex

type
  QuadrantText* = object
    defined*: bool   ## false for undefined
    text*: string
    markdown*: bool  ## type 'markdown', else 'text'

  PointStyle* = object
    radius*: Option[float]
    color*, strokeColor*, strokeWidth*: Option[string]

  QuadrantPoint* = object
    x*, y*: float
    text*: QuadrantText
    className*: string
    style*: PointStyle

  QuadrantDb* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    quadrants*: array[4, QuadrantText]     ## 1 to 4: top right, top left, bottom left, bottom right
    xAxisLeft*, xAxisRight*, yAxisBottom*, yAxisTop*: QuadrantText
    points*: seq[QuadrantPoint]
    classes*: Table[string, PointStyle]

  QuadrantModel* = QuadrantDb

const RE_NUMBER = jsre"/^\d+$/"
const RE_HEX = jsre"/^#?([\dA-Fa-f]{6}|[\dA-Fa-f]{3})$/"
const RE_PIXELS = jsre"/^\d+px$/"

proc invalid(style, value, kind: string): ref PeleError =
  newPeleError("value for " & style & " " & value & " is invalid, please use a valid " & kind,
               "semantic", "quadrantChart")

func keyValue(style: string): (string, string) =
  ## The first two parts of Mermaid's `style.trim().split(/\s*:\s*/)`, found in one pass.
  let s = jsTrim(style)
  let colon = s.find(':')
  if colon == -1: return (s, "undefined")
  let rest = jsTrimStart(s[colon + 1 .. ^1])
  let next = rest.find(':')
  (jsTrimEnd(s[0 ..< colon]), (if next == -1: rest else: jsTrimEnd(rest[0 ..< next])))

proc parseStyles*(styles: seq[string]): PointStyle =
  for style in styles:
    let (key, value) = keyValue(style)
    if key == "radius":
      if not RE_NUMBER.test(value): raise invalid(key, value, "number")
      result.radius = some(jsToNumber(value))
    elif key == "color":
      if not RE_HEX.test(value): raise invalid(key, value, "hex code")
      result.color = some(value)
    elif key == "stroke-color":
      if not RE_HEX.test(value): raise invalid(key, value, "hex code")
      result.strokeColor = some(value)
    elif key == "stroke-width":
      if not RE_PIXELS.test(value): raise invalid(key, value, "number of pixels (eg. 10px)")
      result.strokeWidth = some(value)
    else:
      raise newPeleError("style named " & key & " is not supported.", "semantic", "quadrantChart")

func trimmed(label: QuadrantText): QuadrantText =
  QuadrantText(defined: true, text: jsTrim(label.text), markdown: label.markdown)

proc setQuadrantText*(db: QuadrantDb, k: int, label: QuadrantText) = db.quadrants[k] = trimmed(label)
proc setXAxisLeftText*(db: QuadrantDb, label: QuadrantText) = db.xAxisLeft = trimmed(label)
proc setXAxisRightText*(db: QuadrantDb, label: QuadrantText) = db.xAxisRight = trimmed(label)
proc setYAxisBottomText*(db: QuadrantDb, label: QuadrantText) = db.yAxisBottom = trimmed(label)
proc setYAxisTopText*(db: QuadrantDb, label: QuadrantText) = db.yAxisTop = trimmed(label)

proc addPoint*(db: QuadrantDb, label: QuadrantText, className, x, y: string, styles: seq[string]) =
  db.points.add QuadrantPoint(x: jsToNumber(x), y: jsToNumber(y), text: trimmed(label),
                              className: className, style: parseStyles(styles))

proc addClass*(db: QuadrantDb, className: string, styles: seq[string]) =
  db.classes[className] = parseStyles(styles)

proc setDiagramTitle*(db: QuadrantDb, text: string) = db.title = text
proc setAccTitle*(db: QuadrantDb, text: string) = db.accTitle = jsTrimStart(text)   # replace(/^\s+/g, '')

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc setAccDescription*(db: QuadrantDb, text: string) = db.accDescr = collapseIndents(text)
