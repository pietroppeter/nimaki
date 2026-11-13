## port-of: src/diagrams/usecase/json.ts
## port-status: draft
##
## Pele calls `JSON.parse` and reports its error message, which is V8's. `jsonParse` below is
## V8's JSON parser (`src/json/json-parser.cc`) as far as its results and messages go: the same
## values, and the same message at the same position for text that is not JSON. Positions in
## messages are UTF-16 code units, as in JavaScript; the text itself is UTF-8 (decision 0011).
import std/[strutils, tables]
import ../../errors
import ../../js
import ../../text/entities
import ../../util/chars

type
  JsonKind* = enum jNull, jBool, jNumber, jString, jArray, jObject
  JsonValue* = ref object
    ## A value `JSON.parse` returns. An object keeps its keys in the order they were first
    ## written; a repeated key takes the last value (`keys` and `values` are parallel).
    case kind*: JsonKind
    of jNull: discard
    of jBool: b*: bool
    of jNumber: n*: float
    of jString: s*: string
    of jArray: items*: seq[JsonValue]
    of jObject:
      keys*: seq[string]
      values*: seq[JsonValue]

  OrderedJson* = object
    value*: JsonValue
    propertyOrder*: Table[string, seq[string]]

  JsSyntaxError = object of CatchableError

  # Thrown with the offset of the first character that is not valid JSON.
  WalkError = object of CatchableError
    offset: int

proc get*(o: JsonValue, key: string): (bool, JsonValue) =
  ## `Object.prototype.hasOwnProperty.call(o, key) ? o[key] : undefined`.
  for i, k in o.keys:
    if k == key: return (true, o.values[i])
  (false, nil)

func isArrayIndex(key: string): bool =
  ## Whether `key` is a canonical array index, which JavaScript lists first, in numeric order.
  if key.len == 0 or key.len > 10: return false
  if key.len > 1 and key[0] == '0': return false
  for c in key:
    if c notin {'0'..'9'}: return false
  parseBiggestInt(key) < 4294967295

proc objectKeys*(o: JsonValue): seq[string] =
  ## `Object.keys(o)`: integer-like keys first, ascending, then the others as written.
  var indices: seq[(BiggestInt, string)]
  for k in o.keys:
    if isArrayIndex(k): indices.add (parseBiggestInt(k), k)
  for a in 1 ..< indices.len:
    var b = a
    while b > 0 and indices[b - 1][0] > indices[b][0]:
      swap(indices[b - 1], indices[b])
      dec b
  for (_, k) in indices: result.add k
  for k in o.keys:
    if not isArrayIndex(k): result.add k

# ---------------------------------------------------------------------------------------------
# Strings: a `\u` escape is one UTF-16 code unit, and two of them can make one character.

proc addUnit(output: var string, high: var int, unit: int) =
  ## Appends a UTF-16 code unit, pairing surrogates. A lone surrogate is written as its own
  ## three bytes (WTF-8), as nimaki keeps no other form of it.
  proc raw(output: var string, u: int) =
    output.add char(0xE0 or (u shr 12))
    output.add char(0x80 or ((u shr 6) and 0x3F))
    output.add char(0x80 or (u and 0x3F))
  if high != -1:
    if unit >= 0xDC00 and unit <= 0xDFFF:
      output.add fromCodePoint(0x10000 + ((high - 0xD800) shl 10) + (unit - 0xDC00))
      high = -1
      return
    raw(output, high)
    high = -1
  if unit >= 0xD800 and unit <= 0xDBFF: high = unit
  elif unit >= 0xDC00 and unit <= 0xDFFF: raw(output, unit)
  else: output.add fromCodePoint(unit)

proc flush(output: var string, high: var int) =
  if high != -1:
    output.add char(0xE0 or (high shr 12))
    output.add char(0x80 or ((high shr 6) and 0x3F))
    output.add char(0x80 or (high and 0x3F))
    high = -1

func hexValue(c: int): int =
  if c >= 48 and c <= 57: c - 48
  elif c >= 65 and c <= 70: c - 55
  elif c >= 97 and c <= 102: c - 87
  else: -1

# ---------------------------------------------------------------------------------------------
# JSON.parse, as V8 does it

const
  MAX_CONTEXT = 10
  MIN_LENGTH_FOR_CONTEXT = MAX_CONTEXT * 2 + 1

type Token = enum tEOS, tString, tNumber, tLBrace, tRBrace, tLBrack, tRBrack, tTrue, tFalse, tNull,
                  tColon, tComma, tWhitespace, tIllegal

func tokenOf(c: int): Token =
  case c
  of -1: tEOS
  of 34: tString
  of 45, 48 .. 57: tNumber
  of 123: tLBrace
  of 125: tRBrace
  of 91: tLBrack
  of 93: tRBrack
  of 116: tTrue
  of 102: tFalse
  of 110: tNull
  of 58: tColon
  of 44: tComma
  of 32, 9, 10, 13: tWhitespace
  else: tIllegal

proc jsonParse*(text: string): JsonValue =
  ## `JSON.parse(text)` with V8's messages. Raises JsSyntaxError.
  var at = 0
  let n = text.len
  template cur(): int = (if at < n: ord(text[at]) else: -1)

  proc report(message: string) =
    # V8 adds where it stopped: the position in code units, and the line and column.
    let pos = utf16Len(text, 0, min(at, n))
    var line = 1
    var lastBreak = 0
    var k = 0
    while k < at:
      if text[k] == '\r' and k < at - 1 and text[k + 1] == '\n': inc k
      if text[k] == '\r' or text[k] == '\n':
        inc line
        lastBreak = k + 1
      inc k
    let column = 1 + utf16Len(text, lastBreak, min(at, n))
    raise newException(JsSyntaxError, message & " in JSON at position " & $pos & " (line " & $line &
                       " column " & $column & ")")

  proc unexpected(token: Token) =
    case token
    of tEOS: raise newException(JsSyntaxError, "Unexpected end of JSON input")
    of tNumber: report("Unexpected number")
    of tString: report("Unexpected string")
    else:
      # The character as one UTF-16 code unit, and the text around it.
      let (cp, size) = codePointAt(text, at)
      var ch = text[at ..< at + size]
      if cp >= 0x10000:
        var s = ""
        var high = -1
        addUnit(s, high, 0xD800 + ((cp - 0x10000) shr 10))
        flush(s, high)
        ch = s
      let length = utf16Len(text)
      let pos = utf16Len(text, 0, at)
      if length <= MIN_LENGTH_FOR_CONTEXT:
        raise newException(JsSyntaxError, "Unexpected token '" & ch & "', \"" & text & "\" is not valid JSON")
      var first = 0
      var last = length
      var before = ""
      var after = ""
      if pos < MAX_CONTEXT:
        last = pos + MAX_CONTEXT
        after = "..."
      elif pos < length - MAX_CONTEXT:
        first = pos - MAX_CONTEXT
        last = pos + MAX_CONTEXT
        before = "..."
        after = "..."
      else:
        first = pos - MAX_CONTEXT
        before = "..."
      let a = unitOffset(text, 0, first)
      let b = unitOffset(text, 0, last)
      raise newException(JsSyntaxError, "Unexpected token '" & ch & "', " & before & "\"" &
                         text[a ..< min(b, n)] & "\"" & after & " is not valid JSON")

  proc unexpectedCharacter() = unexpected(tokenOf(cur()))

  proc skipSpace() =
    while at < n and text[at] in {' ', '\t', '\n', '\r'}: inc at

  proc peek(): Token =
    skipSpace()
    tokenOf(cur())

  proc str(): string =
    # The cursor is on the opening quote.
    inc at
    var high = -1
    while true:
      if at >= n: report("Unterminated string")
      let c = ord(text[at])
      if c == 34:
        inc at
        flush(result, high)
        return
      if c < 0x20: report("Bad control character in string literal")
      if c != 92:
        flush(result, high)
        result.add text[at]
        inc at
        continue
      inc at
      let e = cur()
      case e
      of 34, 92, 47:
        addUnit(result, high, e)
      of 98: addUnit(result, high, 8)
      of 102: addUnit(result, high, 12)
      of 110: addUnit(result, high, 10)
      of 114: addUnit(result, high, 13)
      of 116: addUnit(result, high, 9)
      of 117:
        var value = 0
        for i in 0 ..< 4:
          inc at
          let digit = hexValue(cur())
          if digit < 0: report("Bad Unicode escape")
          value = value * 16 + digit
        addUnit(result, high, value)
      of -1: unexpected(tEOS)
      else: report("Bad escaped character")
      inc at

  proc number(): float =
    let start = at
    if cur() == 45: inc at
    if cur() == 48:
      inc at
      if isDigit(cur()): unexpected(tNumber)
    elif not isDigit(cur()): report("No number after minus sign")
    else:
      while isDigit(cur()): inc at
    if cur() == 46:
      inc at
      if not isDigit(cur()): report("Unterminated fractional number")
      while isDigit(cur()): inc at
    if cur() == 101 or cur() == 69:
      inc at
      if cur() == 45 or cur() == 43: inc at
      if not isDigit(cur()): report("Exponent part is missing a number")
      while isDigit(cur()): inc at
    jsNumber(text[start ..< at])

  proc literal(word: string) =
    inc at
    for k in 1 ..< word.len:
      if at >= n: unexpected(tEOS)
      if text[at] != word[k]: unexpectedCharacter()
      inc at

  proc expectNext(token: Token, message: string) =
    if peek() != token: report(message)

  type Frame = object
    value: JsonValue
    key: string

  var stack: seq[Frame]
  var value: JsonValue
  while true:
    # A value.
    let token = peek()
    case token
    of tString: value = JsonValue(kind: jString, s: str())
    of tNumber: value = JsonValue(kind: jNumber, n: number())
    of tTrue:
      literal("true")
      value = JsonValue(kind: jBool, b: true)
    of tFalse:
      literal("false")
      value = JsonValue(kind: jBool, b: false)
    of tNull:
      literal("null")
      value = JsonValue(kind: jNull)
    of tLBrace:
      inc at
      if peek() == tRBrace:
        inc at
        value = JsonValue(kind: jObject)
      else:
        expectNext(tString, "Expected property name or '}'")
        let key = str()
        expectNext(tColon, "Expected ':' after property name")
        inc at
        stack.add Frame(value: JsonValue(kind: jObject), key: key)
        continue
    of tLBrack:
      inc at
      if peek() == tRBrack:
        inc at
        value = JsonValue(kind: jArray)
      else:
        stack.add Frame(value: JsonValue(kind: jArray))
        continue
    else:
      unexpected(token)

    # Where the value goes, and what comes after it.
    while true:
      if stack.len == 0:
        if peek() != tEOS: report("Unexpected non-whitespace character after JSON")
        return value
      let frame = addr stack[^1]
      let container = frame.value
      if container.kind == jObject:
        var found = false
        for i, k in container.keys:
          if k == frame.key:
            container.values[i] = value
            found = true
            break
        if not found:
          container.keys.add frame.key
          container.values.add value
        let next = peek()
        if next == tComma:
          inc at
          expectNext(tString, "Expected double-quoted property name")
          frame.key = str()
          expectNext(tColon, "Expected ':' after property name")
          inc at
          break
        if next != tRBrace: report("Expected ',' or '}' after property value")
        inc at
      else:
        container.items.add value
        let next = peek()
        if next == tComma:
          inc at
          break
        if next != tRBrack: report("Expected ',' or ']' after array element")
        inc at
      value = container
      discard stack.pop()

# ---------------------------------------------------------------------------------------------
# The port of json.ts

type
  Frame = object
    isObject: bool
    pointer: string
    keys: seq[string]
    # For each key read so far, the stretch of `created` its value added.
    ranges: Table[string, (int, int)]
    key: string
    origin: int
    index: int

  State = enum sValue, sKey, sAfter

proc walkError(text: string, offset: int): ref WalkError =
  (ref WalkError)(msg: "Invalid JSON token", offset: utf16Len(text, 0, min(offset, text.len)))

proc escapePointer(key: string): string = key.replace("~", "~0").replace("/", "~1")

proc propertyOrder(text: string): Table[string, seq[string]] =
  ## Walks JSON text that JSON.parse has accepted, to recover the order its keys were written in,
  ## which JSON.parse loses for integer-like keys. On text JSON.parse rejected it finds where.
  ## Nesting is kept on a stack of its own, so depth is limited by memory and not by the call stack.
  var order = initTable[string, seq[string]]()
  var created: seq[string]
  var stack: seq[Frame]
  let n = text.len
  var at = 0
  var pointer = ""
  var state = sValue
  template cc(k: int): int = (if k < n: ord(text[k]) else: -1)

  proc skip() =
    while at < n:
      let c = ord(text[at])
      if c != 32 and c != 9 and c != 10 and c != 13: return
      inc at

  proc readString(decode: bool): string =
    inc at
    var high = -1
    while at < n:
      let start = at
      let ch = text[at]
      inc at
      if ch == '"':
        flush(result, high)
        return
      if ord(ch) < 0x20: raise walkError(text, start)
      if ch != '\\':
        if decode:
          flush(result, high)
          result.add ch
        continue
      let escapeAt = at
      let e = cc(at)
      inc at
      var unit: int
      case e
      of 34, 92, 47: unit = e
      of 98: unit = 8
      of 102: unit = 12
      of 110: unit = 10
      of 114: unit = 13
      of 116: unit = 9
      of 117:
        unit = 0
        for k in 0 ..< 4:
          let d = hexValue(cc(at + k))
          if d < 0: raise walkError(text, at)
          unit = unit * 16 + d
        at += 4
      else: raise walkError(text, escapeAt)
      if decode: addUnit(result, high, unit)
    raise walkError(text, at)

  proc literal(word: string) =
    for k in 0 ..< word.len:
      if cc(at + k) != ord(word[k]): raise walkError(text, at + k)
    at += word.len

  proc number() =
    if cc(at) == 45: inc at
    if cc(at) == 48: inc at
    elif isDigit(cc(at)):
      while isDigit(cc(at)): inc at
    else: raise walkError(text, at)
    if cc(at) == 46:
      inc at
      if not isDigit(cc(at)): raise walkError(text, at)
      while isDigit(cc(at)): inc at
    if (cc(at) or 32) == 101:
      inc at
      if cc(at) == 43 or cc(at) == 45: inc at
      if not isDigit(cc(at)): raise walkError(text, at)
      while isDigit(cc(at)): inc at

  skip()
  while true:
    if state == sValue:
      skip()
      let c = cc(at)
      state = sAfter
      if c == 123:
        inc at
        order[pointer] = @[]
        created.add pointer
        skip()
        if cc(at) == 125: inc at
        else:
          stack.add Frame(isObject: true, pointer: pointer)
          state = sKey
      elif c == 91:
        inc at
        skip()
        if cc(at) == 93: inc at
        else:
          stack.add Frame(isObject: false, pointer: pointer)
          pointer.add "/0"
          state = sValue
      elif c == 34: discard readString(false)
      elif c == 116: literal("true")
      elif c == 102: literal("false")
      elif c == 110: literal("null")
      elif c == 45 or isDigit(c): number()
      else: raise walkError(text, at)
    elif state == sKey:
      let frame = addr stack[^1]
      if cc(at) != 34: raise walkError(text, at)
      let key = readString(true)
      # A repeated key keeps its first place in the order and takes the nested order of its last value.
      if key notin frame.ranges: frame.keys.add key
      else:
        let (a, b) = frame.ranges[key]
        for k in a ..< b: order.del created[k]
      frame.key = key
      frame.origin = created.len
      skip()
      if cc(at) != 58: raise walkError(text, at)
      inc at
      pointer = frame.pointer & "/" & escapePointer(key)
      state = sValue
    else:
      if stack.len == 0: break
      let frame = addr stack[^1]
      if frame.isObject:
        frame.ranges[frame.key] = (frame.origin, created.len)
        # The keys are kept on the frame; the table holds them once the object is closed.
        if frame.pointer in order: order[frame.pointer] = frame.keys
      else: inc frame.index
      skip()
      let c = cc(at)
      if c == (if frame.isObject: 125 else: 93):
        inc at
        discard stack.pop()
      elif c != 44: raise walkError(text, at)
      else:
        inc at
        skip()
        pointer = frame.pointer & "/" & $frame.index
        state = if frame.isObject: sKey else: sValue
  skip()
  if at != n: raise walkError(text, at)
  order

proc locationAt(text: string, offset, line, column: int): (int, int) =
  ## `offset` is in UTF-16 code units, and so is the column.
  var line = line
  var column = column
  let stop = unitOffset(text, 0, min(max(offset, 0), utf16Len(text)))
  var i = 0
  while i < stop and i < text.len:
    let c = ord(text[i])
    if c == 13:
      inc line
      column = 1
    elif c == 10:
      if i == 0 or ord(text[i - 1]) != 13:
        inc line
        column = 1
    else:
      let (cp, size) = codePointAt(text, i)
      column += (if cp >= 0x10000: 2 else: 1)
      i += size
      continue
    inc i
  (line, column)

proc numberAfter(message, prefix: string, start: int): (int, int, int) =
  ## A match of /\b<prefix>(\d+)\b/ from `start`: (where it starts, the number, where it ends),
  ## or (-1, 0, 0).
  var at = message.find(prefix, start)
  while at != -1:
    let boundary = at == 0 or not isWordChar(message[at - 1])
    var k = at + prefix.len
    while k < message.len and message[k] in {'0'..'9'}: inc k
    # \d+ backtracks, but a shorter run still ends next to a digit, so only the whole run can end at \b.
    if boundary and k > at + prefix.len and (k == message.len or not isWordChar(message[k])):
      return (at, parseInt(message[at + prefix.len ..< k]), k)
    at = message.find(prefix, at + 1)
  (-1, 0, 0)

proc locationFromMessage(message, text: string, line, column: int): (bool, (int, int)) =
  ## Engines word JSON.parse errors differently: some give an offset, some a line and column.
  let position = numberAfter(message, "position ", 0)
  if position[0] != -1: return (true, locationAt(text, position[1], line, column))
  var at = message.find("line ")
  while at != -1:
    let first = numberAfter(message, "line ", at)
    if first[0] == -1: break
    if message.continuesWith(" column ", first[2]):
      let second = numberAfter(message, "column ", first[2] + 1)
      if second[0] == first[2] + 1:
        let localLine = first[1]
        let localColumn = second[1]
        return (true, (line + localLine - 1, if localLine == 1: column + localColumn - 1 else: localColumn))
    at = message.find("line ", first[0] + 1)
  let lower = message.toLowerAscii
  if "unexpected end" in lower or "end of json input" in lower:
    return (true, locationAt(text, utf16Len(text), line, column))
  (false, (0, 0))

proc jsonError(message: string, line, column: int): ref PeleError =
  newPeleError(message & " (line " & $line & ", column " & $column & ")", "syntax",
               ErrorInfo(diagramType: "usecase", line: line, column: column))

proc parseOrderedJson*(text: string, origin: proc (): (int, int)): OrderedJson =
  ## Parses the body of a `json` node. `origin` gives the line and column the text starts at in
  ## the diagram.
  var parsed: JsonValue
  try:
    parsed = jsonParse(text)
  except JsSyntaxError as error:
    var message = error.msg
    # Reparse restored entity codes so error messages and positions match the source.
    let shown = writtenCodes(text)
    if shown != text:
      try:
        discard jsonParse(shown)
      except JsSyntaxError as again:
        message = again.msg
    let (line, column) = origin()
    var (found, location) = locationFromMessage(message, shown, line, column)
    if not found:
      var offset = 0
      try:
        discard propertyOrder(shown)
      except WalkError as walk:
        offset = walk.offset
      location = locationAt(shown, offset, line, column)
    raise jsonError("Invalid JSON: " & message, location[0], location[1])
  if parsed.kind != jObject:
    let (line, column) = origin()
    raise jsonError("JSON value must have an object root", line, column)
  OrderedJson(value: parsed, propertyOrder: propertyOrder(text))
