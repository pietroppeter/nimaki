## port-of: src/svg/shapes.ts
## port-status: conformant
##
## Port notes: Pele keeps a record of shape definitions, each with functions for its size, its
## drawing, its inset and its span. Here each of those is one `case` over the shape's name, in
## the order of Pele's record; a name that is not there falls back as Pele's lookups do.
import std/[sets, strutils]
from std/math import PI
import ../jsmath
import ../layout/compound
import builder, theme

type ShapeSize* = object
  w*, h*: float
  dy*: float
    ## Vertical shift of the label from the shape's center.

const
  PAD_X* = 18.0
  PAD_Y* = 12.0
  CORNER = 12.0
  SQRT1_2 = 0.7071067811865476
    ## Kept clear at each end of a straight side, for the corner.

const KNOWN = toHashSet(["rect", "rounded", "stadium", "fr-rect", "cyl", "circle", "dbl-circ",
  "ellipse", "diam", "hex", "odd", "lean-r", "lean-l", "trap-b", "trap-t", "text", "sm-circ",
  "f-circ", "fr-circ", "fork", "notch-rect", "lin-rect", "div-rect", "win-pane", "tri",
  "flip-tri", "sl-rect", "notch-pent", "hourglass", "delay", "h-cyl", "cross-circ", "st-rect",
  "doc", "flag", "datastore", "folder", "bucket", "console", "browser", "person", "bang",
  "cloud", "brace", "brace-r", "braces", "bolt", "lin-cyl", "curv-trap", "docs", "bow-rect",
  "tag-rect", "tag-doc", "lin-doc", "collapsedGroup"])

func flat(w, h: float, sideways: bool): float = (if sideways: h else: w) - 2 * CORNER

func flatAcross(cut: float, w: float, sideways: bool): float =
  ## Straight along the top and bottom except for `cut` at each end, and not straight at the sides.
  if sideways: 0 else: w - 2 * cut - 2 * CORNER

proc bulge(t, half, depth: float): float =
  ## How far an ellipse's outline has fallen away from its bounding box, `t` from the middle of
  ## a side `half` long.
  let k = min(1.0, abs(t) / half)
  depth * (1 - sqrt(1 - k * k))

proc roundInset(w, h: float, side: int, t: float): float =
  if (side and 1) != 0: bulge(t, h / 2, w / 2) else: bulge(t, w / 2, h / 2)

func roundSpan(w, h: float, sideways: bool): float = (if sideways: h else: w) * 0.6

proc capInset(w, h: float, side: int, t: float): float =
  if (side and 1) != 0: 0 else: bulge(t, w / 2, min(12.0, max(6.0, w / 14)))

proc triSize(tw, th: float, flip: bool): ShapeSize =
  let w = max(1.6 * tw + 40, 80.0)
  let h = (th + 10) / (1 - (tw + 8) / w)
  let dy = h / 2 - 10 - th / 2
  ShapeSize(w: w, h: h, dy: if flip: -dy else: dy)

proc path(d, a: string): string = "<path d=\"" & d & "\"" & a & "/>"

func leanInset(h: float, side: int): float = (if (side and 1) != 0: h / 8 else: 0)

func box(tw, th: float): ShapeSize = ShapeSize(w: max(tw + 2 * PAD_X, 2 * PAD_X + 12), h: th + 2 * PAD_Y, dy: 0)

proc poly(points: openArray[float], a: string): string =
  var d = ""
  var i = 0
  while i < points.len:
    d.add (if i > 0: " " else: "") & num(points[i]) & "," & num(points[i + 1])
    i += 2
  "<polygon points=\"" & d & "\"" & a & "/>"

proc rect(w, h: float, a: string, rx = ""): string =
  "<rect x=\"" & num(-w / 2) & "\" y=\"" & num(-h / 2) & "\" width=\"" & num(w) & "\" height=\"" &
    num(h) & "\"" & rx & a & "/>"

proc brace(x, h, dir: float, line: string): string =
  let y = h / 2
  let k = 6 * dir
  "<path d=\"M" & num(x) & "," & num(-y) & "q" & num(k) & ",0 " & num(k) & ",6V-6q0,6 " & num(k) &
    ",6q" & num(-k) & ",0 " & num(-k) & ",6V" & num(y - 6) & "q0,6 " & num(-k) & ",6\" fill=\"none\"" &
    line & "/>"

proc wave(w, h: float, a: string): string =
  let x = w / 2
  let top = -h / 2
  let base = h / 2 - 10
  let q = w / 4
  "<path d=\"M" & num(-x) & "," & num(top) & "H" & num(x) & "V" & num(base) & "q" & num(-q) &
    ",-12 " & num(-2 * q) & ",0t" & num(-2 * q) & ",0Z\"" & a & "/>"

proc sizeOf(shape: string, tw, th: float): ShapeSize =
  case shape
  of "rounded", "notch-rect", "datastore", "tag-rect": box(tw, th)
  of "stadium":
    let h = th + 2 * PAD_Y
    ShapeSize(w: tw + h * 0.5 + 2 * PAD_X - 8, h: h, dy: 0)
  of "fr-rect": ShapeSize(w: tw + 2 * PAD_X + 16, h: th + 2 * PAD_Y, dy: 0)
  of "cyl":
    let w = max(tw + 2 * PAD_X, 56.0)
    let ry = min(12.0, max(6.0, w / 14))
    ShapeSize(w: w, h: th + 2 * PAD_Y + 2 * ry, dy: ry / 2)
  of "circle":
    let d = max(sqrt(tw * tw + th * th) + 16, 44.0)
    ShapeSize(w: d, h: d, dy: 0)
  of "dbl-circ":
    let d = max(sqrt(tw * tw + th * th) + 26, 54.0)
    ShapeSize(w: d, h: d, dy: 0)
  of "ellipse": ShapeSize(w: tw * 1.3 + 2 * PAD_X, h: th * 1.2 + 2 * PAD_Y, dy: 0)
  of "diam":
    let a = tw + 16
    let b = th + 8
    ShapeSize(w: a + 1.6 * b, h: a / 1.6 + b, dy: 0)
  of "hex", "lean-r", "lean-l", "trap-b", "trap-t":
    let h = th + 2 * PAD_Y
    ShapeSize(w: tw + 2 * PAD_X + h / 2, h: h, dy: 0)
  of "odd", "delay":
    let h = th + 2 * PAD_Y
    ShapeSize(w: tw + 2 * PAD_X + h / 4, h: h, dy: 0)
  of "text": ShapeSize(w: tw + 8, h: th + 8, dy: 0)
  of "sm-circ", "f-circ": ShapeSize(w: 14, h: 14, dy: 0)
  of "fr-circ": ShapeSize(w: 18, h: 18, dy: 0)
  of "fork": ShapeSize(w: 72, h: 8, dy: 0)
  of "lin-rect": ShapeSize(w: tw + 2 * PAD_X + 8, h: th + 2 * PAD_Y, dy: 0)
  of "div-rect": ShapeSize(w: tw + 2 * PAD_X, h: th + 2 * PAD_Y + 8, dy: 4)
  of "win-pane", "st-rect": ShapeSize(w: tw + 2 * PAD_X + 8, h: th + 2 * PAD_Y + 8, dy: 4)
  of "tri": triSize(tw, th, false)
  of "flip-tri": triSize(tw, th, true)
  of "sl-rect": ShapeSize(w: tw + 2 * PAD_X, h: th + 2 * PAD_Y + 10, dy: 5)
  of "notch-pent": ShapeSize(w: tw + 2 * PAD_X, h: th + 2 * PAD_Y, dy: 0)
  of "hourglass": ShapeSize(w: 32, h: 40, dy: 0)
  of "h-cyl":
    let h = th + 2 * PAD_Y
    let rx = min(12.0, h / 4)
    ShapeSize(w: tw + 2 * PAD_X + 2 * rx, h: h, dy: 0)
  of "cross-circ": ShapeSize(w: 44, h: 44, dy: 0)
  of "doc", "tag-doc": ShapeSize(w: tw + 2 * PAD_X, h: th + 2 * PAD_Y + 10, dy: -5)
  of "flag": ShapeSize(w: tw + 2 * PAD_X, h: th + 2 * PAD_Y + 16, dy: 0)
  of "folder": ShapeSize(w: max(tw + 2 * PAD_X, 64.0), h: th + 2 * PAD_Y + 8, dy: 4)
  of "bucket": ShapeSize(w: tw + 2 * PAD_X + 20, h: th + 2 * PAD_Y + 10, dy: 3)
  of "console", "browser": ShapeSize(w: max(tw + 2 * PAD_X, 72.0), h: th + 2 * PAD_Y + 12, dy: 6)
  of "person": ShapeSize(w: max(tw + 2 * PAD_X, 56.0), h: th + 2 * PAD_Y + 26, dy: 13)
  of "bang": ShapeSize(w: tw + 2 * PAD_X + 28, h: th + 2 * PAD_Y + 24, dy: 0)
  of "cloud": ShapeSize(w: tw + 2 * PAD_X + 32, h: th + 2 * PAD_Y + 24, dy: 0)
  of "brace", "brace-r": ShapeSize(w: tw + 2 * PAD_X + 12, h: th + 2 * PAD_Y, dy: 0)
  of "braces": ShapeSize(w: tw + 2 * PAD_X + 24, h: th + 2 * PAD_Y, dy: 0)
  of "bolt": ShapeSize(w: 36, h: 56, dy: 0)
  of "lin-cyl":
    let w = max(tw + 2 * PAD_X, 56.0)
    let ry = min(12.0, max(6.0, w / 14))
    ShapeSize(w: w, h: th + 2 * PAD_Y + 2 * ry + 8, dy: ry / 2 + 4)
  of "curv-trap":
    let h = th + 2 * PAD_Y
    ShapeSize(w: tw + 2 * PAD_X + h * 0.6, h: h, dy: 0)
  of "docs": ShapeSize(w: tw + 2 * PAD_X + 8, h: th + 2 * PAD_Y + 18, dy: -1)
  of "bow-rect":
    let h = th + 2 * PAD_Y
    ShapeSize(w: tw + 2 * PAD_X + h * 0.4, h: h, dy: 0)
  of "lin-doc": ShapeSize(w: tw + 2 * PAD_X + 8, h: th + 2 * PAD_Y + 10, dy: -5)
  of "collapsedGroup": ShapeSize(w: tw + 2 * PAD_X + 8, h: th + 2 * PAD_Y + 8, dy: -2)
  else: box(tw, th) # rect, and the fallback

proc drawOf(shape: string, w, h: float, a, line: string): string =
  case shape
  of "rounded": rect(w, h, a, " rx=\"" & num(min(12.0, h / 2)) & "\"")
  of "stadium": rect(w, h, a, " rx=\"" & num(h / 2) & "\"")
  of "fr-rect":
    let x = w / 2 - 8
    rect(w, h, rounded(a)) &
      "<path d=\"M" & num(-x) & "," & num(-h / 2) & "V" & num(h / 2) & "M" & num(x) & "," &
      num(-h / 2) & "V" & num(h / 2) & "\" fill=\"none\"" & line & "/>"
  of "cyl":
    let rx = w / 2
    let ry = min(12.0, max(6.0, w / 14))
    let top = -h / 2 + ry
    let bottom = h / 2 - ry
    "<path d=\"M" & num(-rx) & "," & num(top) & "A" & num(rx) & "," & num(ry) & " 0 0 1 " & num(rx) &
      "," & num(top) & "V" & num(bottom) & "A" & num(rx) & "," & num(ry) & " 0 0 1 " & num(-rx) & "," &
      num(bottom) & "Z\"" & a & "/>" &
      "<path d=\"M" & num(-rx) & "," & num(top) & "A" & num(rx) & "," & num(ry) & " 0 0 0 " & num(rx) &
      "," & num(top) & "\" fill=\"none\"" & line & "/>"
  of "circle": "<circle r=\"" & num(w / 2) & "\"" & a & "/>"
  of "dbl-circ":
    "<circle r=\"" & num(w / 2) & "\"" & a & "/><circle r=\"" & num(w / 2 - 5) & "\" fill=\"none\"" & line & "/>"
  of "ellipse": "<ellipse rx=\"" & num(w / 2) & "\" ry=\"" & num(h / 2) & "\"" & a & "/>"
  of "diam": poly([0.0, -h / 2, w / 2, 0, 0, h / 2, -w / 2, 0], a)
  of "hex":
    let m = h / 4
    poly([-w / 2 + m, -h / 2, w / 2 - m, -h / 2, w / 2, 0, w / 2 - m, h / 2, -w / 2 + m, h / 2, -w / 2, 0], a)
  of "odd":
    let notch = h / 4
    poly([-w / 2, -h / 2, w / 2, -h / 2, w / 2, h / 2, -w / 2, h / 2, -w / 2 + notch, 0], a)
  of "lean-r":
    let s = h / 4
    poly([-w / 2 + s, -h / 2, w / 2, -h / 2, w / 2 - s, h / 2, -w / 2, h / 2], a)
  of "lean-l":
    let s = h / 4
    poly([-w / 2, -h / 2, w / 2 - s, -h / 2, w / 2, h / 2, -w / 2 + s, h / 2], a)
  of "trap-b":
    let s = h / 4
    poly([-w / 2 + s, -h / 2, w / 2 - s, -h / 2, w / 2, h / 2, -w / 2, h / 2], a)
  of "trap-t":
    let s = h / 4
    poly([-w / 2, -h / 2, w / 2, -h / 2, w / 2 - s, h / 2, -w / 2 + s, h / 2], a)
  of "text": rect(w, h, " fill=\"none\" stroke=\"none\"")
  of "sm-circ": "<circle r=\"" & num(w / 2) & "\"" & a & "/>"
  of "f-circ": "<circle r=\"" & num(w / 2) & "\" fill=\"var(--_l)\"" & line & "/>"
  of "fr-circ":
    "<circle r=\"" & num(w / 2) & "\"" & a & "/><circle r=\"" & num(w / 2 - 4) & "\" fill=\"var(--_l)\"" & line & "/>"
  of "fork": rect(w, h, " fill=\"var(--_l)\"" & line, " rx=\"2\"")
  of "notch-rect":
    let c = 10.0
    poly([-w / 2 + c, -h / 2, w / 2, -h / 2, w / 2, h / 2, -w / 2, h / 2, -w / 2, -h / 2 + c], a)
  of "lin-rect":
    rect(w, h, rounded(a)) & "<path d=\"M" & num(-w / 2 + 8) & "," & num(-h / 2) & "V" & num(h / 2) &
      "\" fill=\"none\"" & line & "/>"
  of "div-rect":
    rect(w, h, rounded(a)) & "<path d=\"M" & num(-w / 2) & "," & num(-h / 2 + 8) & "H" & num(w / 2) &
      "\" fill=\"none\"" & line & "/>"
  of "win-pane":
    rect(w, h, rounded(a)) & "<path d=\"M" & num(-w / 2 + 8) & "," & num(-h / 2) & "V" & num(h / 2) &
      "M" & num(-w / 2) & "," & num(-h / 2 + 8) & "H" & num(w / 2) & "\" fill=\"none\"" & line & "/>"
  of "tri": poly([0.0, -h / 2, w / 2, h / 2, -w / 2, h / 2], a)
  of "flip-tri": poly([-w / 2, -h / 2, w / 2, -h / 2, 0, h / 2], a)
  of "sl-rect": poly([-w / 2, -h / 2 + 10, w / 2, -h / 2, w / 2, h / 2, -w / 2, h / 2], a)
  of "notch-pent":
    let c = 10.0
    poly([-w / 2 + c, -h / 2, w / 2 - c, -h / 2, w / 2, -h / 2 + c, w / 2, h / 2, -w / 2, h / 2, -w / 2, -h / 2 + c], a)
  of "hourglass": poly([-w / 2, -h / 2, w / 2, -h / 2, -w / 2, h / 2, w / 2, h / 2], a)
  of "delay":
    let r = h / 2
    "<path d=\"M" & num(-w / 2) & "," & num(-r) & "H" & num(w / 2 - r) & "A" & num(r) & "," & num(r) &
      " 0 0 1 " & num(w / 2 - r) & "," & num(r) & "H" & num(-w / 2) & "Z\"" & a & "/>"
  of "h-cyl":
    let ry = h / 2
    let rx = min(12.0, h / 4)
    let l = -w / 2 + rx
    let r = w / 2 - rx
    "<path d=\"M" & num(l) & "," & num(-ry) & "H" & num(r) & "A" & num(rx) & "," & num(ry) & " 0 0 1 " &
      num(r) & "," & num(ry) & "H" & num(l) & "A" & num(rx) & "," & num(ry) & " 0 0 1 " & num(l) & "," &
      num(-ry) & "Z\"" & a & "/>" &
      "<path d=\"M" & num(r) & "," & num(-ry) & "A" & num(rx) & "," & num(ry) & " 0 0 0 " & num(r) & "," &
      num(ry) & "\" fill=\"none\"" & line & "/>"
  of "cross-circ":
    let r = w / 2
    let k = r * SQRT1_2
    "<circle r=\"" & num(r) & "\"" & a & "/>" &
      "<path d=\"M" & num(-k) & "," & num(-k) & "L" & num(k) & "," & num(k) & "M" & num(k) & "," &
      num(-k) & "L" & num(-k) & "," & num(k) & "\" fill=\"none\"" & line & "/>"
  of "st-rect":
    let bw = w - 8
    let bh = h - 8
    var output = ""
    for i in 0 ..< 3:
      let x = -w / 2 + float(2 - i) * 4
      let y = -h / 2 + float(i) * 4
      output.add "<rect x=\"" & num(x) & "\" y=\"" & num(y) & "\" width=\"" & num(bw) & "\" height=\"" &
        num(bh) & "\"" & rounded(a) & "/>"
    output
  of "doc": wave(w, h, a)
  of "flag":
    let x = w / 2
    let y = h / 2 - 8
    let q = w / 4
    "<path d=\"M" & num(-x) & "," & num(-y) & "q" & num(q) & ",-10 " & num(2 * q) & ",0t" & num(2 * q) &
      ",0V" & num(y) & "q" & num(-q) & ",10 " & num(-2 * q) & ",0t" & num(-2 * q) & ",0Z\"" & a & "/>"
  of "datastore":
    rect(w, h, a.replace("stroke=\"var(--_b)\"", "stroke=\"none\"")) &
      "<path d=\"M" & num(-w / 2) & "," & num(-h / 2) & "H" & num(w / 2) & "M" & num(-w / 2) & "," &
      num(h / 2) & "H" & num(w / 2) & "\" fill=\"none\"" & line & "/>"
  of "folder":
    let x = w / 2
    let y = h / 2
    let tab = min(w * 0.4, 48.0)
    path("M" & num(-x) & "," & num(-y) & "H" & num(-x + tab) & "L" & num(-x + tab + 8) & "," &
         num(-y + 8) & "H" & num(x) & "V" & num(y) & "H" & num(-x) & "Z", a)
  of "bucket":
    let x = w / 2
    let y = h / 2
    let ry = 5.0
    let taper = h / 6
    path("M" & num(-x) & "," & num(-y + ry) & "A" & num(x) & "," & num(ry) & " 0 0 1 " & num(x) & "," &
         num(-y + ry) & "L" & num(x - taper) & "," & num(y - ry) & "A" & num(x - taper) & "," & num(ry) &
         " 0 0 1 " & num(-x + taper) & "," & num(y - ry) & "Z", a) &
      "<path d=\"M" & num(-x) & "," & num(-y + ry) & "A" & num(x) & "," & num(ry) & " 0 0 0 " & num(x) &
      "," & num(-y + ry) & "\" fill=\"none\"" & line & "/>"
  of "console":
    rect(w, h, rounded(a)) &
      "<path d=\"M" & num(-w / 2) & "," & num(-h / 2 + 12) & "H" & num(w / 2) & "M" & num(-w / 2 + 7) &
      "," & num(-h / 2 + 4) & "l3,2.5l-3,2.5M" & num(-w / 2 + 13) & "," & num(-h / 2 + 9) &
      "h4\" fill=\"none\"" & line & "/>"
  of "browser":
    var dots = ""
    for i in 0 ..< 3:
      dots.add "<circle cx=\"" & num(-w / 2 + 8 + float(i) * 7) & "\" cy=\"" & num(-h / 2 + 6) &
        "\" r=\"1.5\" fill=\"none\"" & line & "/>"
    rect(w, h, rounded(a)) & "<path d=\"M" & num(-w / 2) & "," & num(-h / 2 + 12) & "H" & num(w / 2) &
      "\" fill=\"none\"" & line & "/>" & dots
  of "person":
    let top = -h / 2
    "<rect x=\"" & num(-w / 2) & "\" y=\"" & num(top + 26) & "\" width=\"" & num(w) & "\" height=\"" &
      num(h - 26) & "\" rx=\"12\"" & a & "/>" & "<circle cy=\"" & num(top + 14) & "\" r=\"13\"" & a & "/>"
  of "bang":
    const spikes = 14
    var pts: seq[float]
    for i in 0 ..< spikes * 2:
      let angle = (PI * float(i)) / float(spikes) - PI / 2
      let k = if i mod 2 == 0: 1.0 else: 0.82
      pts.add [cos(angle) * (w / 2) * k, sin(angle) * (h / 2) * k]
    poly(pts, a)
  of "cloud":
    let x = w / 2
    let y = h / 2
    let r = y * 0.55
    path("M" & num(-x + r) & "," & num(y) & "A" & num(r) & "," & num(r) & " 0 0 1 " & num(-x + r * 0.6) &
         "," & num(-y * 0.1) & "A" & num(x * 0.42) & "," & num(y * 0.7) & " 0 0 1 " & num(-x * 0.1) & "," &
         num(-y * 0.72) & "A" & num(x * 0.4) & "," & num(y * 0.62) & " 0 0 1 " & num(x * 0.62) & "," &
         num(-y * 0.42) & "A" & num(r * 1.05) & "," & num(r * 1.05) & " 0 0 1 " & num(x - r) & "," &
         num(y) & "Z", a)
  of "brace": rect(w, h, " fill=\"none\" stroke=\"none\"") & brace(-w / 2 + 12, h, -1, line)
  of "brace-r": rect(w, h, " fill=\"none\" stroke=\"none\"") & brace(w / 2 - 12, h, 1, line)
  of "braces":
    rect(w, h, " fill=\"none\" stroke=\"none\"") & brace(-w / 2 + 12, h, -1, line) & brace(w / 2 - 12, h, 1, line)
  of "bolt":
    poly([w * 0.15, -h / 2, -w / 2, h * 0.08, -w * 0.05, h * 0.08, -w * 0.15, h / 2, w / 2, -h * 0.08,
          w * 0.05, -h * 0.08], a)
  of "lin-cyl":
    let rx = w / 2
    let ry = min(12.0, max(6.0, w / 14))
    let top = -h / 2 + ry
    let bottom = h / 2 - ry
    proc arc(y: float): string =
      "M" & num(-rx) & "," & num(y) & "A" & num(rx) & "," & num(ry) & " 0 0 0 " & num(rx) & "," & num(y)
    path("M" & num(-rx) & "," & num(top) & "A" & num(rx) & "," & num(ry) & " 0 0 1 " & num(rx) & "," &
         num(top) & "V" & num(bottom) & "A" & num(rx) & "," & num(ry) & " 0 0 1 " & num(-rx) & "," &
         num(bottom) & "Z", a) & "<path d=\"" & arc(top) & arc(top + 8) & "\" fill=\"none\"" & line & "/>"
  of "curv-trap":
    let x = w / 2
    let y = h / 2
    let k = h * 0.3
    path("M" & num(-x + k) & "," & num(-y) & "H" & num(x - k) & "A" & num(k) & "," & num(y) & " 0 0 1 " &
         num(x - k) & "," & num(y) & "H" & num(-x + k) & "L" & num(-x) & ",0Z", a)
  of "docs":
    var output = ""
    for i in 0 ..< 3:
      output.add "<g transform=\"translate(" & $((1 - i) * 4) & "," & $((i - 1) * 4) & ")\">" &
        wave(w - 8, h - 8, a) & "</g>"
    output
  of "bow-rect":
    let x = w / 2
    let y = h / 2
    let k = h * 0.2
    path("M" & num(-x + k) & "," & num(-y) & "H" & num(x) & "A" & num(k) & "," & num(y) & " 0 0 0 " &
         num(x) & "," & num(y) & "H" & num(-x + k) & "A" & num(k) & "," & num(y) & " 0 0 1 " & num(-x + k) &
         "," & num(-y) & "Z", a)
  of "tag-rect":
    rect(w, h, rounded(a)) & "<path d=\"M" & num(w / 2 - 12) & "," & num(h / 2) & "L" & num(w / 2) & "," &
      num(h / 2 - 12) & "\" fill=\"none\"" & line & "/>"
  of "tag-doc":
    wave(w, h, a) & "<path d=\"M" & num(w / 2 - 12) & "," & num(h / 2 - 14) & "L" & num(w / 2) & "," &
      num(h / 2 - 26) & "\" fill=\"none\"" & line & "/>"
  of "lin-doc":
    wave(w, h, a) & "<path d=\"M" & num(-w / 2 + 8) & "," & num(-h / 2) & "V" & num(h / 2 - 6) &
      "\" fill=\"none\"" & line & "/>"
  of "collapsedGroup":
    "<rect x=\"" & num(-w / 2 + 6) & "\" y=\"" & num(-h / 2 + 8) & "\" width=\"" & num(w - 12) &
      "\" height=\"" & num(h - 8) & "\"" & rounded(a) & "/>" &
      "<rect x=\"" & num(-w / 2) & "\" y=\"" & num(-h / 2) & "\" width=\"" & num(w) & "\" height=\"" &
      num(h - 4) & "\"" & rounded(a) & "/>"
  else: rect(w, h, rounded(a)) # rect, and the fallback

proc insetOf(shape: string, w, h: float, side: int, t: float): float =
  ## 0 for a shape without an inset.
  case shape
  of "stadium": (if (side and 1) != 0: bulge(t, h / 2, h / 2) else: 0)
  of "cyl", "lin-cyl": capInset(w, h, side, t)
  of "circle", "dbl-circ", "ellipse", "sm-circ", "f-circ", "fr-circ", "cross-circ": roundInset(w, h, side, t)
  of "diam": (if (side and 1) != 0: (abs(t) * w) / h else: (abs(t) * h) / w)
  of "hex": (if (side and 1) != 0: abs(t) / 2 else: 0)
  of "odd": (if side == 3: h / 4 else: 0)
  of "lean-r", "lean-l", "trap-b", "trap-t": leanInset(h, side)
  of "tri", "flip-tri", "bolt": (if (side and 1) != 0: w / 4 else: 0)
  of "sl-rect": (if side == 0: 5 else: 0)
  of "hourglass": (if (side and 1) != 0: w / 2 else: 0)
  of "doc", "docs", "tag-doc", "lin-doc": (if side == 2: 10 else: 0)
  of "flag": (if (side and 1) != 0: 0 else: 8)
  of "bucket": (if (side and 1) != 0: h / 12 else: 0)
  of "bang": 3
  of "cloud": (if (side and 1) != 0: 2 else: 1)
  of "bow-rect": (if side == 1: h * 0.2 else: 0)
  else: 0

proc spanOf(shape: string, w, h: float, sideways: bool): float =
  ## 0 for a shape without a span.
  case shape
  of "rect", "rounded", "fr-rect", "text", "notch-rect", "lin-rect", "div-rect", "win-pane",
     "notch-pent", "datastore", "console", "browser", "tag-rect": flat(w, h, sideways)
  of "stadium": (if sideways: h * 0.6 else: w - h)
  of "cyl": (if sideways: h - 2 * CORNER - 12 else: w * 0.6)
  of "lin-cyl": (if sideways: h - 2 * CORNER - 20 else: w * 0.6)
  of "circle", "dbl-circ", "ellipse", "sm-circ", "f-circ", "fr-circ", "cross-circ": roundSpan(w, h, sideways)
  of "diam": (if sideways: h else: w) * 0.6
  of "hex": (if sideways: h * 0.5 else: w - h / 2 - CORNER)
  of "odd": flatAcross(0, w, sideways)
  of "lean-r", "lean-l", "trap-b", "trap-t": flatAcross(h / 4, w, sideways)
  of "fork": (if sideways: h else: w) - 8
  of "st-rect": (if sideways: h else: w) - 2 * CORNER - 8
  else: 0

proc shapeSize*(shape: string, tw, th: float): ShapeSize = sizeOf(shape, tw, th)

proc drawShape*(shape: string, w, h: float, a, line: string): string = drawOf(shape, w, h, a, line)

proc shapeInset*(shape: string, w, h: float, side: int, t = 0.0): float =
  if shape notin KNOWN: 0.0 else: insetOf(shape, w, h, side, t)

proc shapeSpan*(shape: string, w, h: float, sideways: bool): float =
  ## How much of a side of the shape edges may spread along, when the flow runs down or, if
  ## `sideways`, across.
  max(0.0, if shape notin KNOWN: 0.0 else: spanOf(shape, w, h, sideways))

proc shapeHasLabel*(shape: string): bool =
  shape notin ["sm-circ", "f-circ", "fr-circ", "fork", "hourglass", "cross-circ", "bolt"]

proc shapeFilled*(shape: string): bool =
  shape notin ["text", "brace", "brace-r", "braces"]

proc endSide*(route: seq[float], at: int, c: CNode): int =
  ## The side of a node's layout box that a route end lies on: 0 top, 1 right, 2 bottom, 3 left,
  ## or -1 for none.
  let dx = route[at] - c.x
  let dy = route[at + 1] - c.y
  if abs(abs(dy) - c.h / 2) < 0.5: return (if dy < 0: 0 else: 2)
  if abs(abs(dx) - c.w / 2) < 0.5: return (if dx < 0: 3 else: 1)
  -1

type ShapeView* = object
  shape*: string
  w*, h*: float

proc insetRoute*(route: var seq[float], at: int, view: ShapeView, c: CNode) =
  ## Moves a route end from a node's layout box onto the outline of the shape drawn in it.
  if c.isGroup: return
  let side = endSide(route, at, c)
  if side == 0 or side == 2:
    let amount = shapeInset(view.shape, view.w, view.h, side, route[at] - c.x) + (c.h - view.h) / 2
    route[at + 1] += (if side == 0: amount else: -amount)
  elif side >= 0:
    let amount = shapeInset(view.shape, view.w, view.h, side, route[at + 1] - c.y) + (c.w - view.w) / 2
    route[at] += (if side == 3: amount else: -amount)
