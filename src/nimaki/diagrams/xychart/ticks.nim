## port-of: src/diagrams/xychart/ticks.ts
## port-status: conformant
from std/math import floor
import ../../jsmath
import ../../js

func tickStep*(span, count: float): float =
  ## A step of 1, 2 or 5 times a power of ten that divides `span` into about `count` parts.
  ## A step below one comes back as the negative of its inverse, which is a whole number, so
  ## that tick values are found by division and print without rounding noise (0.3, not
  ## 0.30000000000000004).
  let raw = span / jsMax(count, 1)
  let power = floor(log10(raw))
  let unit = raw / pow(10, power)
  let factor = if unit >= 7.07: 10.0 elif unit >= 3.16: 5.0 elif unit >= 1.41: 2.0 else: 1.0
  if power < 0: -pow(10, -power) / factor else: factor * pow(10, power)

func tickIndex*(step, value: float): float =
  if step > 0: value / step else: value * -step

func tickValue*(step, index: float): float =
  if step > 0: index * step else: index / -step

func ticksBetween*(lo, hi, step: float): seq[float] =
  ## The multiples of a step from `lo` to `hi`, both included.
  var first = jsRound(tickIndex(step, lo))
  if tickValue(step, first) < lo: first += 1
  var last = jsRound(tickIndex(step, hi))
  if tickValue(step, last) > hi: last -= 1
  var i = first
  while i <= last and result.len < 100:
    result.add tickValue(step, i)
    i += 1
