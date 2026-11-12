## port-of: src/preprocess.ts
## port-status: draft
##
## The regular expressions of preprocess.ts are hand-written scanners here (porting guide:
## regular expressions); each one names the pattern it answers as.
import std/[strutils, json, tables, sets]
import errors, js
import util/yaml

type
  Config* = YamlValue
    ## `{ [key: string]: YamlValue }`: always a record (kind yMap).

  Preprocessed* = object
    text*: string
    title*: string        ## "" for undefined
    config*: Config
    withComments*: string ## the text before its comment lines are removed
    lineOffset*: int      ## the number of front matter lines before it

  Steps* = ref seq[seq[Edit]]
    ## The edits of each step, recorded only when a source position is needed (nil otherwise).

const UNSAFE_KEYS = ["__proto__", "constructor", "prototype"].toHashSet

func isLineTerminatorAt(s: string, i: int): bool =
  ## [\n\r  ] at byte i
  if i >= s.len: return false
  if s[i] in {'\n', '\r'}: return true
  s.continuesWith(" ", i) or s.continuesWith(" ", i)

func matchComment(text: string, p: int): int =
  ## /^\s*%%(?!{)[^\n]+\n?/m at p (where ^ holds): the end of the match, or -1.
  var i = p
  while true:
    let n = spaceLenAt(text, i)
    if n == 0: break
    i += n
  if not text.continuesWith("%%", i): return -1
  i += 2
  if i < text.len and text[i] == '{': return -1
  let first = i
  while i < text.len and text[i] != '\n': inc i
  if i == first: return -1
  if i < text.len: inc i
  i

proc commentSpans(text: string): seq[(int, int)] =
  ## The matches of RE_COMMENT, left to right.
  var p = 0
  while p <= text.len:
    let lineStart = p == 0 or text.isLineTerminatorAt(prevRuneStart(text, p))
    if lineStart and p < text.len:
      let stop = matchComment(text, p)
      if stop > p:
        result.add (p, stop)
        p = stop
        continue
    if p >= text.len: break
    p += codePointAt(text, p).size

proc removeSpans(text: string, spans: seq[(int, int)], steps: Steps): string =
  if steps != nil:
    var edits: seq[Edit]
    for (a, b) in spans: edits.add (a, b, 0)
    steps[].add edits
  var last = 0
  for (a, b) in spans:
    result.add text[last ..< a]
    last = b
  result.add text[last .. ^1]

proc cleanupComments*(text: string, steps: Steps = nil): string =
  var text = text
  if "%%" in text: text = removeSpans(text, commentSpans(text), steps)
  let trimmed = jsTrimStart(text)
  if steps != nil: steps[].add @[(0, text.len - trimmed.len, 0)]
  trimmed

func normalizeLineBreaks*(text: string): string =
  if '\r' in text: text.replace("\r\n", "\n").replace("\r", "\n") else: text

func isLineBreak(text: string, i: int): bool = i < text.len and text[i] in {'\n', '\r'}

type FrontMatter = object
  indent, body: string
  length: int

proc matchFrontMatter(text: string): (bool, FrontMatter) =
  ## Finds a `---` fenced YAML block at the start of the text the way Mermaid's front matter
  ## regex does.
  var cursor = 0
  while cursor < text.len and isJsSpaceAt(text, cursor) and not isLineBreak(text, cursor):
    cursor += codePointAt(text, cursor).size
  let indent = text[0 ..< cursor]
  if not text.continuesWith("---", cursor): return

  var openingEnds: seq[int]
  var i = cursor + 3
  while i < text.len and isJsSpaceAt(text, i):
    if isLineBreak(text, i): openingEnds.add i
    i += codePointAt(text, i).size
  if openingEnds.len == 0: return

  let fence = indent & "---"
  proc closingEnd(i: int): int =
    if not isLineBreak(text, i) or not text.continuesWith(fence, i + 1): return -1
    var last = -1
    var j = i + 1 + fence.len
    while j < text.len and isJsSpaceAt(text, j):
      if isLineBreak(text, j): last = j
      j += codePointAt(text, j).size
    last

  let needle = "\n" & fence
  var lastFence = -1
  var k = text.rfind(needle)
  while k > openingEnds[0]:
    if closingEnd(k) != -1:
      lastFence = k
      break
    k = if k - 1 >= 0: text.rfind(needle, last = k - 1 + needle.len - 1) else: -1
  if lastFence == -1: return

  var openingEnd = openingEnds[0]
  for candidate in openingEnds:
    if candidate < lastFence: openingEnd = candidate

  let bodyStart = openingEnd + 1
  let firstAt = if bodyStart > 0: bodyStart - 1 else: 0
  var j = text.find(needle, firstAt)
  while j != -1 and j <= lastFence:
    if j >= bodyStart:
      let stop = closingEnd(j)
      if stop != -1:
        return (true, FrontMatter(indent: indent, body: text[bodyStart ..< j], length: stop + 1))
    j = text.find(needle, j + 1)

proc merge(target, source: Config): Config =
  for key, value in source.fields:
    if key in UNSAFE_KEYS: continue
    let current = target.fields.getOrDefault(key, nil)
    if isRecord(value) and isRecord(current): discard merge(current, value)
    elif isRecord(value): target.fields[key] = merge(ymap(), value)
    else: target.fields[key] = value
  target

proc fromJson(j: JsonNode): YamlValue =
  case j.kind
  of JNull: ynull()
  of JBool: ybool(j.bval)
  of JInt: ynum(float(j.num))
  of JFloat: ynum(j.fnum)
  of JString: ystr(j.str)
  of JArray:
    var items: seq[YamlValue]
    for it in j.elems: items.add fromJson(it)
    yseq(items)
  of JObject:
    let m = ymap()
    for k, v in j.fields: m.fields[k] = fromJson(v)
    m

type DirectiveMatch = object
  first, last: int
  kind: string           ## match[1] ?? match[2]
  hasArgs: bool          ## match[4] !== undefined
  args: string

proc matchDirective(s: string, p: int): (bool, DirectiveMatch) =
  ## /%{2}{\s*(?:(\w+)\s*:|(\w+))\s*(?:(\w+)|((?:(?!}%{2}).|\r?\n)*))?\s*(?:}%{2})?/i at p.
  if not s.continuesWith("%%{", p): return
  var i = p + 3
  proc spaces(i: var int) =
    while true:
      let n = spaceLenAt(s, i)
      if n == 0: break
      i += n
  spaces(i)
  if i >= s.len or not isWordChar(s[i]): return
  let w0 = i
  while i < s.len and isWordChar(s[i]): inc i
  var m = DirectiveMatch(first: p, kind: s[w0 ..< i])
  var j = i
  spaces(j)
  if j < s.len and s[j] == ':': i = j + 1
  spaces(i)
  if i < s.len and isWordChar(s[i]):
    while i < s.len and isWordChar(s[i]): inc i
  else:
    let a0 = i
    while i < s.len:
      if s.continuesWith("}%%", i): break
      if s[i] == '\n': inc i
      elif s[i] == '\r':
        if i + 1 < s.len and s[i + 1] == '\n': i += 2
        else: break
      elif s.isLineTerminatorAt(i): break
      else: i += codePointAt(s, i).size
    m.hasArgs = true
    m.args = s[a0 ..< i]
  spaces(i)
  if s.continuesWith("}%%", i): i += 3
  m.last = i
  (true, m)

proc directiveMatches(s: string): seq[DirectiveMatch] =
  var p = s.find("%%{")
  while p != -1:
    let (ok, m) = matchDirective(s, p)
    if ok:
      result.add m
      p = s.find("%%{", max(m.last, p + 1))
    else:
      p = s.find("%%{", p + 1)

proc directives(text: string, config: Config, steps: Steps): string =
  if "%%{" notin text: return text
  let normalized = jsTrim(text).replace('\'', '"')
  for match in directiveMatches(normalized):
    let kind = match.kind
    if kind == "wrap":
      config.fields["wrap"] = ybool(true)
    elif (kind == "init" or kind == "initialize") and match.hasArgs and match.args != "":
      try:
        let args = fromJson(jsonParse(jsTrim(match.args)))
        if isRecord(args): discard merge(config, args)
      except CatchableError:
        discard # Mermaid ignores an init directive whose body is not valid JSON.
  var spans: seq[(int, int)]
  for m in directiveMatches(text): spans.add (m.first, m.last)
  removeSpans(text, spans, steps)

proc htmlTags(text: string): string =
  ## text.replace(/<(\w+)([^>]*)>/g, (_m, tag, attrs) => '<' + tag + attrs.replace(/="([^"]*)"/g, "='$1'") + '>')
  var i = 0
  while i < text.len:
    if text[i] == '<' and i + 1 < text.len and isWordChar(text[i + 1]):
      var j = i + 1
      while j < text.len and isWordChar(text[j]): inc j
      let tag = text[i + 1 ..< j]
      let close = text.find('>', j)
      if close != -1:
        let attrs = text[j ..< close]
        var out2 = ""
        var k = 0
        while k < attrs.len:
          if attrs.continuesWith("=\"", k):
            let q = attrs.find('"', k + 2)
            if q != -1:
              out2.add "='" & attrs[k + 2 ..< q] & "'"
              k = q + 1
              continue
          out2.add attrs[k]
          inc k
        result.add "<" & tag & out2 & ">"
        i = close + 1
        continue
    result.add text[i]
    inc i

proc preprocess*(source: string, steps: Steps = nil): Preprocessed =
  ## `steps` maps normalized source to `withComments`.
  var text = normalizeLineBreaks(source)
  # A tag needs a closing bracket, so nothing after the last one can match.
  let lastClose = if '<' in text: text.rfind('>') else: -1
  if lastClose > 0:
    text = htmlTags(text[0 .. lastClose]) & text[lastClose + 1 .. ^1]

  let config = ymap()
  var title = ""
  var lineOffset = 0

  var front: FrontMatter
  var found = false
  if "---" in text: (found, front) = matchFrontMatter(text)
  if found:
    let body =
      if front.indent.len > 0:
        var lines: seq[string]
        for line in front.body.split('\n'):
          lines.add(if line.startsWith(front.indent): line[front.indent.len .. ^1] else: line)
        lines.join("\n")
      else: front.body
    var parsed: YamlValue
    try:
      parsed = parseYaml(body)
    except CatchableError as error:
      raise newPeleError("Front matter is not valid YAML. " & error.msg, "syntax")
    if isRecord(parsed):
      if truthy(parsed["title"]): title = jsStr(parsed["title"])
      if isRecord(parsed["config"]): discard merge(config, parsed["config"])
      if truthy(parsed["displayMode"]):
        var gantt = config["gantt"]
        if not isRecord(gantt):
          gantt = ymap()
          config.fields["gantt"] = gantt
        gantt.fields["displayMode"] = ystr(jsStr(parsed["displayMode"]))
    var i = text.find('\n')
    while i != -1 and i < front.length:
      inc lineOffset
      i = text.find('\n', i + 1)
    text = text[front.length .. ^1]
    if steps != nil: steps[].add @[(0, front.length, 0)]

  text = directives(text, config, steps)
  Preprocessed(text: cleanupComments(text), title: title, config: config, withComments: text,
               lineOffset: lineOffset)

proc recording(steps: Steps): int =
  ## Starts the edits of a new step; returns its index (-1 when not recording).
  if steps == nil: return -1
  steps[].add @[]
  steps[].high

proc dropColorSemicolons(text: string, keyword: string, steps: Steps): string =
  ## Does what Mermaid's `text.replace(/keyword.*:\S*#.*;/g, drop the last character)` does:
  ## on a line where the keyword is followed by a colon, a color-like `#`, and later a
  ## semicolon, the last semicolon goes. Mermaid's regex backtracks without bound; this is
  ## one pass.
  let edits = recording(steps)
  var start = text.find(keyword)
  if start == -1: return text
  var output = ""
  var last = 0
  while start != -1:
    var lineEnd = start
    while lineEnd < text.len and not text.isLineTerminatorAt(lineEnd):
      lineEnd += codePointAt(text, lineEnd).size
    var afterColon = false
    var hash = -1
    var j = start + keyword.len
    while j < lineEnd:
      let (c, size) = codePointAt(text, j)
      if c == 58:
        afterColon = true
      elif c == 35:
        if afterColon:
          hash = j
          break
      elif isJsSpace(c):
        afterColon = false
      j += size
    if hash != -1:
      let semi = if lineEnd - 1 >= 0: text.rfind(';', last = lineEnd - 1) else: -1
      if semi > hash:
        if edits >= 0: steps[edits].add (semi, semi + 1, 0)
        output.add text[last ..< semi]
        last = semi + 1
    start = if lineEnd >= text.len: -1 else: text.find(keyword, lineEnd + 1)
  if last == 0: text else: output & text[last .. ^1]

proc encodeEntities*(text: string, steps: Steps = nil): string =
  ## Mermaid hides `#name;` entity codes behind placeholder characters so `#` and `;` survive
  ## parsing.
  if '#' notin text: return text
  let text = dropColorSemicolons(dropColorSemicolons(text, "style", steps), "classDef", steps)
  let edits = recording(steps)
  # text.replace(/#\w+;/g, ...)
  var i = 0
  while i < text.len:
    if text[i] == '#':
      var j = i + 1
      while j < text.len and isWordChar(text[j]): inc j
      if j > i + 1 and j < text.len and text[j] == ';':
        let inner = text[i + 1 ..< j]
        let code = (if inner.allCharsInSet(Digits): "ﬂ°°" else: "ﬂ°") & inner & "¶ß"
        if edits >= 0: steps[edits].add (i, j + 1, code.len)
        result.add code
        i = j + 1
        continue
    result.add text[i]
    inc i
