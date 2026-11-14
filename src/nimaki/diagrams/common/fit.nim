## port-of: src/diagrams/common/fit.ts
## port-status: draft
import std/strutils
import ../../js
import ../../text/[label, measurer]
import ../../jsregex

const RE_TAG_START = jsre"/<(?!br\s*\/?>)/gi"
const RE_ICON = jsre"/:fa-/g"
# A line break, an encoded entity, a surrogate pair, or one character: the pieces a word can be cut between.
const RE_UNIT = jsre"/<br\s*\/?>|ﬂ°°?\w+¶ß|&#?\w+;|[\ud800-\udbff][\udc00-\udfff]|[\s\S]/gi"

proc plainLabel*(raw: string, measurer: TextMeasurer, size, max: float, base = 0): Label =
  ## Lays out text the way Mermaid's journey and timeline draw it: as plain text in which only
  ## <br> is markup, so other tags and icon names show as written instead of being read as
  ## formatting. `raw` "" stands for undefined too.
  var text = raw
  if '<' in text: text = text.replace(RE_TAG_START, "&lt;")
  if ":fa-" in text: text = text.replace(RE_ICON, "&colon;fa-")
  layoutLabel(text, false, measurer, size, max, base)

proc fitLabel*(raw: string, measurer: TextMeasurer, size, max: float, base = 0): Label =
  ## layoutLabel wraps at spaces only. For a box of fixed width, this also cuts any word too long
  ## to fit.
  let label = plainLabel(raw, measurer, size, max, base)
  if raw == "" or label.width <= max: return label
  var output = ""
  var width = 0.0
  for unit in raw.match(RE_UNIT):
    let long = utf16Len(unit) > 2
    if jsTrim(unit) == "" or (long and unit[0] == '<'):
      width = 0
    else:
      let w = measurer.width(if long: "x" else: unit, size, base)
      if width > 0 and width + w > max:
        output.add '\n'
        width = 0
      width += w
    output.add unit
  plainLabel(output, measurer, size, max, base)
