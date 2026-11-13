## port-of: src/diagrams/cynefin/boundaries.ts
## port-status: draft
##
## The geometry of Mermaid's Cynefin boundaries: seeded wavy lines between the domains and the
## S-shaped cliff between Clear and Chaotic. Curves are flat lists of numbers: a start point, then
## six numbers (two control points and an end point) per cubic segment.
from std/math import trunc, floorMod, isNaN, classify, FloatClass
import ../../js
import ../../svg/builder

func toInt32(x: float): int32 =
  ## ECMAScript ToInt32.
  if x.isNaN or x.classify in {fcInf, fcNegInf}: return 0
  let m = floorMod(trunc(x), 4294967296.0)
  cast[int32](uint32(m))

func imul(a, b: int32): int32 =
  ## Math.imul: the low 32 bits of the product. Computed in 16-bit halves so that no partial
  ## product passes 2^48: in JavaScript, Nim's numbers are doubles, and a full 32 x 32-bit product
  ## would lose its low bits before they are masked (the JavaScript build of Nim 2.2.4 does).
  let ua = cast[uint32](a)
  let ub = cast[uint32](b)
  let lo = (ua and 0xffff'u32) * ub
  let hi = ((ua shr 16) * (ub and 0xffff'u32)) and 0xffff'u32
  cast[int32](lo + (hi shl 16))
func ushr(a: int32, n: int): int32 = cast[int32](cast[uint32](a) shr n)

func seededRandom*(seed: float): float =
  ## mulberry32, one step.
  var t = toInt32(seed + float(0x6d2b79f5))
  t = imul(t xor ushr(t, 15), t or 1)
  t = t xor (cast[int32](cast[uint32](t) + cast[uint32](imul(t xor ushr(t, 7), t or 61))))
  float(cast[uint32](t xor ushr(t, 14))) / 4294967296.0

func hashString*(str: string): float =
  var hash = 0'i32
  for c in codeUnits(str):
    hash = cast[int32](cast[uint32](hash) * 32'u32 - cast[uint32](hash) + uint32(c))
  float(hash)

func resolveSeed*(configured: float, id: string): float =
  ## A configured seed other than zero wins; otherwise the seed comes from the diagram's id.
  ## `configured` NaN for undefined.
  if not configured.isNaN and configured.classify notin {fcInf, fcNegInf} and configured != 0: return configured
  hashString(id)

type WaveOptions* = object
  segments*: int
  vertical*: bool
  pointStep*, controlStep*, controlShift*: float
    ## Multipliers Mermaid uses to vary the seed per point and per control point.
  pinStart*, pinEnd*: bool

const FOLD* = WaveOptions(segments: 7, vertical: true, pointStep: 17, controlStep: 31, controlShift: 7)
const HORIZON* = WaveOptions(segments: 7, vertical: false, pointStep: 23, controlStep: 37, controlShift: 11)

func wave*(start, to, center, seed, amplitude: float, o: WaveOptions): seq[float] =
  ## A wavy line along one axis from `start` to `to`, centered on `center` in the other axis.
  ## Points jitter by up to the amplitude; a pinned end stays on the center line.
  let step = (to - start) / float(o.segments)
  var along, across: seq[float]
  for i in 0 .. o.segments:
    let pinned = (i == 0 and o.pinStart) or (i == o.segments and o.pinEnd)
    along.add start + float(i) * step
    across.add(if pinned: center else: center + seededRandom(seed + float(i) * o.pointStep) * amplitude * 2 - amplitude)
  result = if o.vertical: @[across[0], along[0]] else: @[along[0], across[0]]
  for i in 0 ..< o.segments:
    let mid = (along[i] + along[i + 1]) / 2
    let offset = amplitude * 1.5 * (if i mod 2 == 0: 1.0 else: -1.0) *
      seededRandom(seed + float(i) * o.controlStep + o.controlShift)
    if o.vertical: result.add [across[i] + offset, mid, across[i + 1] - offset, mid, across[i + 1], along[i + 1]]
    else: result.add [mid, across[i] + offset, mid, across[i + 1] - offset, along[i + 1], across[i + 1]]

func cliff*(cx, top, bottom, amplitude: float): seq[float] =
  ## The cliff: a steep S from (cx, top) down to (cx, bottom).
  let h = bottom - top
  @[cx, top,
    cx + amplitude, top + h * 0.2, cx - amplitude * 1.5, top + h * 0.55, cx + amplitude * 0.5, top + h * 0.75,
    cx - amplitude, top + h * 0.85, cx + amplitude * 0.3, top + h * 0.95, cx, bottom]

func forward*(curve: seq[float]): string =
  ## Path commands that continue from the curve's start point to its end.
  var i = 2
  while i < curve.len:
    result.add "C" & num(curve[i]) & "," & num(curve[i + 1]) & " " & num(curve[i + 2]) & "," & num(curve[i + 3]) &
      " " & num(curve[i + 4]) & "," & num(curve[i + 5])
    i += 6

func backward*(curve: seq[float]): string =
  ## Path commands that continue from the curve's end point back to its start.
  var i = curve.len - 6
  while i >= 2:
    result.add "C" & num(curve[i + 2]) & "," & num(curve[i + 3]) & " " & num(curve[i]) & "," & num(curve[i + 1]) &
      " " & num(curve[i - 2]) & "," & num(curve[i - 1])
    i -= 6

func curvePath*(curve: seq[float]): string =
  "M" & num(curve[0]) & "," & num(curve[1]) & forward(curve)

func ellipsePath*(cx, cy, rx, ry: float): string =
  let r = num(rx) & "," & num(ry)
  "M" & num(cx - rx) & "," & num(cy) & "A" & r & " 0 1,1 " & num(cx + rx) & "," & num(cy) & "A" & r & " 0 1,1 " &
    num(cx - rx) & "," & num(cy) & "Z"
