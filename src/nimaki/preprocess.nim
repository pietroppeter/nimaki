## port-of: src/preprocess.ts
## port-status: draft
import std/[strutils, json, tables, sets]
import errors, js, jsregex
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

const
  RE_COMMENT = jsre"/^\s*%%(?!{)[^\n]+\n?/gm"
  RE_DIRECTIVE = jsre"/%{2}{\s*(?:(\w+)\s*:|(\w+))\s*(?:(\w+)|((?:(?!}%{2}).|\r?\n)*))?\s*(?:}%{2})?/gi"
  RE_HTML_TAG = jsre"/<(\w+)([^>]*)>/g"
  RE_ATTR = jsre"""/="([^"]*)"/g"""
const UNSAFE_KEYS = ["__proto__", "constructor", "prototype"].toHashSet

func replacements(text: string, re: JsRegExp, length: int): seq[Edit] =
  ## `replacements` of errors.ts: where each match is, and the length that replaces it.
  for m in re.matches(text): result.add (m.index, m.stop, length)

proc removeAll(text: string, re: JsRegExp, steps: Steps): string =
  if steps != nil: steps[].add replacements(text, re, 0)
  text.replace(re, "")

proc cleanupComments*(text: string, steps: Steps = nil): string =
  var text = text
  if "%%" in text: text = removeAll(text, RE_COMMENT, steps)
  let trimmed = jsTrimStart(text)
  if steps != nil: steps[].add @[(0, text.len - trimmed.len, 0)]
  trimmed

func normalizeLineBreaks*(text: string): string =
  if '\r' in text: text.replace(jsre"/\r\n?/g", "\n") else: text

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

proc fromJson*(j: JsonNode): YamlValue =
  ## A JSON value as the YAML value frontmatter would give (used for `config` in options).
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

proc directives(text: string, config: Config, steps: Steps): string =
  if "%%{" notin text: return text
  let normalized = jsTrim(text).replace('\'', '"')
  for match in RE_DIRECTIVE.matches(normalized):
    let kind = if match.has(1): match[1] else: match[2]
    if kind == "wrap":
      config.fields["wrap"] = ybool(true)
    elif (kind == "init" or kind == "initialize") and match[4] != "":
      try:
        let args = fromJson(jsonParse(jsTrim(match[4])))
        if isRecord(args): discard merge(config, args)
      except CatchableError:
        discard # Mermaid ignores an init directive whose body is not valid JSON.
  removeAll(text, RE_DIRECTIVE, steps)

proc preprocess*(source: string, steps: Steps = nil): Preprocessed =
  ## `steps` maps normalized source to `withComments`.
  var text = normalizeLineBreaks(source)
  # A tag needs a closing bracket, so nothing after the last one can match.
  let lastClose = if '<' in text: text.rfind('>') else: -1
  if lastClose > 0:
    text = text[0 .. lastClose].replace(RE_HTML_TAG, func (m: JsMatch): string =
      "<" & m[1] & m[2].replace(RE_ATTR, "='$1'") & ">") & text[lastClose + 1 .. ^1]

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

const
  RE_ENTITY = jsre"/#\w+;/g"
  RE_INT = jsre"/^\+?\d+$/"
  RE_LINE_BREAK = newRegExp("[\\n\\r" & "\u2028\u2029" & "]", "g")

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
    let stop = RE_LINE_BREAK.matchEnd(text, start)
    let lineEnd = if stop >= 0: stop - 1 else: text.len
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
  text.replace(RE_ENTITY, proc (m: JsMatch): string =
    let inner = m[0][1 ..< m[0].len - 1]
    result = (if RE_INT.test(inner): "ﬂ°°" else: "ﬂ°") & inner & "¶ß"
    if edits >= 0: steps[edits].add (m.index, m.stop, result.len))
