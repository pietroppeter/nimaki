## port-of: src/diagrams/common/literal-label.ts
## port-status: draft
import std/[strutils, unicode]
from std/math import ceil
import ../../js
import ../../svg/builder
import ../../text/[label, measurer]

func isSpaceChar(c: string): bool =
  ## SPACE = /\s/, tested on one code point
  c.len > 0 and isJsSpace(codePointAt(c, 0).rune)

func codePoints(s: string): seq[string] =
  ## Array.from(s)
  for r in s.runes: result.add r.toUTF8

proc literalLabel*(text: string, measurer: TextMeasurer, size, room: float, style = 0): Label =
  ## Literal labels, including filenames and protocol fields, must retain every character but the
  ## spaces a line breaks at. Long words can break between code points; measurement stays
  ## bounded by one line of text.
  var lines: seq[string]
  for raw in text.split('\n'):
    let chars = codePoints(raw)
    if chars.len == 0: lines.add ""
    var start = 0
    while start < chars.len:
      proc join(first, length: int): string =
        for i in first ..< first + length: result.add chars[i]
      let first = start
      proc fits(length: int): bool = measurer.width(join(first, length), size, style) <= room
      var hi = 1
      while hi < chars.len - start and fits(hi): hi = min(chars.len - start, hi * 2)
      var lo = 1
      while lo < hi:
        let mid = int(ceil((lo + hi) / 2))
        if fits(mid): lo = mid
        else: hi = mid - 1
      var take = lo
      let wraps = start + take < chars.len
      if wraps and not isSpaceChar(chars[start + take]):
        for i in countdown(take - 1, 1):
          if isSpaceChar(chars[start + i]):
            take = i + 1
            break
      let line = join(start, take)
      let trimmed = jsTrimEnd(line)
      lines.add(if wraps: (if trimmed != "": trimmed else: line) else: line)
      start += take
      while wraps and start < chars.len and isSpaceChar(chars[start]): inc start
  if text == "": lines.setLen 0
  var widths: seq[float]
  for line in lines: widths.add measurer.width(line, size, style)
  var width = 0.0
  for w in widths: width = jsMax(width, w)
  let lineHeight = jsRound(size * 1.5)
  result = Label(widths: widths, width: width, height: float(lines.len) * lineHeight, size: size,
                 lineHeight: lineHeight)
  for i, line in lines: result.lines.add @[Span(text: line, style: style, width: widths[i])]

proc breakLabel*(label: Label, measurer: TextMeasurer, room: float): Label =
  if label.width <= room: return label
  var lines: seq[seq[Span]]
  var widths: seq[float]
  for i in 0 ..< label.lines.len:
    if label.widths[i] <= room:
      lines.add label.lines[i]
      widths.add label.widths[i]
      continue
    var current: seq[Span]
    var width = 0.0
    template commit() =
      lines.add current
      widths.add width
      current = @[]
      width = 0
    for span in label.lines[i]:
      if span.hasIcon or span.math != nil:
        if current.len > 0 and width + span.width > room: commit()
        current.add span
        width += span.width
        continue
      for char in codePoints(span.text):
        var hasLast = current.len > 0
        let joined = hasLast and not current[^1].hasIcon and current[^1].math == nil and
          current[^1].style == span.style
        let nextWidth = measurer.width(if joined: current[^1].text & char else: char, label.size, span.style)
        var added = nextWidth - (if joined: current[^1].width else: 0)
        if current.len > 0 and width + added > room:
          commit()
          hasLast = false
          added = measurer.width(char, label.size, span.style)
        if hasLast and not current[^1].hasIcon and current[^1].math == nil and current[^1].style == span.style:
          current[^1].text.add char
          current[^1].width += added
        else:
          current.add Span(text: char, style: span.style, width: added)
        width += added
    if current.len > 0 or label.lines[i].len == 0: commit()
  var width = 0.0
  for w in widths: width = jsMax(width, w)
  var broken = label
  broken.lines = lines
  broken.widths = widths
  broken.width = width
  broken.height = float(lines.len) * label.lineHeight
  if label.heights.len > 0: withHeights(broken) else: broken

proc leftLabelSvg*(label: Label, x, top: float, attrs: string): string =
  ## Writes a label with every line starting at x. A line is anchored at its start and keeps its
  ## spaces, so that where it begins does not depend on how its text was measured.
  let shared = sharedStyle(label)
  let opening = "<text" & textStyle(attrs, shared)
  for i in 0 ..< label.lines.len:
    let spans = label.lines[i]
    let cy = top + (float(i) + 0.5) * label.lineHeight
    var icon = false
    for span in spans:
      if span.hasIcon: icon = true
    if icon:
      let width = label.widths[i]
      var one = label
      one.lines = @[spans]
      one.widths = @[width]
      one.width = width
      one.height = label.lineHeight
      result.add labelSvg(one, x + width / 2, cy, attrs)
      continue
    var text = ""
    for span in spans:
      let own = spanStyle(span.style and not shared)
      text.add(if own != "": "<tspan" & own & ">" & esc(span.text) & "</tspan>" else: esc(span.text))
    if text != "":
      result.add opening & " x=\"" & num(x) & "\" y=\"" & num(cy + label.size * 0.35) &
        "\" text-anchor=\"start\" xml:space=\"preserve\">" & text & "</text>"
