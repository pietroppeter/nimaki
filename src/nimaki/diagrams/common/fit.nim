## port-of: src/diagrams/common/fit.ts
## port-status: draft
import std/strutils
import ../../js
import ../../text/[label, measurer]

func tagStartAt(s: string, i: int): bool =
  ## RE_TAG_START: /<(?!br\s*\/?>)/gi, at byte `i`.
  if s[i] != '<': return false
  if i + 2 < s.len and s[i + 1] in {'b', 'B'} and s[i + 2] in {'r', 'R'}:
    var j = i + 3
    while true:
      let n = spaceLenAt(s, j)
      if n == 0: break
      j += n
    if j < s.len and s[j] == '/': inc j
    if j < s.len and s[j] == '>': return false
  true

func brEnd(s: string, i: int): int =
  ## /<br\s*\/?>/i at byte `i`: where it ends, or -1.
  if not (i + 2 < s.len and s[i] == '<' and s[i + 1] in {'b', 'B'} and s[i + 2] in {'r', 'R'}): return -1
  var j = i + 3
  while true:
    let n = spaceLenAt(s, j)
    if n == 0: break
    j += n
  if j < s.len and s[j] == '/': inc j
  if j < s.len and s[j] == '>': j + 1 else: -1

func wordsEnd(s: string, i: int): int =
  ## \w+ at byte `i`: where it ends, or -1 when there is none.
  var j = i
  while j < s.len and isWordChar(s[j]): inc j
  if j > i: j else: -1

func units(s: string): seq[string] =
  ## RE_UNIT: /<br\s*\/?>|ﬂ°°?\w+¶ß|&#?\w+;|[\ud800-\udbff][\udc00-\udfff]|[\s\S]/gi. A line break,
  ## an encoded entity, a surrogate pair, or one character: the pieces a word can be cut between.
  ## Without the u flag the case-insensitive match changes none of ﬂ, °, ¶ and ß.
  var i = 0
  while i < s.len:
    var e = brEnd(s, i)
    if e < 0 and s.continuesWith("ﬂ°", i):
      var j = i + "ﬂ°".len
      if s.continuesWith("°", j): j += "°".len
      let w = wordsEnd(s, j)
      if w > 0 and s.continuesWith("¶ß", w): e = w + "¶ß".len
    if e < 0 and s[i] == '&':
      var j = i + 1
      if j < s.len and s[j] == '#': inc j
      let w = wordsEnd(s, j)
      if w > 0 and w < s.len and s[w] == ';': e = w + 1
    if e < 0: e = i + codePointAt(s, i).size
    result.add s[i ..< e]
    i = e

proc plainLabel*(raw: string, measurer: TextMeasurer, size, max: float, base = 0): Label =
  ## Lays out text the way Mermaid's journey and timeline draw it: as plain text in which only
  ## <br> is markup, so other tags and icon names show as written instead of being read as
  ## formatting. `raw` "" stands for undefined too.
  var text = raw
  if '<' in text:
    var output = ""
    for i in 0 ..< text.len:
      if tagStartAt(text, i): output.add "&lt;" else: output.add text[i]
    text = output
  if ":fa-" in text: text = text.replace(":fa-", "&colon;fa-")
  layoutLabel(text, false, measurer, size, max, base)

proc fitLabel*(raw: string, measurer: TextMeasurer, size, max: float, base = 0): Label =
  ## layoutLabel wraps at spaces only. For a box of fixed width, this also cuts any word too long
  ## to fit.
  let label = plainLabel(raw, measurer, size, max, base)
  if raw == "" or label.width <= max: return label
  var output = ""
  var width = 0.0
  for unit in units(raw):
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
