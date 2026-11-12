## port-of: src/text/measurer.ts
## port-status: draft
##
## Only the metrics measurer: nimaki runs where there is no canvas, so `defaultMeasurer` is
## always `metricsMeasurer`, as Pele's is in Node. `canvasMeasurer` and `forgetTextWidths` have
## nothing to do here.
import std/strutils
import metrics
import ../js

type
  TextMeasurer* = object
    width*: proc (text: string, size: float, style: int): float {.noSideEffect, gcsafe.}

const
  # Pele's `const enum Style`: bits, combined as an `int`.
  Bold* = 1
  Italic* = 2
  Mono* = 4
  Sub* = 8
  Sup* = 16
  Underline* = 32

const SMALLER = 1.2 ## Approximate divisor for CSS font-size="smaller".

func parseInt36(s: string): int =
  for c in s:
    result = result * 36 + (if c in Digits: ord(c) - ord('0') else: ord(c) - ord('a') + 10)

func unpack(packed: string): array[95, uint16] =
  for i in 0 ..< 95:
    result[i] = uint16(parseInt36(packed[i * 2 .. i * 2 + 1]))

const regular = unpack(metrics.REGULAR)
const bold = unpack(metrics.BOLD)

func isWide(c: int): bool =
  (c >= 0x1100 and c <= 0x115f) or
    (c >= 0x2e80 and c <= 0xa4cf) or
    (c >= 0xac00 and c <= 0xd7a3) or
    (c >= 0xf900 and c <= 0xfaff) or
    (c >= 0xfe30 and c <= 0xfe4f) or
    (c >= 0xff00 and c <= 0xff60) or
    (c >= 0xffe0 and c <= 0xffe6) or
    (c >= 0xd800 and c <= 0xdbff)

func isZeroWidth(c: int): bool =
  c == 0xad or
    (c >= 0x300 and c <= 0x36f) or
    (c >= 0x200b and c <= 0x200f) or
    (c >= 0xdc00 and c <= 0xdfff) or
    (c >= 0xfe00 and c <= 0xfe0f) or
    c == 0xfeff

func metricsWidth(text: string, size: float, style: int): float =
  ## Estimates widths from a table of Arial advances. Used where no canvas is available.
  let mono = (style and Mono) != 0
  let eff = if (style and (Sub or Sup)) != 0: size / SMALLER else: size
  let table = if (style and Bold) != 0: bold else: regular
  var units = 0.0
  for c in codeUnits(text):
    if c < 32: continue
    if c < 127: units += (if mono: 600.0 else: float(table[c - 32]))
    elif isZeroWidth(c): continue
    elif isWide(c): units += (if mono: 1200.0 else: 1000.0)
    else: units += (if mono: 600.0 else: 580.0)
  (units * eff) / 1000

let metricsMeasurer* = TextMeasurer(width: metricsWidth)

proc defaultMeasurer*(fontFamily = "sans-serif", monoFamily = "monospace"): TextMeasurer =
  metricsMeasurer
