## JavaScript's Math functions, in one place. Not a port of a file of Pele. Most call Nim's (the
## C library's); V8 computes some with its own algorithms, which can differ in the last bit
## (porting guide: math functions). Where difftest or the fuzzer found that it shows, V8's
## version replaces Nim's here, for every caller, in the C build: hypot, sin, cos, acos, atan
## and atan2 (fdlibm.nim). The JavaScript build calls V8's own.
import std/math as nm

when defined(js):
  func sin*(x: float): float {.inline.} = nm.sin(x)
  func cos*(x: float): float {.inline.} = nm.cos(x)
  func atan2*(y, x: float): float {.inline.} = nm.arctan2(y, x)
  func atan*(x: float): float {.inline.} = nm.arctan(x)
  func acos*(x: float): float {.inline.} = nm.arccos(x)
else:
  # Node's V8 computes these with fdlibm, which the C library does not always match in the
  # last bit; a venn layout of four sets turned that into a pixel.
  import fdlibm
  func sin*(x: float): float {.inline.} = fdSin(x)
  func cos*(x: float): float {.inline.} = fdCos(x)
  func atan2*(y, x: float): float {.inline.} = fdAtan2(y, x)
  func atan*(x: float): float {.inline.} = fdAtan(x)
  func acos*(x: float): float {.inline.} = fdAcos(x)
func tan*(x: float): float {.inline.} = nm.tan(x)
func asin*(x: float): float {.inline.} = nm.arcsin(x)
when defined(js):
  func hypot*(x, y: float): float {.inline.} = nm.hypot(x, y)
else:
  func hypot*(x, y: float): float =
    ## V8's `Math.hypot` (`MathHypot` in V8's src/builtins/math.tq): the largest magnitude
    ## divides both, and the squares are added with Kahan's compensation. The C library's
    ## differs in the last bit, which a venn layout of 300 rounds turns into 0.4 px.
    if x.isNaN or y.isNaN:
      if abs(x) == Inf or abs(y) == Inf: return Inf
      return NaN
    let ax = abs(x)
    let ay = abs(y)
    let top = max(ax, ay)
    if top == Inf: return Inf
    if top == 0: return 0
    var sum = 0.0
    var compensation = 0.0
    for v in [ax, ay]:
      let n = v / top
      let summand = n * n - compensation
      let preliminary = sum + summand
      compensation = (preliminary - sum) - summand
      sum = preliminary
    nm.sqrt(sum) * top
func pow*(x, y: float): float {.inline.} = nm.pow(x, y)
func exp*(x: float): float {.inline.} = nm.exp(x)
func log*(x: float): float {.inline.} = nm.ln(x)
func log10*(x: float): float {.inline.} = nm.log10(x)
func log2*(x: float): float {.inline.} = nm.log2(x)
func sqrt*(x: float): float {.inline.} = nm.sqrt(x)
