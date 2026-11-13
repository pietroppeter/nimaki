## JavaScript's numbers and strings, in Nim. Not a port of a file of Pele: the small set of
## JavaScript behaviours Pele relies on without saying so, written once so every ported file
## gets them the same way (the porting guide lists when to use each).
##
## Strings stay UTF-8 (decision 0011). Where Pele counts or reads UTF-16 code units
## (`length`, `charCodeAt`), these helpers count and read them from the UTF-8 bytes.
import std/[math, strutils, unicode, json]

# ---------------------------------------------------------------------------------------------
# Numbers

func jsRound*(x: float): float =
  ## `Math.round`: a tie goes up, toward +∞ (`Math.round(-2.5)` is -2).
  if x.isNaN or x.classify in {fcInf, fcNegInf}: return x
  let f = floor(x)
  if x - f >= 0.5: f + 1 else: f

func shortestDigits(x: float): tuple[digits: string, point: int] =
  ## The shortest decimal digits that read back as `x` (x > 0, finite), and where the decimal
  ## point goes: x = 0.digits × 10^point. Nim's `$` already finds the shortest digits.
  let s = $x
  var mant = s
  var exp = 0
  let e = s.find('e')
  if e >= 0:
    mant = s[0 ..< e]
    exp = parseInt(s[e + 1 .. ^1])
  var intPart = mant
  var frac = ""
  let dot = mant.find('.')
  if dot >= 0:
    intPart = mant[0 ..< dot]
    frac = mant[dot + 1 .. ^1]
  var digits = intPart & frac
  var point = intPart.len + exp
  var lead = 0
  while lead < digits.len - 1 and digits[lead] == '0':
    inc lead
  digits = digits[lead .. ^1]
  point -= lead
  var last = digits.len
  while last > 1 and digits[last - 1] == '0':
    dec last
  digits.setLen last
  (digits, point)

func jsString*(x: float): string =
  ## ECMAScript's Number::toString: `String(x)`, `${x}`. `-0` is "0"; exponent form from 1e21
  ## and below 1e-6.
  if x.isNaN: return "NaN"
  if x == Inf: return "Infinity"
  if x == -Inf: return "-Infinity"
  if x == 0: return "0"
  if x < 0: return "-" & jsString(-x)
  let (digits, n) = shortestDigits(x)
  let k = digits.len
  if k <= n and n <= 21:
    result = digits & repeat('0', n - k)
  elif 0 < n and n <= 21:
    result = digits[0 ..< n] & "." & digits[n .. ^1]
  elif -6 < n and n <= 0:
    result = "0." & repeat('0', -n) & digits
  else:
    let e = n - 1
    result = digits[0 .. 0]
    if k > 1: result.add "." & digits[1 .. ^1]
    result.add "e" & (if e >= 0: "+" else: "-") & $abs(e)

func jsString*(x: int): string = jsString(float(x))

func exactDecimal(x: float): string =
  ## The exact decimal value of a finite double x >= 0, as "int.frac" (frac at least 101
  ## digits long, zero padded): x = m × 2^e is m × 5^-e / 10^-e when e < 0.
  var (m, e) = (x, 0)
  if x != 0:
    let fr = frexp(x)
    m = fr.frac
    e = fr.exp
  # make m an integer: m × 2^53, e - 53
  var mant = uint64(m * 9007199254740992.0)
  e -= 53
  while mant != 0 and (mant and 1) == 0 and e < 0:
    mant = mant shr 1
    inc e
  var digits: seq[int]   # little-endian decimal digits
  var t = mant
  if t == 0: digits.add 0
  while t > 0:
    digits.add int(t mod 10)
    t = t div 10
  proc mul(d: var seq[int], k: int) =
    var carry = 0
    for i in 0 ..< d.len:
      let v = d[i] * k + carry
      d[i] = v mod 10
      carry = v div 10
    while carry > 0:
      d.add carry mod 10
      carry = carry div 10
  var point = 0   # digits after the decimal point
  if e >= 0:
    for _ in 0 ..< e: mul(digits, 2)
  else:
    for _ in 0 ..< -e: mul(digits, 5)
    point = -e
  while digits.len <= point: digits.add 0
  var s = ""
  for i in countdown(digits.high, point): s.add char(ord('0') + digits[i])
  s.add '.'
  for i in countdown(point - 1, 0): s.add char(ord('0') + digits[i])
  while s.len - s.find('.') - 1 < 101: s.add '0'
  s

func toFixed*(x: float, fractionDigits: int): string =
  ## `x.toFixed(n)`: the exact decimal value of the double, rounded at n digits with a tie up
  ## (away from zero, as JavaScript does on the magnitude).
  if x.isNaN: return "NaN"
  if abs(x) >= 1e21: return jsString(x)
  let negative = x < 0
  let exact = exactDecimal(abs(x))
  let dot = exact.find('.')
  var intPart = exact[0 ..< dot]
  var frac = exact[dot + 1 .. ^1]
  var kept = intPart & frac[0 ..< fractionDigits]
  let roundUp = frac[fractionDigits] >= '5'
  if roundUp:
    var i = kept.high
    while i >= 0:
      if kept[i] == '9':
        kept[i] = '0'
        dec i
      else:
        kept[i] = char(ord(kept[i]) + 1)
        break
    if i < 0: kept = "1" & kept
  let intLen = kept.len - fractionDigits
  result = kept[0 ..< intLen]
  if fractionDigits > 0: result.add "." & kept[intLen .. ^1]
  if negative: result = "-" & result

func jsNumber*(s: string): float =
  ## `Number(s)` for the decimal numbers the lexers accept (`-?digits(.digits)?`).
  parseFloat(s)

func significant(x: float, p: int): tuple[digits: string, e: int] =
  ## The exact decimal value of x > 0 (finite) rounded to p significant digits, a tie up, as
  ## toPrecision and toExponential round it: x ≈ d.ddd × 10^e.
  let exact = exactDecimal(x)
  let dot = exact.find('.')
  let all = exact[0 ..< dot] & exact[dot + 1 .. ^1]
  var first = 0
  while first < all.len and all[first] == '0': inc first
  var e = dot - 1 - first
  var kept = all[first ..< min(all.len, first + p)]
  while kept.len < p: kept.add '0'
  let next = if first + p < all.len: all[first + p] else: '0'
  if next >= '5':
    var i = kept.high
    while i >= 0:
      if kept[i] == '9':
        kept[i] = '0'
        dec i
      else:
        kept[i] = char(ord(kept[i]) + 1)
        break
    if i < 0:
      kept = "1" & kept[0 ..< kept.high]
      inc e
  (kept, e)

func expForm(digits: string, e: int): string =
  result = digits[0 .. 0]
  if digits.len > 1: result.add "." & digits[1 .. ^1]
  result.add "e" & (if e >= 0: "+" else: "-") & $abs(e)

func toExponential*(x: float, fractionDigits: int): string =
  ## `x.toExponential(f)`.
  if x.isNaN: return "NaN"
  if x == Inf: return "Infinity"
  if x == -Inf: return "-Infinity"
  if x < 0: return "-" & toExponential(-x, fractionDigits)
  if x == 0: return expForm(repeat('0', fractionDigits + 1), 0)
  let (digits, e) = significant(x, fractionDigits + 1)
  expForm(digits, e)

func toPrecision*(x: float, precision: int): string =
  ## `x.toPrecision(p)`.
  if x.isNaN: return "NaN"
  if x == Inf: return "Infinity"
  if x == -Inf: return "-Infinity"
  if x < 0: return "-" & toPrecision(-x, precision)
  var digits = repeat('0', precision)
  var e = 0
  if x != 0: (digits, e) = significant(x, precision)
  if e < -6 or e >= precision: return expForm(digits, e)
  if e == precision - 1: return digits
  if e >= 0: return digits[0 .. e] & "." & digits[e + 1 .. ^1]
  "0." & repeat('0', -(e + 1)) & digits

func jsTrim*(s: string): string
func jsTrimStart*(s: string): string

func jsParseFloat*(raw: string): float =
  ## `parseFloat(s)`: the longest prefix, after JavaScript's whitespace, that is a decimal number
  ## or `Infinity` with a sign; NaN when there is none.
  let s = jsTrimStart(raw)
  var i = 0
  if i < s.len and s[i] in {'+', '-'}: inc i
  if s.continuesWith("Infinity", i): return (if s.len > 0 and s[0] == '-': -Inf else: Inf)
  let digits0 = i
  while i < s.len and s[i] in Digits: inc i
  if i < s.len and s[i] == '.':
    inc i
    while i < s.len and s[i] in Digits: inc i
  if i == digits0 or (i == digits0 + 1 and s[digits0] == '.'): return NaN
  if i < s.len and s[i] in {'e', 'E'}:
    var j = i + 1
    if j < s.len and s[j] in {'+', '-'}: inc j
    if j < s.len and s[j] in Digits:
      while j < s.len and s[j] in Digits: inc j
      i = j
  var t = s[0 ..< i]
  t = t.replace(".e", ".0e").replace(".E", ".0E")
  if t.endsWith("."): t.add "0"
  if t.startsWith("."): t = "0" & t
  elif t.startsWith("-.") or t.startsWith("+."): t = t[0] & "0" & t[1 .. ^1]
  parseFloat(t)

func jsToNumber*(raw: string): float =
  ## `Number(s)` for any string (ECMAScript's StringToNumber): JavaScript's whitespace around it
  ## is dropped, "" is 0, `Infinity` with a sign, `0x`, `0o` and `0b` without one, and a decimal
  ## number with an optional sign and exponent; anything else is NaN. A prefixed number past
  ## 2^53 is summed digit by digit, which can round differently from JavaScript.
  let s = jsTrim(raw)
  if s == "": return 0
  case s
  of "Infinity", "+Infinity": return Inf
  of "-Infinity": return -Inf
  else: discard
  if s.len > 2 and s[0] == '0' and s[1] in {'x', 'X', 'o', 'O', 'b', 'B'}:
    let (base, digits) = case s[1]
      of 'x', 'X': (16.0, HexDigits)
      of 'o', 'O': (8.0, {'0'..'7'})
      else: (2.0, {'0', '1'})
    var v = 0.0
    for c in s[2 .. ^1]:
      if c notin digits: return NaN
      v = v * base + float(if c in Digits: ord(c) - ord('0') else: ord(c.toLowerAscii) - ord('a') + 10)
    return v
  var i = 0
  if s[i] in {'+', '-'}: inc i
  let first = i
  while i < s.len and s[i] in Digits: inc i
  let intDigits = i - first
  var fracDigits = 0
  if i < s.len and s[i] == '.':
    inc i
    let f = i
    while i < s.len and s[i] in Digits: inc i
    fracDigits = i - f
  if intDigits + fracDigits == 0: return NaN
  if i < s.len and s[i] in {'e', 'E'}:
    inc i
    if i < s.len and s[i] in {'+', '-'}: inc i
    let e = i
    while i < s.len and s[i] in Digits: inc i
    if i == e: return NaN
  if i != s.len: return NaN
  var t = s
  if t[0] == '+': t = t[1 .. ^1]
  t = t.replace(".e", ".0e").replace(".E", ".0E")
  if t.endsWith("."): t.add '0'
  if t.startsWith("."): t = "0" & t
  elif t.startsWith("-."): t = "-0" & t[1 .. ^1]
  parseFloat(t)

func jsMax*(a, b: float): float =
  ## `Math.max`: NaN when either is NaN.
  if a.isNaN or b.isNaN: NaN else: max(a, b)

func jsMin*(a, b: float): float =
  if a.isNaN or b.isNaN: NaN else: min(a, b)

# ---------------------------------------------------------------------------------------------
# Strings: UTF-16 code units read from UTF-8

func codePointAt*(s: string, i: int): tuple[rune: int, size: int] =
  ## The code point that starts at byte `i`, and its length in bytes. A byte that does not
  ## start a valid sequence reads as U+FFFD, one byte long (as TextDecoder does).
  let b = ord(s[i])
  if b < 0x80: return (b, 1)
  var n, cp, least: int
  if b >= 0xC2 and b <= 0xDF: (n, cp, least) = (2, b and 0x1F, 0x80)
  elif b >= 0xE0 and b <= 0xEF: (n, cp, least) = (3, b and 0x0F, 0x800)
  elif b >= 0xF0 and b <= 0xF4: (n, cp, least) = (4, b and 0x07, 0x10000)
  else: return (0xFFFD, 1)
  if i + n > s.len: return (0xFFFD, 1)
  for k in 1 ..< n:
    let c = ord(s[i + k])
    if (c and 0xC0) != 0x80: return (0xFFFD, 1)
    cp = (cp shl 6) or (c and 0x3F)
  if cp < least or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF): return (0xFFFD, 1)
  (cp, n)

iterator codeUnits*(s: string): int =
  ## The UTF-16 code units of `s`, as `charCodeAt` reads them one by one.
  var i = 0
  while i < s.len:
    let (cp, size) = codePointAt(s, i)
    if cp >= 0x10000:
      let v = cp - 0x10000
      yield 0xD800 + (v shr 10)
      yield 0xDC00 + (v and 0x3FF)
    else:
      yield cp
    i += size

func jsCompare*(a, b: string): int =
  ## How JavaScript orders two strings (`sort()` with no comparator, `<`): by UTF-16 code units,
  ## which differs from the byte order of UTF-8 for characters from U+E000 against those past
  ## U+FFFF.
  var x, y: seq[int]
  for c in codeUnits(a): x.add c
  for c in codeUnits(b): y.add c
  for i in 0 ..< min(x.len, y.len):
    if x[i] != y[i]: return x[i] - y[i]
  x.len - y.len

func substringFrom*(s: string, units: int): string =
  ## `s.substring(units)`: drops `units` UTF-16 code units from the start (a character past
  ## U+FFFF counts two).
  var i = 0
  var k = 0
  while k < units and i < s.len:
    let (cp, size) = codePointAt(s, i)
    k += (if cp >= 0x10000: 2 else: 1)
    i += size
  s[i .. ^1]

func utf16Len*(s: string): int =
  ## `s.length`.
  for _ in codeUnits(s): inc result

func utf16Len*(s: string, first, last: int): int =
  ## The length in UTF-16 code units of the bytes `first ..< last` of `s`.
  var i = first
  while i < last:
    let (cp, size) = codePointAt(s, i)
    result += (if cp >= 0x10000: 2 else: 1)
    i += size

func fromCodePoint*(cp: int): string =
  ## `String.fromCodePoint`.
  $Rune(cp)

func isJsSpace*(c: int): bool =
  ## `\s` of a JavaScript regular expression, on a code point.
  if c < 128: return c == 32 or (c >= 9 and c <= 13)
  c == 0xa0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200a) or c == 0x2028 or c == 0x2029 or
    c == 0x202f or c == 0x205f or c == 0x3000 or c == 0xfeff

func isJsSpaceAt*(s: string, i: int): bool =
  ## Whether a `\s` starts at byte `i` (false past the end).
  i >= 0 and i < s.len and isJsSpace(codePointAt(s, i).rune)

func spaceLenAt*(s: string, i: int): int =
  ## The bytes of the `\s` at byte `i`, or 0.
  if i < s.len:
    let (cp, size) = codePointAt(s, i)
    if isJsSpace(cp): return size
  0

func jsTrimStart*(s: string): string =
  ## `trimStart()`: removes `\s` (and line terminators, which `\s` holds) from the start.
  var i = 0
  while i < s.len:
    let n = spaceLenAt(s, i)
    if n == 0: break
    i += n
  s[i .. ^1]

func jsTrimEnd*(s: string): string =
  ## `trimEnd()`.
  var stop = s.len
  while stop > 0:
    # step back one code point
    var k = stop - 1
    while k > 0 and (ord(s[k]) and 0xC0) == 0x80 and stop - k < 4: dec k
    let (cp, size) = codePointAt(s, k)
    if k + size != stop or not isJsSpace(cp): break
    stop = k
  s[0 ..< stop]

func jsTrim*(s: string): string = jsTrimStart(jsTrimEnd(s))

func prevRuneStart*(s: string, i: int): int =
  ## The byte where the code point that ends at byte `i` starts (i > 0).
  var k = i - 1
  while k > 0 and (ord(s[k]) and 0xC0) == 0x80 and i - k < 4: dec k
  if k + codePointAt(s, k).size == i: k else: i - 1

func isJsSpaceBefore*(s: string, i: int): bool =
  ## Whether the character before byte `i` is a `\s`.
  i > 0 and isJsSpace(codePointAt(s, prevRuneStart(s, i)).rune)

func isWordChar*(c: char): bool =
  ## `\w`.
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func unitOffset*(s: string, first, units: int): int =
  ## The byte offset `units` UTF-16 code units after byte `first` of `s`: the inverse of
  ## `utf16Len(s, first, last)`. An index inside a surrogate pair rounds up to the next character.
  result = first
  var k = 0
  while k < units and result < s.len:
    let (cp, size) = codePointAt(s, result)
    k += (if cp >= 0x10000: 2 else: 1)
    result += size
  if k < units: result += units - k

func replaceFirst*(s, sub, by: string): string =
  ## `s.replace(sub, by)` with a string pattern: only the first occurrence.
  let i = s.find(sub)
  if i < 0: s else: s[0 ..< i] & by & s[i + sub.len .. ^1]

# ---------------------------------------------------------------------------------------------
# JSON.parse

type JsSyntaxError* = object of CatchableError
  ## What `JSON.parse` throws on text that is not JSON.

proc jsonParse*(text: string): JsonNode =
  ## `JSON.parse(text)`: strict JSON (ECMA-404), unlike `std/json`'s `parseJson`, which also reads
  ## comments, trailing commas, leading zeros, `1.` and unknown escapes. Containers are kept on an
  ## explicit stack, so any depth parses. A lone surrogate (`"\ud800"`) is kept as its three bytes.
  ## Numbers are floats.
  let n = text.len
  var i = 0
  proc fail() {.noreturn.} =
    raise newException(JsSyntaxError, "Unexpected token in JSON at position " & $i)
  proc ws() =
    while i < n and text[i] in {' ', '\t', '\n', '\r'}: inc i
  proc hex4(): int =
    if i + 4 > n: fail()
    for k in 0 ..< 4:
      let c = text[i + k]
      let d = if c in {'0'..'9'}: ord(c) - 48 elif c in {'a'..'f'}: ord(c) - 87
              elif c in {'A'..'F'}: ord(c) - 55 else: -1
      if d < 0: fail()
      result = result * 16 + d
    i += 4
  proc str(): string =
    inc i # the opening quote
    while true:
      if i >= n: fail()
      let c = text[i]
      if c == '"':
        inc i
        return
      if ord(c) < 0x20: fail()
      if c != '\\':
        result.add c
        inc i
        continue
      inc i
      if i >= n: fail()
      let e = text[i]
      inc i
      case e
      of '"': result.add '"'
      of '\\': result.add '\\'
      of '/': result.add '/'
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'u':
        var cp = hex4()
        if cp >= 0xD800 and cp <= 0xDBFF and i + 6 <= n and text[i] == '\\' and text[i + 1] == 'u':
          let save = i
          i += 2
          let lo = hex4()
          if lo >= 0xDC00 and lo <= 0xDFFF: cp = 0x10000 + ((cp - 0xD800) shl 10) + (lo - 0xDC00)
          else: i = save
        result.add $Rune(cp)
      else: fail()
  proc number(): JsonNode =
    let start = i
    if i < n and text[i] == '-': inc i
    if i < n and text[i] == '0': inc i
    elif i < n and text[i] in {'1'..'9'}:
      while i < n and text[i] in {'0'..'9'}: inc i
    else: fail()
    if i < n and text[i] == '.':
      inc i
      if not (i < n and text[i] in {'0'..'9'}): fail()
      while i < n and text[i] in {'0'..'9'}: inc i
    if i < n and text[i] in {'e', 'E'}:
      inc i
      if i < n and text[i] in {'+', '-'}: inc i
      if not (i < n and text[i] in {'0'..'9'}): fail()
      while i < n and text[i] in {'0'..'9'}: inc i
    newJFloat(parseFloat(text[start ..< i]))
  proc literal(word: string, node: JsonNode): JsonNode =
    if not text.continuesWith(word, i): fail()
    i += word.len
    node

  var stack: seq[JsonNode]
  var keys: seq[string]
  while true:
    ws()
    if i >= n: fail()
    var value: JsonNode
    case text[i]
    of '{':
      inc i
      ws()
      if i < n and text[i] == '}':
        inc i
        value = newJObject()
      else:
        stack.add newJObject()
        if not (i < n and text[i] == '"'): fail()
        keys.add str()
        ws()
        if not (i < n and text[i] == ':'): fail()
        inc i
        continue
    of '[':
      inc i
      ws()
      if i < n and text[i] == ']':
        inc i
        value = newJArray()
      else:
        stack.add newJArray()
        keys.add ""
        continue
    of '"': value = newJString(str())
    of 't': value = literal("true", newJBool(true))
    of 'f': value = literal("false", newJBool(false))
    of 'n': value = literal("null", newJNull())
    else: value = number()
    # Attach the value, and close every container that ends after it.
    while true:
      if stack.len == 0:
        ws()
        if i != n: fail()
        return value
      let top = stack[^1]
      if top.kind == JObject: top[keys[^1]] = value
      else: top.add value
      ws()
      if i >= n: fail()
      let c = text[i]
      inc i
      if c == ',':
        if top.kind == JObject:
          ws()
          if not (i < n and text[i] == '"'): fail()
          keys[^1] = str()
          ws()
          if not (i < n and text[i] == ':'): fail()
          inc i
        break
      if (top.kind == JObject and c == '}') or (top.kind == JArray and c == ']'):
        value = top
        discard stack.pop()
        discard keys.pop()
        continue
      fail()
