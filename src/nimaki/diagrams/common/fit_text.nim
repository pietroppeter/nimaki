## port-of: src/diagrams/common/fit-text.ts
## port-status: conformant
from std/math import floor
import ../../js
import ../../text/measurer

type Fitted* = object
  text*: string
  size*: float
  width*: float

proc fitText*(text: string, max, size, min: float, measurer: TextMeasurer,
              style = 0): (bool, Fitted) =
  ## Fits one line of text into a width: first by shrinking the font down to `min`, then by
  ## cutting the text and adding an ellipsis. (false, _) when not even one character fits
  ## (Pele's undefined).
  if text == "" or max <= 0: return
  var width = measurer.width(text, size, style)
  if width <= max: return (true, Fitted(text: text, size: size, width: width))

  # Width grows with font size, so one division lands on the right size or just above it.
  var fitted = jsMax(min, floor((size * max) / width))
  while fitted >= min:
    width = measurer.width(text, fitted, style)
    if width <= max: return (true, Fitted(text: text, size: fitted, width: width))
    fitted -= 1

  # Array.from(text): one item per code point
  var chars: seq[string]
  for c in codePoints(text): chars.add c
  proc prefix(count: int): string =
    for i in 0 ..< count: result.add chars[i]
  var low = 0
  var high = chars.len - 1
  while low < high:
    let mid = (low + high + 1) shr 1
    if measurer.width(jsTrimEnd(prefix(mid)) & "…", min, style) <= max: low = mid
    else: high = mid - 1
  if low == 0: return
  let cut = jsTrimEnd(prefix(low)) & "…"
  width = measurer.width(cut, min, style)
  if width <= max: (true, Fitted(text: cut, size: min, width: width)) else: (false, Fitted())
