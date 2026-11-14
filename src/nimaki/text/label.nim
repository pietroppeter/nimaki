## port-of: src/text/label.ts
## port-status: conformant
## Its patterns stay hand-written scanners (decision 0016): they run on every label of every
## drawing, and nim-regex compiled to JavaScript costs microseconds a character (Pele's stress
## tests missed their time bounds with it).
##
## Labels are measured and broken into lines here. The regular expressions are scanners
## (porting guide); each one names the pattern it answers as.
import std/[strutils, tables, sets, math]
import entities, measurer, icons
import math as pmath
import ../js

type
  Span* = object
    text*: string
    style*: int
    icon*: string          ## "" for none (Pele's undefined)
    hasIcon*: bool
    math*: MathMarkup      ## nil for none
    width*: float

  Label* = object
    lines*: seq[seq[Span]]
    widths*: seq[float]
    width*, height*, size*, lineHeight*: float
    heights*: seq[float]   ## present only when math needs extra line height (empty otherwise)

const LINE_HEIGHT* = 1.5
const WRAPPED_LINE_HEIGHT = 1.3
  ## Lines of one wrapped label sit closer, so the label reads as one block.

const TAG_STYLES = {"b": Bold, "strong": Bold, "i": Italic, "em": Italic, "cite": Italic,
                    "dfn": Italic, "var": Italic, "code": Mono, "kbd": Mono, "samp": Mono,
                    "tt": Mono, "sub": Sub, "sup": Sup, "u": Underline, "ins": Underline}.toTable
const SHIFT = Sub or Sup
const HTML_TAGS = toHashSet((
    "a abbr address article aside audio b bdi bdo big blockquote body br button caption center cite code col " &
    "colgroup data dd del details dfn dialog div dl dt em embed fieldset figcaption figure font footer form h1 h2 " &
    "h3 h4 h5 h6 head header hr html i iframe img input ins kbd label legend li link main map mark meta meter nav " &
    "noscript object ol optgroup option output p picture pre progress q rp rt ruby s samp script section select " &
    "small source span strike strong style sub summary sup table tbody td template textarea tfoot th thead time " &
    "title tr track tt u ul var video wbr").split(' '))

# Break between any two Chinese or Japanese characters. Hangul is left out: Korean puts spaces
# between words.
func isCJK(c: int): bool =
  (c >= 0x2e80 and c <= 0x9fff) or (c >= 0xf900 and c <= 0xfaff) or (c >= 0xff00 and c <= 0xff60)

const CLOSE_CHARS = "、。，．：；！？）］｝」』】〕〉》〙〗ー…‥・ゝゞぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ,.:;!?)]}"
const OPEN_CHARS = "（［｛「『【〔〈《〘〖([{"

func runeSet(s: string): HashSet[int] =
  var i = 0
  while i < s.len:
    let (cp, size) = codePointAt(s, i)
    result.incl cp
    i += size

let closeSet = runeSet(CLOSE_CHARS)
let openSet = runeSet(OPEN_CHARS)

# Break hints: a zero-width space, and a soft hyphen, which shows as '-' where a line breaks.
func isHint(c: int): bool = c == 0x200b or c == 0xad
const SHY = "­"

# The helpers of pieceEnd take the string, not capture it: nim js copies a captured string at
# every call of the closure (porting guide, Code that JavaScript runs slowly).
func cpAt(s: string, i: int): int = (if i < s.len: codePointAt(s, i).rune else: -1)
func nextAt(s: string, i: int): int = i + codePointAt(s, i).size
func spacesAt(s: string, i: int): int =
  result = i
  while result < s.len and isJsSpace(cpAt(s, result)): result = nextAt(s, result)
proc closesAt(s: string, i: int): int =
  result = i
  while result < s.len and cpAt(s, result) in closeSet: result = nextAt(s, result)

proc pieceEnd(s: string, p: int): int =
  ## The end of the match of RE_PIECE at p:
  ## \s*(?:[OPEN]*[CJK][CLOSE]*|[^\s CJK HINT]+[HINT]*[CLOSE]*|[HINT]+)\s*|\s+
  template cp(i: int): int = cpAt(s, i)
  template next(i: int): int = nextAt(s, i)
  template spaces(i: int): int = spacesAt(s, i)
  template closes(i: int): int = closesAt(s, i)
  let a = spaces(p)
  if a < s.len:
    # [OPEN]*[CJK], backtracking over the opening marks
    var opens = @[a]
    var i = a
    while i < s.len and cp(i) in openSet:
      i = next(i)
      opens.add i
    for k in countdown(opens.high, 0):
      let at = opens[k]
      if at < s.len and isCJK(cp(at)):
        return spaces(closes(next(at)))
    let c = cp(a)
    if not isJsSpace(c) and not isCJK(c) and not isHint(c):
      var j = a
      while j < s.len:
        let d = cp(j)
        if isJsSpace(d) or isCJK(d) or isHint(d): break
        j = next(j)
      while j < s.len and isHint(cp(j)): j = next(j)
      return spaces(closes(j))
    if isHint(c):
      var j = a
      while j < s.len and isHint(cp(j)): j = next(j)
      return spaces(j)
  # \s+
  if p < s.len and isJsSpace(cp(p)): return spaces(p)
  -1

proc pieces(s: string): seq[string] =
  ## span.text.match(RE_PIECE) ?? []
  var p = 0
  while p < s.len:
    let e = pieceEnd(s, p)
    if e <= p:
      p += codePointAt(s, p).size
      continue
    result.add s[p ..< e]
    p = e

proc hasCJK(s: string): bool =
  var i = 0
  while i < s.len:
    let (c, size) = codePointAt(s, i)
    if isCJK(c): return true
    i += size

proc hasHint(s: string): bool = "​" in s or SHY in s

# Unique placeholders protect TeX from markup parsing and keep expressions aligned when tags
# are removed.
const MARK = 0xe000
const MAX_MARKS = 0x1900

func isMark(c: int): bool = c >= 0xe000 and c <= 0xf8ff

proc hasMark(s: string): bool =
  var i = 0
  while i < s.len:
    let (c, size) = codePointAt(s, i)
    if isMark(c): return true
    i += size

type Marks = ref object
  tex: seq[string]
  math: seq[MathMarkup]

var marks: Marks

func emptyLabel(): Label = Label()

proc dedent(text: string): string =
  let lines = text.split('\n')
  var least = high(int)
  for line in lines:
    if jsTrim(line) == "": continue
    let indent = line.len - jsTrimStart(line).len
    if indent < least: least = indent
  if least == high(int) or least == 0: return text
  var output: seq[string]
  for line in lines: output.add line[min(least, line.len - jsTrimStart(line).len) .. ^1]
  output.join("\n")

func plain(line: seq[Span]): bool =
  ## plain(line[line.length - 1])
  line.len > 0 and not line[^1].hasIcon and line[^1].math == nil

proc pushPlain(line: var seq[Span], text: string, style: int) =
  let decoded = decodeEntities(text)
  if plain(line) and line[^1].style == style: line[^1].text.add decoded
  else: line.add Span(text: decoded, style: style, width: 0)

proc pushText(line: var seq[Span], text: string, style: int) =
  if text == "": return
  if marks != nil and hasMark(text):
    let found = marks
    # text.split(/([-])/)
    var part = ""
    var i = 0
    while i < text.len:
      let (c, size) = codePointAt(text, i)
      if isMark(c):
        if part != "": pushPlain(line, part, style)
        part = ""
        let at = c - MARK
        let math = if at < found.math.len: found.math[at] else: nil
        if math != nil: line.add Span(text: "", style: style, math: math, width: math.width)
        else: pushPlain(line, "$$" & (if at < found.tex.len: found.tex[at] else: "undefined") & "$$", style)
      else:
        part.add text[i ..< i + size]
      i += size
    if part != "": pushPlain(line, part, style)
    return
  pushPlain(line, text, style)

proc pushIcons(line: var seq[Span], text: string, style: int) =
  if ":fa-" notin text:
    pushText(line, text, style)
    return
  var last = 0
  # /(fa[bklrs]?):fa-([\w-]+)/g
  var i = 0
  while i < text.len:
    var matched = false
    if text.continuesWith("fa", i):
      var j = i + 2
      if j < text.len and text[j] in {'b', 'k', 'l', 'r', 's'} and text.continuesWith(":fa-", j + 1): inc j
      if text.continuesWith(":fa-", j):
        let prefix = text[i ..< j]
        var k = j + 4
        while k < text.len and (isWordChar(text[k]) or text[k] == '-'): inc k
        if k > j + 4:
          matched = true
          let icon = prefix & ":fa-" & text[j + 4 ..< k]
          pushText(line, text[last ..< i], style)
          last = k
          if iconMarkup(icon) != "":
            line.add Span(text: "", style: style, icon: icon, hasIcon: true, width: 0)
          elif last < text.len and text[last] == ' ':
            # An icon the host does not have leaves no gap, nor the space that set it off from
            # the text.
            inc last
          elif last == text.len:
            if plain(line): line[^1].text = jsTrimEnd(line[^1].text)
          i = k
    if not matched: inc i
  pushText(line, text[last .. ^1], style)

type Open = object
  style: int
  shifts: seq[int]   ## Sub/sup stack; only the innermost tag shifts text.

proc matchTag(s: string, i: int): (bool, int, string) =
  ## /<\/?([a-zA-Z][\w-]*)(?:\s[^<>]*)?\/?>/y at i: whether it matches, its end, the tag name.
  var j = i + 1
  if j < s.len and s[j] == '/': inc j
  if j >= s.len or s[j] notin Letters: return
  let n0 = j
  while j < s.len and (isWordChar(s[j]) or s[j] == '-'): inc j
  let name = s[n0 ..< j]
  let n = spaceLenAt(s, j)
  if n > 0:
    var k = j + n
    while k < s.len and s[k] notin {'<', '>'}: inc k
    if k < s.len and s[k] == '>': return (true, k + 1, name)
  if j < s.len and s[j] == '/': inc j
  if j < s.len and s[j] == '>': return (true, j + 1, name)
  (false, 0, "")

proc inline(line: var seq[Span], source: string, markdown: bool, base: int, open: var Open) =
  ## Splits inline HTML and, for markdown labels, emphasis markers into styled spans.
  var style = open.style
  var marked = 0
  var text = ""
  var i = 0
  let n = source.len
  template flush() =
    pushIcons(line, text, style or (if open.shifts.len > 0: open.shifts[^1] else: 0))
    text = ""
  while i < n:
    let ch = source[i]
    if ch == '<':
      let (ok, stop, name) = matchTag(source, i)
      if ok:
        let tag = name.toLowerAscii
        let closing = source[i + 1] == '/'
        let bit = TAG_STYLES.getOrDefault(tag, 0)
        if (bit and SHIFT) != 0:
          flush()
          var at = -1
          for k in countdown(open.shifts.high, 0):
            if open.shifts[k] == bit:
              at = k
              break
          if not closing: open.shifts.add bit
          elif at != -1: open.shifts.delete(at)
        elif bit != 0:
          flush()
          open.style = if closing: (open.style and not bit) or (base and bit) else: open.style or bit
          style = if closing: (style and not bit) or (base and bit) else: style or bit
        # Other HTML tags are dropped and their text kept. Anything else shaped like a tag, such
        # as the type in List<T>, is text.
        if bit != 0 or tag in HTML_TAGS:
          i = stop
          continue
    elif markdown and (ch == '*' or ch == '_'):
      let double = i + 1 < n and source[i + 1] == ch
      let bit = if double: Bold else: Italic
      let length = if double: 2 else: 1
      let opening = (marked and bit) == 0
      let prevSpace = if i > 0: isJsSpaceBefore(source, i) else: true
      let nextSpace = if i + length < n: isJsSpaceAt(source, i + length) else: true
      let canOpen = opening and not nextSpace and
        source.find(if double: ch & ch else: $ch, i + length) != -1
      let canClose = not opening and not prevSpace
      let wordy = ch == '_' and i > 0 and isWordChar(source[i - 1]) and
        i + length < n and isWordChar(source[i + length])
      if (canOpen or canClose) and not wordy:
        flush()
        marked = if canOpen: marked or bit else: marked and not bit
        style = if canOpen: style or bit else: (style and not bit) or (base and bit)
        i += length
        continue
    text.add ch
    inc i
  flush()

proc measureSpans(line: var seq[Span], measurer: TextMeasurer, size: float): float =
  for span in line.mitems:
    span.width = if span.hasIcon: size * 1.25
                 elif span.math != nil: span.math.width
                 else: measurer.width(span.text, size, span.style)
    result += span.width

func dropLastUnit(s: string): string =
  ## s.slice(0, -1)
  if s.len == 0: s else: s[0 ..< prevRuneStart(s, s.len)]

proc wrap(line: seq[Span], measurer: TextMeasurer, size, max: float,
          output: var seq[seq[Span]], widths: var seq[float]) =
  var current: seq[Span]
  var width = 0.0
  template commit(hyphen: bool) =
    if plain(current):
      template last: untyped = current[^1]
      var trimmed = jsTrimEnd(last.text)
      if hyphen and last.text.endsWith(SHY): trimmed = dropLastUnit(trimmed) & "-"
      if trimmed != last.text:
        last.text = trimmed
        let w = measurer.width(trimmed, size, last.style)
        width += w - last.width
        last.width = w
    output.add current
    widths.add width
    current = @[]
    width = 0
  for index, span in line:
    if span.hasIcon or span.math != nil:
      let w = if span.math != nil: span.math.width else: size * 1.25
      if width > 0 and width + w > max: commit(false)
      var copy = span
      copy.width = w
      current.add copy
      width += w
      continue
    let parts = pieces(span.text)
    # A piece ending in a soft hyphen fits if its '-' does, or if the rest of the word does,
    # which hides the hyphen. The line only grows along a word, so no later hyphen in it fits
    # either, and the remaining width of each word makes this one check.
    let soft = SHY in span.text
    let n = if soft: parts.len else: 0
    var own = newSeq[float](n)
    var rest = newSeq[float](n + 1)
    for q in countdown(n - 1, 0):
      # A soft hyphen before a space is no break of its own: the space is.
      let shy = parts[q].endsWith(SHY)
      let stop = jsTrimEnd(parts[q])
      own[q] = measurer.width(if shy: dropLastUnit(stop) else: stop, size, span.style)
      # Word width beyond this span is unknown.
      rest[q] = if not shy: own[q]
                elif q == n - 1: (if index == line.high: own[q] else: Inf)
                else: own[q] + rest[q + 1]
    for p in 0 ..< parts.len:
      var part = parts[p]
      let partWidth = if soft: own[p] else: measurer.width(jsTrimEnd(part), size, span.style)
      let fits =
        if not soft or not part.endsWith(SHY): width + partWidth <= max
        else: width + measurer.width(dropLastUnit(part) & "-", size, span.style) <= max or
              width + rest[p] <= max
      if width > 0 and not fits:
        # Breaking at whitespace leaves a preceding soft hyphen hidden.
        commit(jsTrimStart(part) == part)
        part = jsTrimStart(part)
      if plain(current) and current[^1].style == span.style:
        current[^1].text.add part
        # Remeasuring for each zero-width piece would take quadratic time.
        if partWidth > 0 or jsTrimEnd(part) != part:
          let before = current[^1].width
          current[^1].width = measurer.width(current[^1].text, size, current[^1].style)
          width += current[^1].width - before
      else:
        let w = measurer.width(part, size, span.style)
        current.add Span(text: part, style: span.style, width: w)
        width += w
  if current.len > 0 or output.len == 0: commit(false)

func hasMarkup(raw: string): bool =
  ## RE_MARKUP: /[<\\\n*_]|fa[bklrs]?:fa-/
  for c in raw:
    if c in {'<', '\\', '\n', '*', '_'}: return true
  var i = raw.find("fa")
  while i != -1:
    var j = i + 2
    if j < raw.len and raw[j] in {'b', 'k', 'l', 'r', 's'} and raw.continuesWith(":fa-", j + 1): return true
    if raw.continuesWith(":fa-", j): return true
    i = raw.find("fa", i + 1)
  false

proc withHeights*(label: Label): Label

proc layoutLines(raw: string, markdown: bool, measurer: TextMeasurer, size, maxWidth: float,
                 base: int, lineHeight: float): Label

proc layoutMarkup(raw: string, markdown: bool, measurer: TextMeasurer, size, maxWidth: float,
                  base: int, lineHeight: float, found: Marks = nil): Label =
  let outer = marks
  marks = found
  try:
    let label = layoutLines(raw, markdown, measurer, size, maxWidth, base, lineHeight)
    result = if found != nil: withHeights(label) else: label
  finally:
    marks = outer

proc layoutLabel*(raw: string, markdown: bool, measurer: TextMeasurer, size, maxWidth: float,
                  base = 0): Label =
  ## `raw` "" stands for both "" and undefined, which Pele treats alike.
  if raw == "": return emptyLabel()
  let lineHeight = jsRound(size * LINE_HEIGHT)

  if mathActive() and "$$" in raw and not hasMark(raw):
    let found = Marks()
    # raw.replace(/\$\$(.+?)\$\$/g, ...): `.` stops at line terminators
    var marked = ""
    var i = 0
    while i < raw.len:
      if raw.continuesWith("$$", i):
        var j = i + 2
        var stop = -1
        while j < raw.len:
          if raw[j] in {'\n', '\r'} or raw.continuesWith(" ", j) or raw.continuesWith(" ", j): break
          if j > i + 2 and raw.continuesWith("$$", j):
            stop = j
            break
          j += codePointAt(raw, j).size
        if stop != -1:
          if found.tex.len == MAX_MARKS:
            marked.add raw[i ..< stop + 2]
          else:
            found.tex.add raw[i + 2 ..< stop]
            marked.add fromCodePoint(MARK + found.tex.len - 1)
          i = stop + 2
          continue
      marked.add raw[i]
      inc i
    if found.tex.len > 0:
      for tex in found.tex: found.math.add typeset(decodeEntities(tex), size)
      return layoutMarkup(marked, markdown, measurer, size, maxWidth, base, lineHeight, found)

  if not hasMarkup(raw) and '&' notin raw and "ﬂ" notin raw:
    let text = jsTrim(raw)
    let width = measurer.width(text, size, base)
    if width <= maxWidth or not (' ' in text or hasCJK(text) or hasHint(text)):
      return Label(lines: @[@[Span(text: text, style: base, width: width)]], widths: @[width],
                   width: width, height: lineHeight, size: size, lineHeight: lineHeight)
    var lines: seq[seq[Span]]
    var widths: seq[float]
    wrap(@[Span(text: text, style: base, width: width)], measurer, size, maxWidth, lines, widths)
    var widest = 0.0
    for w in widths:
      if w > widest: widest = w
    let snug = if lines.len > 1: jsRound(size * WRAPPED_LINE_HEIGHT) else: lineHeight
    return Label(lines: lines, widths: widths, width: widest, height: float(lines.len) * snug,
                 size: size, lineHeight: snug)
  layoutMarkup(raw, markdown, measurer, size, maxWidth, base, lineHeight)

proc splitBreaks(s: string): seq[string] =
  ## s.split(/<br\s*\/?>|\\n|\n/gi)
  var part = ""
  var i = 0
  while i < s.len:
    if s[i] == '\n':
      result.add part
      part = ""
      inc i
      continue
    if s[i] == '\\' and i + 1 < s.len and s[i + 1] == 'n':
      result.add part
      part = ""
      i += 2
      continue
    if s[i] == '<' and i + 2 < s.len and s[i + 1] in {'b', 'B'} and s[i + 2] in {'r', 'R'}:
      var j = i + 3
      while true:
        let n = spaceLenAt(s, j)
        if n == 0: break
        j += n
      if j < s.len and s[j] == '/': inc j
      if j < s.len and s[j] == '>':
        result.add part
        part = ""
        i = j + 1
        continue
    part.add s[i]
    inc i
  result.add part

proc layoutLines(raw: string, markdown: bool, measurer: TextMeasurer, size, maxWidth: float,
                 base: int, lineHeight: float): Label =
  let source = if markdown: jsTrim(dedent(raw.replace("\r\n", "\n").replace("\r", "\n"))) else: jsTrim(raw)
  var lines: seq[seq[Span]]
  var widths: seq[float]
  var width = 0.0
  # HTML tags can span explicit breaks; Markdown emphasis stays local to each line.
  var open = Open(style: base)
  for part in splitBreaks(source):
    var line: seq[Span]
    inline(line, jsTrim(part), markdown, base, open)
    let w = measureSpans(line, measurer, size)
    if w > maxWidth:
      wrap(line, measurer, size, maxWidth, lines, widths)
    else:
      lines.add line
      widths.add w
  for w in widths:
    if w > width: width = w
  let snug = if lines.len > 1: jsRound(size * WRAPPED_LINE_HEIGHT) else: lineHeight
  Label(lines: lines, widths: widths, width: width, height: float(lines.len) * snug, size: size,
        lineHeight: snug)

proc withHeights*(label: Label): Label =
  var heights: seq[float]
  var has = false
  for i in 0 ..< label.lines.len:
    var h = label.lineHeight
    for span in label.lines[i]:
      if span.math != nil: h = max(h, ceil(span.math.height + label.size / 4))
    if h != label.lineHeight and not has:
      has = true
      heights = newSeq[float](label.lines.len)
      for k in 0 ..< heights.len: heights[k] = label.lineHeight
    if has: heights[i] = h
  if not has:
    if label.heights.len == 0: return label
    result = label
    result.heights = @[]
    result.height = float(label.lines.len) * label.lineHeight
    return
  var height = 0.0
  for h in heights: height += h
  result = label
  result.heights = heights
  result.height = height

func hasMath*(line: seq[Span]): bool =
  for span in line:
    if span.math != nil: return true

func lineMiddle*(label: Label, i: int): float =
  if label.heights.len == 0: return (float(i) + 0.5) * label.lineHeight
  var top = 0.0
  for k in 0 ..< i: top += label.heights[k]
  top + label.heights[i] / 2

func labelLine*(label: Label, i: int): Label =
  let width = label.widths[i]
  let height = if label.heights.len > 0: label.heights[i] else: label.lineHeight
  result = Label(lines: @[label.lines[i]], widths: @[width], width: width, height: height,
                 size: label.size, lineHeight: label.lineHeight)
  if height != label.lineHeight: result.heights = @[height]
