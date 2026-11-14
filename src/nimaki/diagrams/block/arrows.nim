## port-of: src/diagrams/block/arrows.ts
## port-status: conformant
import ../../svg/builder
import ../../js

const
  RIGHT* = 1
  LEFT* = 2
  UP* = 4
  DOWN* = 8
  OVERHANG* = 7.0     ## How far a head reaches past each side of its shaft.
  MAX_DEPTH = 20.0
  NUB = 12.0

type ArrowSize* = object
  w*, h*: float
  dx*, dy*: float     ## Shift of the label from the center, away from the heads.

func arrowMask*(directions: seq[string]): int =
  ## Mermaid compares directions exactly, so `( up )` draws no arrow there. Here spaces are ignored.
  for direction in directions:
    case jsTrim(direction)
    of "right": result = result or RIGHT
    of "left": result = result or LEFT
    of "up": result = result or UP
    of "down": result = result or DOWN
    of "x": result = result or RIGHT or LEFT
    of "y": result = result or UP or DOWN
    else: discard

func bit(mask, flag: int): float = (if (mask and flag) != 0: 1.0 else: 0.0)

func arrowAxis*(mask: int): string =
  ## An arrow along one axis has a shaft and heads wider than it. One that points along both axes
  ## is a box with a small point on each side it names.
  if mask != 0 and (mask and (UP or DOWN)) == 0: return "x"
  if mask != 0 and (mask and (RIGHT or LEFT)) == 0: return "y"
  ""

func arrowSize*(mask: int, tw, th: float): ArrowSize =
  let axis = arrowAxis(mask)
  let across = bit(mask, LEFT) - bit(mask, RIGHT)
  let along = bit(mask, UP) - bit(mask, DOWN)
  if axis == "x":
    let h = max(th + 8, 14.0) + 2 * OVERHANG
    let depth = min(h / 2, MAX_DEPTH)
    return ArrowSize(w: max(tw + 12, 16.0) + depth * (if mask == (RIGHT or LEFT): 2.0 else: 1.0),
                     h: h, dx: (across * depth) / 2, dy: 0)
  if axis == "y":
    let w = max(tw + 16, 14.0) + 2 * OVERHANG
    let depth = min(w / 2, MAX_DEPTH)
    return ArrowSize(w: w, h: max(th + 8, 16.0) + depth * (if mask == (UP or DOWN): 2.0 else: 1.0),
                     dx: 0, dy: (along * depth) / 2)
  ArrowSize(
    w: max(tw + 16, 24.0) + NUB * (bit(mask, LEFT) + bit(mask, RIGHT)),
    h: max(th + 8, 24.0) + NUB * (bit(mask, UP) + bit(mask, DOWN)),
    dx: (across * NUB) / 2,
    dy: (along * NUB) / 2)

func drawArrow*(mask: int, w, h: float, attrs: string): string =
  let axis = arrowAxis(mask)
  let x = w / 2
  let y = h / 2
  var p: seq[float]
  template has(flag: int): bool = (mask and flag) != 0
  if axis == "x":
    let depth = min(y, MAX_DEPTH)
    let s = y - OVERHANG
    let x0 = if has(LEFT): -x + depth else: -x
    let x1 = if has(RIGHT): x - depth else: x
    p = @[x0, -s, x1, -s]
    if has(RIGHT): p.add [x1, -y, x, 0, x1, y]
    p.add [x1, s, x0, s]
    if has(LEFT): p.add [x0, y, -x, 0, x0, -y]
  elif axis == "y":
    let depth = min(x, MAX_DEPTH)
    let s = x - OVERHANG
    let y0 = if has(UP): -y + depth else: -y
    let y1 = if has(DOWN): y - depth else: y
    p = @[s, y0, s, y1]
    if has(DOWN): p.add [x, y1, 0, y, -x, y1]
    p.add [-s, y1, -s, y0]
    if has(UP): p.add [-x, y0, 0, -y, x, y0]
  else:
    let x0 = if has(LEFT): -x + NUB else: -x
    let x1 = if has(RIGHT): x - NUB else: x
    let y0 = if has(UP): -y + NUB else: -y
    let y1 = if has(DOWN): y - NUB else: y
    let cx = (x0 + x1) / 2
    let cy = (y0 + y1) / 2
    let kx = min(10.0, (x1 - x0) / 2)
    let ky = min(10.0, (y1 - y0) / 2)
    p = @[x0, y0]
    if has(UP): p.add [cx - kx, y0, cx, -y, cx + kx, y0]
    p.add [x1, y0]
    if has(RIGHT): p.add [x1, cy - ky, x, cy, x1, cy + ky]
    p.add [x1, y1]
    if has(DOWN): p.add [cx + kx, y1, cx, y, cx - kx, y1]
    p.add [x0, y1]
    if has(LEFT): p.add [x0, cy + ky, -x, cy, x0, cy - ky]
  var points = ""
  var i = 0
  while i < p.len:
    points.add (if i > 0: " " else: "") & num(p[i]) & "," & num(p[i + 1])
    i += 2
  "<polygon points=\"" & points & "\" stroke-linejoin=\"round\"" & attrs & "/>"
