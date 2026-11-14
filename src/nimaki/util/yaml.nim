## port-of: src/util/yaml.ts
## port-status: draft
##
## A small YAML reader covering what Mermaid feeds to js-yaml with the JSON schema:
## block and flow collections, quoted and plain scalars, and block scalars.
##
## JavaScript's `undefined` is `nil` here; YAML's `null` is a value of kind `yNull`.
import std/[tables, strutils, math]
import ../js
import ../jsregex
import ../errors

type
  YamlKind* = enum yNull, yBool, yNumber, yString, ySeq, yMap
  YamlValue* = ref object
    case kind*: YamlKind
    of yNull: discard
    of yBool: b*: bool
    of yNumber: n*: float
    of yString: s*: string
    of ySeq: items*: seq[YamlValue]
    of yMap: fields*: OrderedTable[string, YamlValue]

  YamlError* = object of CatchableError
  Incomplete = object of CatchableError
    ## A quoted scalar or flow collection runs past the text read so far.

func ynull*(): YamlValue = YamlValue(kind: yNull)
func ybool*(b: bool): YamlValue = YamlValue(kind: yBool, b: b)
func ynum*(n: float): YamlValue = YamlValue(kind: yNumber, n: n)
func ystr*(s: string): YamlValue = YamlValue(kind: yString, s: s)
func yseq*(items: seq[YamlValue] = @[]): YamlValue = YamlValue(kind: ySeq, items: items)
func ymap*(): YamlValue = YamlValue(kind: yMap)

func isRecord*(v: YamlValue): bool = v != nil and v.kind == yMap

func `[]`*(v: YamlValue, key: string): YamlValue =
  ## `v[key]` of a record, `undefined` (nil) otherwise.
  if v.isRecord: v.fields.getOrDefault(key, nil) else: nil

func `[]=`*(v: YamlValue, key: string, value: YamlValue) =
  v.fields[key] = value

func jsStr*(v: YamlValue): string =
  ## `String(v)`.
  if v == nil: return "undefined"
  case v.kind
  of yNull: "null"
  of yBool: (if v.b: "true" else: "false")
  of yNumber: jsString(v.n)
  of yString: v.s
  of ySeq:
    var parts: seq[string]
    for it in v.items: parts.add(if it == nil or it.kind == yNull: "" else: jsStr(it))
    parts.join(",")
  of yMap: "[object Object]"

func truthy*(v: YamlValue): bool =
  ## JavaScript truthiness.
  if v == nil: return false
  case v.kind
  of yNull: false
  of yBool: v.b
  of yNumber: not (v.n == 0 or v.n.isNaN)
  of yString: v.s.len > 0
  else: true

proc yamlError(msg: string): ref YamlError = newException(YamlError, msg)

const MAX_DEPTH = 64

proc assign(target: YamlValue, key: string, value: YamlValue) =
  target.fields[key] = value

type Reader = ref object
  lines: seq[string]
  i: int

proc newReader(src: string): Reader =
  let text = if '\r' in src: src.replace(jsre"/\r\n?/g", "\n") else: src
  Reader(lines: text.split('\n'))

proc skipBlank(r: Reader) =
  while r.i < r.lines.len:
    let t = jsTrim(r.lines[r.i])
    if t != "" and t[0] != '#' and t != "---": break
    inc r.i

proc indent(r: Reader): int =
  let line = r.lines[r.i]
  var k = 0
  while k < line.len and line[k] == ' ': inc k
  if k < line.len and line[k] == '\t': raise yamlError("YAML: tabs are not allowed for indentation")
  k

func at(s: string, i: int): char =
  ## `s[i]`, or '\0' for undefined past either end.
  if i >= 0 and i < s.len: s[i] else: '\0'

const
  RE_INT = jsre"/^[-+]?(?:0|[1-9][0-9]*)$/"
  RE_HEX = jsre"/^[-+]?0x[0-9a-fA-F]+$/"
  RE_OCT = jsre"/^[-+]?0o[0-7]+$/"
  RE_BIN = jsre"/^[-+]?0b[01]+$/"
  RE_FLOAT = jsre"/^[-+]?(?:[0-9][0-9]*(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?$/"

func jsNumberOf(s: string): float =
  ## `Number(s)` for what RE_INT, RE_FLOAT, RE_HEX, RE_OCT and RE_BIN accept (unsigned for
  ## the prefixed ones).
  if s.len > 2 and s[0] == '0' and s[1] in {'x', 'o', 'b'}:
    let base = case s[1]
      of 'x': 16.0
      of 'o': 8.0
      else: 2.0
    var v = 0.0
    for c in s[2 .. ^1]:
      v = v * base + float(if c in Digits: ord(c) - ord('0') else: (ord(c.toLowerAscii) - ord('a') + 10))
    return v
  var t = s
  if t.len > 0 and t[^1] == '.': t.add '0'
  if t.startsWith(".") : t = "0" & t
  elif t.startsWith("-.") or t.startsWith("+."): t = t[0] & "0" & t[1 .. ^1]
  t = t.replace(".e", ".0e").replace(".E", ".0E")
  parseFloat(t)

func isBlankCh(ch: char): bool = ch in {' ', '\t', '\n', '\r'}

const KEY_START = {' ', '\t', '\n', '\r', '\v', '\f', '#', ':', ',', '[', ']', '{', '}', '&', '*',
                   '!', '|', '>', '\'', '"', '%', '@', '`'}

proc splitKey(line: string): tuple[ok: bool, key: string, length: int] =
  ## Splits `key: rest` at the start of a line: the raw key and the offset where the value starts.
  let first = line.at(0)
  var stop, colon: int
  if first == '"' or first == '\'':
    var i = 1
    while true:
      if i >= line.len: return (false, "", 0)
      let c = line[i]
      if first == '"' and c == '\\':
        i += 2
      elif c == first:
        if first == '"' or line.at(i + 1) != '\'': break
        i += 2
      else:
        inc i
    stop = i + 1
    colon = stop
    while isBlankCh(line.at(colon)): inc colon
    if line.at(colon) != ':': return (false, "", 0)
  else:
    if line.len == 0 or first in KEY_START or isJsSpaceAt(line, 0): return (false, "", 0)
    if first == '-' and (line.len < 2 or isBlankCh(line[1]) or line[1] == ':' or line[1] == '#'):
      return (false, "", 0)
    colon = 1
    while colon < line.len and line[colon] != ':' and line[colon] != '#': inc colon
    if line.at(colon) != ':': return (false, "", 0)
    stop = colon
    while isBlankCh(line.at(stop - 1)): dec stop
  var length = colon + 1
  if length < line.len and not isBlankCh(line[length]): return (false, "", 0)
  while isBlankCh(line.at(length)): inc length
  (true, line[0 ..< stop], length)

proc scalar(raw: string): YamlValue =
  let s = jsTrim(raw)
  if s == "" or s == "~" or s == "null" or s == "Null" or s == "NULL": return ynull()
  if s == "true" or s == "True" or s == "TRUE": return ybool(true)
  if s == "false" or s == "False" or s == "FALSE": return ybool(false)
  let c = s[0]
  if c != '-' and c != '+' and c != '.' and (c < '0' or c > '9'): return ystr(s)
  if RE_INT.test(s) or RE_FLOAT.test(s): return ynum(jsNumberOf(s))
  if RE_HEX.test(s) or RE_OCT.test(s) or RE_BIN.test(s):
    let neg = s[0] == '-'
    let v = jsNumberOf(if neg or s[0] == '+': s[1 .. ^1] else: s)
    return ynum(if neg: -v else: v)
  if jsre"/^[-+]?\.(?:inf|Inf|INF)$/".test(s): return ynum(if s[0] == '-': -Inf else: Inf)
  if jsre"/^\.(?:nan|NaN|NAN)$/".test(s): return ynum(NaN)
  ystr(s)

proc escapeOf(e: char, ok: var bool): string =
  ok = true
  case e
  of '0': "\0"
  of 'a': "\x07"
  of 'b': "\b"
  of 't': "\t"
  of 'n': "\n"
  of 'v': "\v"
  of 'f': "\f"
  of 'r': "\r"
  of 'e': "\x1b"
  of ' ': " "
  of '"': "\""
  of '/': "/"
  of '\\': "\\"
  of 'N': fromCodePoint(0x85)
  of '_': fromCodePoint(0xa0)
  of 'L': fromCodePoint(0x2028)
  of 'P': fromCodePoint(0x2029)
  else:
    ok = false
    ""

proc fold(text: string): string =
  ## Folds the line breaks of a scalar: blanks around a break go, one break becomes a space, and
  ## each further break stays.
  if '\n' notin text: return text
  var lines = text.split('\n')
  let last = lines.high
  for i in 0 .. last:
    let line = lines[i]
    var first = 0
    var stop = line.len
    if i > 0:
      while first < stop and line[first] in {' ', '\t'}: inc first
    if i < last:
      while stop > first and line[stop - 1] in {' ', '\t'}: dec stop
    lines[i] = line[first ..< stop]
  lines.join("\n").replace(jsre"/\n+/g", func (m: JsMatch): string =
    if m[0].len == 1: " " else: repeat('\n', m[0].len - 1))

proc unquoteDouble(body: string): string =
  if '\\' notin body: return fold(body)
  let s = fold(body.replace(jsre"/\\\n[ \t]*/g", ""))
  var i = 0
  while i < s.len:
    let ch = s[i]
    if ch != '\\':
      result.add ch
      inc i
      continue
    inc i
    let e = s.at(i)
    if e in {'x', 'u', 'U'}:
      let length = if e == 'x': 2 elif e == 'u': 4 else: 8
      let hex = s[min(i + 1, s.len) ..< min(i + 1 + length, s.len)]
      var cp = 0
      var n = 0
      for c in hex:
        if c notin HexDigits: break
        cp = cp * 16 + parseHexInt($c)
        inc n
      if n == 0 or cp > 0x10FFFF:
        # String.fromCodePoint throws a RangeError, which render() reports as a limit
        raise newException(JsRangeError, "Invalid code point " & (if n == 0: "NaN" else: $cp))
      result.add fromCodePoint(cp)
      i += length
    else:
      var ok: bool
      let r = escapeOf(e, ok)
      if not ok: raise yamlError("YAML: unknown escape sequence")
      result.add r
    inc i

proc skip(s: string, pos: int, commas: bool): int =
  var pos = pos
  while pos < s.len:
    let c = s[pos]
    if c in {' ', '\n', '\t', '\r'} or (commas and c == ','):
      inc pos
    elif c == '#' and (pos == 0 or isJsSpaceBefore(s, pos)):
      let nl = s.find('\n', pos)
      pos = if nl == -1: s.len else: nl
    else:
      break
  pos

proc entryStart(ch: char, separated: bool) =
  ## Entries of a flow collection are separated by exactly one comma, as js-yaml requires.
  if not separated: raise yamlError("YAML: missed comma between flow collection entries")
  if ch == ',': raise yamlError("YAML: expected the node content, but found ','")

proc flow(s: string, pos: int, stops: string, depth = 0): (YamlValue, int) =
  ## Parses a flow value starting at s[pos]; returns the value and the index after it.
  if depth > MAX_DEPTH: raise yamlError("YAML: nesting is too deep")
  var pos = skip(s, pos, false)
  let ch = s.at(pos)
  if ch == '{':
    let output = ymap()
    inc pos
    var separated = true
    while true:
      pos = skip(s, pos, false)
      if pos >= s.len: raise newException(Incomplete, "YAML: unexpected end of the stream within a flow collection")
      if s[pos] == '}': return (output, pos + 1)
      entryStart(s[pos], separated)
      var key: YamlValue
      (key, pos) = flow(s, pos, ":,}", depth + 1)
      pos = skip(s, pos, false)
      var value = ynull()
      if s.at(pos) == ':': (value, pos) = flow(s, pos + 1, ",}", depth + 1)
      assign(output, jsStr(key), value)
      pos = skip(s, pos, false)
      separated = s.at(pos) == ','
      if separated: inc pos
  if ch == '[':
    let output = yseq()
    inc pos
    var separated = true
    while true:
      pos = skip(s, pos, false)
      if pos >= s.len: raise newException(Incomplete, "YAML: unexpected end of the stream within a flow collection")
      if s[pos] == ']': return (output, pos + 1)
      entryStart(s[pos], separated)
      var value: YamlValue
      (value, pos) = flow(s, pos, ",]", depth + 1)
      output.items.add value
      pos = skip(s, pos, false)
      separated = s.at(pos) == ','
      if separated: inc pos
  if ch == '"':
    var stop = pos + 1
    while stop < s.len and s[stop] != '"': stop += (if s[stop] == '\\': 2 else: 1)
    if stop >= s.len: raise newException(Incomplete, "YAML: unexpected end of the stream within a double quoted scalar")
    return (ystr(unquoteDouble(s[pos + 1 ..< stop])), stop + 1)
  if ch == '\'':
    var stop = pos + 1
    while stop < s.len:
      if s[stop] == '\'':
        if s.at(stop + 1) != '\'': break
        inc stop
      inc stop
    if stop >= s.len: raise newException(Incomplete, "YAML: unexpected end of the stream within a single quoted scalar")
    return (ystr(fold(s[pos + 1 ..< stop]).replace(jsre"/''/g", "'")), stop + 1)
  var stop = pos
  while stop < s.len:
    let c = s[stop]
    if c in stops and (c != ':' or stop + 1 >= s.len or s[stop + 1] in {',', '[', ']', '{', '}'} or
                       isJsSpaceAt(s, stop + 1)):
      break
    if c == '#' and stop > pos and isJsSpaceBefore(s, stop):
      let nl = s.find('\n', stop)
      return (scalar(fold(jsTrim(s[pos ..< stop]))), if nl == -1: s.len else: nl)
    inc stop
  (scalar(fold(jsTrim(s[pos ..< stop]))), stop)

proc stripComment(s: string): string =
  var quote = '\0'
  var i = 0
  while i < s.len:
    let c = s[i]
    if quote != '\0':
      if c == '\\' and quote == '"': inc i
      elif c == quote: quote = '\0'
    elif c == '"' or c == '\'':
      quote = c
    elif c == '#' and (i == 0 or s[i - 1] == ' ' or s[i - 1] == '\t'):
      return s[0 ..< i]
    inc i
  s

func leading(line: string): int =
  ## line.length - line.trimStart().length, in bytes
  line.len - jsTrimStart(line).len

proc blockScalar(r: Reader, header: string, parentIndent: int): string =
  let folded = header[0] == '>'
  let chomp = if '-' in header: '-' elif '+' in header: '+' else: '\0'
  let explicit = jsre"/[1-9]/".exec(header)
  var indent = if explicit.found: parentIndent + ord(explicit[0][0]) - ord('0') else: -1
  var output: seq[string]
  while r.i < r.lines.len:
    let line = r.lines[r.i]
    if jsTrim(line) == "":
      output.add ""
      inc r.i
      continue
    let k = leading(line)
    if indent == -1:
      if k <= parentIndent: break
      indent = k
    if k < indent: break
    output.add line[min(indent, line.len) .. ^1]
    inc r.i
  var trailing = 0
  while output.len > 0 and output[^1] == "":
    discard output.pop()
    inc trailing
  var text: string
  if folded:
    for i in 0 ..< output.len:
      let cur = output[i]
      if i > 0:
        let prev = output[i - 1]
        if cur == "": text.add "\n"
        elif prev != "": text.add(if prev.at(0) in {' ', '\t'} or cur.at(0) in {' ', '\t'}: "\n" else: " ")
      text.add cur
  else:
    text = output.join("\n")
  if output.len == 0: return (if chomp == '+': repeat('\n', trailing) else: "")
  if chomp == '-': return text
  if chomp == '+': return text & repeat('\n', trailing + 1)
  text & "\n"

proc inlineValue(r: Reader, rest: string, indent: int): YamlValue =
  let first = rest.at(0)
  if first == '|' or first == '>':
    if jsre"/^[|>][-+0-9]*\s*(?:#.*)?$/".test(rest): return ystr(blockScalar(r, rest, indent))
  if first in {'{', '[', '"', '\''}:
    # The value may continue on later lines. Read them in growing batches until it closes.
    let start = r.i
    var text = rest
    var taken = 0
    var batch = 1
    while true:
      try:
        let (value, stop) = flow(text, 0, "")
        var used = 0
        var k = text.find('\n')
        while k != -1 and k < stop:
          inc used
          k = text.find('\n', k + 1)
        let lineEnd = text.find('\n', stop)
        if jsTrim(stripComment(text[stop ..< (if lineEnd == -1: text.len else: lineEnd)])) != "":
          raise yamlError("YAML: unexpected content after a value")
        r.i = start + used
        return value
      except Incomplete as err:
        if start + taken >= r.lines.len: raise yamlError(err.msg)
        let more = r.lines[start + taken ..< min(start + taken + batch, r.lines.len)]
        text.add "\n" & more.join("\n")
        taken += more.len
        batch *= 2
  var text = jsTrim(stripComment(rest))
  while r.i < r.lines.len:
    let line = r.lines[r.i]
    if jsTrim(line) == "":
      var j = r.i
      while j < r.lines.len and jsTrim(r.lines[j]) == "": inc j
      if j >= r.lines.len or leading(r.lines[j]) <= indent: break
      text.add repeat('\n', j - r.i)
      r.i = j
      continue
    if leading(line) <= indent: break
    let more = jsTrim(stripComment(line))
    text.add((if text.endsWith("\n"): "" else: " ") & more)
    inc r.i
  scalar(text)

proc isSeqLine(line: string): bool = line == "-" or line.startsWith("- ")

proc blockValue(r: Reader, minIndent: int, depth = 0): YamlValue =
  if depth > MAX_DEPTH: raise yamlError("YAML: nesting is too deep")
  r.skipBlank()
  if r.i >= r.lines.len: return ynull()
  let indent = r.indent()
  if indent < minIndent: return ynull()
  let line = r.lines[r.i][indent .. ^1]

  if isSeqLine(line):
    let output = yseq()
    while r.i < r.lines.len:
      r.skipBlank()
      if r.i >= r.lines.len or r.indent() != indent: break
      let cur = r.lines[r.i][indent .. ^1]
      if not isSeqLine(cur): break
      let rest = cur[1 .. ^1]
      let pad = leading(rest) + 1
      let body = jsTrim(stripComment(rest))
      if body == "":
        inc r.i
        output.items.add blockValue(r, indent + 1, depth + 1)
      elif splitKey(body).ok:
        r.lines[r.i] = repeat(' ', indent + pad) & jsTrimStart(rest)
        output.items.add blockValue(r, indent + pad, depth + 1)
      else:
        inc r.i
        output.items.add inlineValue(r, jsTrim(rest), indent)
    return output

  if not splitKey(line).ok:
    inc r.i
    return inlineValue(r, jsTrim(line), indent - 1)

  let output = ymap()
  while r.i < r.lines.len:
    r.skipBlank()
    if r.i >= r.lines.len: break
    let k = r.indent()
    if k < indent: break
    if k > indent: raise yamlError("YAML: bad indentation of a mapping entry")
    let cur = r.lines[r.i][indent .. ^1]
    let km = splitKey(cur)
    if not km.ok: raise yamlError("YAML: can not read a block mapping entry")
    let key = jsStr(flow(km.key, 0, "")[0])
    let rest = cur[km.length .. ^1]
    inc r.i
    if jsTrim(stripComment(rest)) == "":
      r.skipBlank()
      if r.i < r.lines.len:
        let next = r.indent()
        let nextLine = r.lines[r.i][next .. ^1]
        let sq = isSeqLine(nextLine)
        assign(output, key, if next > indent or (sq and next == indent):
                              blockValue(r, if sq: indent else: indent + 1, depth + 1)
                            else: ynull())
      else:
        assign(output, key, ynull())
    else:
      assign(output, key, inlineValue(r, jsTrim(rest), indent))
  output

proc parseYaml*(src: string): YamlValue =
  ## Raises YamlError with js-yaml's message on text it cannot read.
  let trimmed = jsTrim(src)
  if trimmed.at(0) == '{' or trimmed.at(0) == '[':
    try:
      let (value, stop) = flow(trimmed, 0, "")
      if skip(trimmed, stop, false) == trimmed.len: return value
    except Incomplete as err:
      raise yamlError(err.msg)
  let r = newReader(src)
  let value = blockValue(r, 0)
  r.skipBlank()
  if r.i < r.lines.len and jsTrim(r.lines[r.i]) != "...":
    raise yamlError("YAML: end of the stream or a document separator is expected")
  value
