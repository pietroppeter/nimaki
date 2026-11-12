## JavaScript's Math functions, in one place. Not a port of a file of Pele. Today each one calls
## Nim's (the C library's): V8 computes some of them with its own algorithms, and they can differ
## in the last bit (porting guide: math functions). Never after `num()`'s rounding so far; when
## difftest finds a case where it shows, V8's version replaces Nim's here, for every caller.
import std/math as nm

func sin*(x: float): float {.inline.} = nm.sin(x)
func cos*(x: float): float {.inline.} = nm.cos(x)
func tan*(x: float): float {.inline.} = nm.tan(x)
func atan2*(y, x: float): float {.inline.} = nm.arctan2(y, x)
func atan*(x: float): float {.inline.} = nm.arctan(x)
func asin*(x: float): float {.inline.} = nm.arcsin(x)
func acos*(x: float): float {.inline.} = nm.arccos(x)
func hypot*(x, y: float): float {.inline.} = nm.hypot(x, y)
func pow*(x, y: float): float {.inline.} = nm.pow(x, y)
func exp*(x: float): float {.inline.} = nm.exp(x)
func log*(x: float): float {.inline.} = nm.ln(x)
func log10*(x: float): float {.inline.} = nm.log10(x)
func log2*(x: float): float {.inline.} = nm.log2(x)
func sqrt*(x: float): float {.inline.} = nm.sqrt(x)
