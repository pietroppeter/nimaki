## JavaScript's `Date`, for the diagrams that compute with dates (gantt). A date is its time value:
## milliseconds since 1970 as a float, NaN for an invalid date. The algorithms are ECMAScript's
## (section 21.4.1, "Overview of Date Objects"), and `parseDate` follows V8's date parser, the
## one Node runs: ISO 8601 first, then the legacy forms browsers accept.
##
## Local time is UTC here. The referee runs Pele with `TZ=UTC` (decision 0012), so every getter
## and setter of local time is its UTC one, and `getTimezoneOffset` is 0.
import std/math

type JsDate* = float  ## a time value; NaN when invalid

const
  msPerDay = 86400000.0
  msPerHour = 3600000.0
  msPerMinute = 60000.0
  msPerSecond = 1000.0

func finite(x: float): bool = x == x and x != Inf and x != -Inf

func toIntegerOrInfinity(x: float): float =
  if x != x: 0.0 else: trunc(x) + 0.0

func modulo(a, b: float): float =
  ## the mathematical modulo, with the sign of b
  result = a mod b
  if result != 0 and (result < 0) != (b < 0): result += b
  result += 0.0

func day*(t: float): float = floor(t / msPerDay)
func timeWithinDay(t: float): float = modulo(t, msPerDay)

func daysInYear(y: float): float =
  if modulo(y, 4) != 0: 365.0
  elif modulo(y, 100) != 0: 366.0
  elif modulo(y, 400) != 0: 365.0
  else: 366.0

func dayFromYear(y: float): float =
  365 * (y - 1970) + floor((y - 1969) / 4) - floor((y - 1901) / 100) + floor((y - 1601) / 400)

func timeFromYear(y: float): float = msPerDay * dayFromYear(y)

func yearFromTime(t: float): float =
  var y = floor(t / (msPerDay * 365.2425)) + 1970
  while timeFromYear(y) > t: y -= 1
  while timeFromYear(y + 1) <= t: y += 1
  y

func inLeapYear(t: float): bool = daysInYear(yearFromTime(t)) == 366

func dayWithinYear(t: float): float = day(t) - dayFromYear(yearFromTime(t))

const monthStarts = [0.0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]

func monthStart(m: int, leap: bool): float =
  monthStarts[m] + (if leap and m >= 2: 1.0 else: 0.0)

func monthFromTime(t: float): float =
  let d = dayWithinYear(t)
  let leap = inLeapYear(t)
  for m in 0 .. 11:
    if d < monthStart(m + 1, leap): return float(m)
  11.0

func dateFromTime(t: float): float =
  let m = int(monthFromTime(t))
  dayWithinYear(t) - monthStart(m, inLeapYear(t)) + 1

func weekDay(t: float): float = modulo(day(t) + 4, 7)
func hourFromTime(t: float): float = modulo(floor(t / msPerHour), 24)
func minFromTime(t: float): float = modulo(floor(t / msPerMinute), 60)
func secFromTime(t: float): float = modulo(floor(t / msPerSecond), 60)
func msFromTime(t: float): float = modulo(t, msPerSecond)

func makeTime*(hour, min, sec, ms: float): float =
  if not (hour.finite and min.finite and sec.finite and ms.finite): return NaN
  let h = toIntegerOrInfinity(hour)
  let m = toIntegerOrInfinity(min)
  let s = toIntegerOrInfinity(sec)
  let milli = toIntegerOrInfinity(ms)
  ((h * msPerHour + m * msPerMinute) + s * msPerSecond) + milli

func makeDay*(year, month, date: float): float =
  if not (year.finite and month.finite and date.finite): return NaN
  let y = toIntegerOrInfinity(year)
  let m = toIntegerOrInfinity(month)
  let dt = toIntegerOrInfinity(date)
  let ym = y + floor(m / 12)
  if not ym.finite: return NaN
  # V8 gives up on years and months far outside the range a time value can reach.
  if abs(ym) > 1_000_000: return NaN
  let mn = int(modulo(m, 12))
  let leap = daysInYear(ym) == 366
  dayFromYear(ym) + monthStart(mn, leap) + dt - 1

func makeDate*(day, time: float): float =
  if not (day.finite and time.finite): return NaN
  let tv = day * msPerDay + time
  if not tv.finite: NaN else: tv

func timeClip*(t: float): JsDate =
  if not t.finite or abs(t) > 8.64e15: NaN else: trunc(t) + 0.0

func isValid*(d: JsDate): bool = d == d

# ---------------------------------------------------------------------------------------------
# Constructors

func fullYear(y: float): float =
  ## new Date(y, ...) and Date.UTC read a year from 0 to 99 as 1900 to 1999.
  if y == y:
    let yi = toIntegerOrInfinity(y)
    if yi >= 0 and yi <= 99: return 1900 + yi
  y

func newDate*(year, month: float, date = 1.0, hours = 0.0, minutes = 0.0, seconds = 0.0, ms = 0.0): JsDate =
  ## new Date(year, month, ...), in local time
  timeClip(makeDate(makeDay(fullYear(year), month, date), makeTime(hours, minutes, seconds, ms)))

func dateUTC*(year, month: float, date = 1.0, hours = 0.0, minutes = 0.0, seconds = 0.0, ms = 0.0): JsDate =
  ## Date.UTC(year, month, ...)
  newDate(year, month, date, hours, minutes, seconds, ms)

func fromTime*(t: float): JsDate = timeClip(t)  ## new Date(number)

# ---------------------------------------------------------------------------------------------
# Getters, local time being UTC

template getter(name, fn: untyped) =
  func name*(d: JsDate): float =
    if d != d: NaN else: fn(d)

getter(getFullYear, yearFromTime)
getter(getMonth, monthFromTime)
getter(getDate, dateFromTime)
getter(getDay, weekDay)
getter(getHours, hourFromTime)
getter(getMinutes, minFromTime)
getter(getSeconds, secFromTime)
getter(getMilliseconds, msFromTime)

func getTimezoneOffset*(d: JsDate): float = (if d != d: NaN else: 0.0)

# ---------------------------------------------------------------------------------------------
# Setters: each returns the new time value, as `d.setX(...)` stores it.

func setDate*(d: JsDate, date: float): JsDate =
  if d != d: return NaN
  timeClip(makeDate(makeDay(yearFromTime(d), monthFromTime(d), date), timeWithinDay(d)))

func setMonth*(d: JsDate, month: float): JsDate =
  if d != d: return NaN
  timeClip(makeDate(makeDay(yearFromTime(d), month, dateFromTime(d)), timeWithinDay(d)))

func setMonth*(d: JsDate, month, date: float): JsDate =
  if d != d: return NaN
  timeClip(makeDate(makeDay(yearFromTime(d), month, date), timeWithinDay(d)))

func setFullYear*(d: JsDate, year: float): JsDate =
  let t = if d != d: 0.0 else: d
  timeClip(makeDate(makeDay(year, monthFromTime(t), dateFromTime(t)), timeWithinDay(t)))

func setHours*(d: JsDate, hours, minutes, seconds, ms: float): JsDate =
  if d != d: return NaN
  timeClip(makeDate(day(d), makeTime(hours, minutes, seconds, ms)))

# ---------------------------------------------------------------------------------------------
# Parsing, as V8 parses (src/date/dateparser*.{h,cc})

type
  TokenKind = enum tkInvalid, tkUnknown, tkNumber, tkSymbol, tkWhiteSpace, tkKeyword, tkEnd
  KeywordType = enum kwInvalid, kwMonthName, kwTimeZoneName, kwTimeSeparator, kwAmPm
  DateToken = object
    kind: TokenKind
    length: int        ## UTF-16 code units
    value: int         ## a number's value, a symbol's character, a keyword's value
    keyword: KeywordType

const kNone = high(int32).int

func isWhiteSpaceRune(c: int): bool =
  ## Unicode white space and line terminators, as V8's IsWhiteSpaceOrLineTerminator
  c == 9 or c == 10 or c == 11 or c == 12 or c == 13 or c == 32 or c == 0xa0 or c == 0x1680 or
    (c >= 0x2000 and c <= 0x200a) or c == 0x2028 or c == 0x2029 or c == 0x202f or c == 0x205f or
    c == 0x3000 or c == 0xfeff

const keywords: array[27, (string, KeywordType, int)] = [
  ("jan", kwMonthName, 1), ("feb", kwMonthName, 2), ("mar", kwMonthName, 3), ("apr", kwMonthName, 4),
  ("may", kwMonthName, 5), ("jun", kwMonthName, 6), ("jul", kwMonthName, 7), ("aug", kwMonthName, 8),
  ("sep", kwMonthName, 9), ("oct", kwMonthName, 10), ("nov", kwMonthName, 11), ("dec", kwMonthName, 12),
  ("am\0", kwAmPm, 0), ("pm\0", kwAmPm, 12),
  ("ut\0", kwTimeZoneName, 0), ("utc", kwTimeZoneName, 0), ("z\0\0", kwTimeZoneName, 0),
  ("gmt", kwTimeZoneName, 0), ("cdt", kwTimeZoneName, -5), ("cst", kwTimeZoneName, -6),
  ("edt", kwTimeZoneName, -4), ("est", kwTimeZoneName, -5), ("mdt", kwTimeZoneName, -6),
  ("mst", kwTimeZoneName, -7), ("pdt", kwTimeZoneName, -7), ("pst", kwTimeZoneName, -8),
  ("t\0\0", kwTimeSeparator, 0),
]

type Scanner = object
  runes: seq[int]   ## the input as UTF-16 code units
  pos: int
  next: DateToken

func ch(s: Scanner, i: int): int = (if i < s.runes.len: s.runes[i] else: 0)

proc scan(s: var Scanner): DateToken =
  let start = s.pos
  if s.pos >= s.runes.len: return DateToken(kind: tkEnd)
  let c = s.runes[s.pos]
  if c >= ord('0') and c <= ord('9'):
    var n = 0
    var i = 0
    while s.pos < s.runes.len and s.runes[s.pos] >= ord('0') and s.runes[s.pos] <= ord('9'):
      # The value keeps nine significant digits; the rest are read and dropped.
      if i < 9: n = n * 10 + s.runes[s.pos] - ord('0')
      inc i
      inc s.pos
    return DateToken(kind: tkNumber, value: n, length: s.pos - start)
  if c in [ord(':'), ord('-'), ord('+'), ord('.'), ord(')')]:
    inc s.pos
    return DateToken(kind: tkSymbol, value: c, length: 1)
  if c >= ord('A') and not isWhiteSpaceRune(c):
    var prefix = [0, 0, 0]
    var len = 0
    while s.pos < s.runes.len and s.runes[s.pos] >= ord('A') and not isWhiteSpaceRune(s.runes[s.pos]):
      if len < 3: prefix[len] = s.runes[s.pos] or 0x20
      inc len
      inc s.pos
    for (word, kind, value) in keywords:
      var j = 0
      while j < 3 and prefix[j] == ord(word[j]): inc j
      if j == 3 and (len <= 3 or kind == kwMonthName):
        return DateToken(kind: tkKeyword, keyword: kind, value: value, length: len)
    return DateToken(kind: tkKeyword, keyword: kwInvalid, value: 0, length: len)
  if isWhiteSpaceRune(c):
    while s.pos < s.runes.len and isWhiteSpaceRune(s.runes[s.pos]): inc s.pos
    return DateToken(kind: tkWhiteSpace, length: s.pos - start)
  if c == ord('('):
    var balance = 0
    while true:
      let k = s.ch(s.pos)
      if k == ord(')'): dec balance
      elif k == ord('('): inc balance
      inc s.pos
      if not (balance > 0 and s.ch(s.pos) != 0): break
    return DateToken(kind: tkUnknown)
  inc s.pos
  DateToken(kind: tkUnknown)

proc initScanner(text: string): Scanner =
  var i = 0
  while i < text.len:
    # UTF-8 to UTF-16 code units
    let b = ord(text[i])
    var cp, size: int
    if b < 0x80: (cp, size) = (b, 1)
    elif b < 0xe0: (cp, size) = (((b and 0x1f) shl 6) or (ord(text[i + 1]) and 0x3f), 2)
    elif b < 0xf0: (cp, size) = (((b and 0x0f) shl 12) or ((ord(text[i + 1]) and 0x3f) shl 6) or (ord(text[i + 2]) and 0x3f), 3)
    else: (cp, size) = (((b and 0x07) shl 18) or ((ord(text[i + 1]) and 0x3f) shl 12) or ((ord(text[i + 2]) and 0x3f) shl 6) or (ord(text[i + 3]) and 0x3f), 4)
    if cp >= 0x10000:
      result.runes.add 0xd800 + ((cp - 0x10000) shr 10)
      result.runes.add 0xdc00 + ((cp - 0x10000) and 0x3ff)
    else:
      result.runes.add cp
    i += size
  result.next = result.scan()

proc take(s: var Scanner): DateToken =
  result = s.next
  s.next = s.scan()

func peek(s: Scanner): DateToken = s.next

func isSymbol(t: DateToken, c: char): bool = t.kind == tkSymbol and t.value == ord(c)
func isSign(t: DateToken): bool = t.kind == tkSymbol and (t.value == ord('+') or t.value == ord('-'))
func sign(t: DateToken): int = (if t.value == ord('-'): -1 else: 1)
func isFixed(t: DateToken, n: int): bool = t.kind == tkNumber and t.length == n
func isKeywordZ(t: DateToken): bool =
  t.kind == tkKeyword and t.keyword == kwTimeZoneName and t.length == 1 and t.value == 0
func between(x, lo, hi: int): bool = x >= lo and x <= hi

proc skipSymbol(s: var Scanner, c: char): bool =
  if s.next.isSymbol(c):
    discard s.take()
    true
  else: false

type
  DayComposer = object
    comp: array[3, int]
    index: int
    namedMonth: int
    isoDate: bool
  TimeComposer = object
    comp: array[4, int]
    index: int
    hourOffset: int
  TimeZoneComposer = object
    sign, hour, minute: int

func isMonth(x: int): bool = between(x, 1, 12)
func isDay(x: int): bool = between(x, 1, 31)
func isMinute(x: int): bool = between(x, 0, 59)
func isHour(x: int): bool = between(x, 0, 23)
func isSecond(x: int): bool = between(x, 0, 59)
func isHour12(x: int): bool = between(x, 0, 12)
func isMillisecond(x: int): bool = between(x, 0, 999)

proc add(d: var DayComposer, n: int): bool =
  if d.index < 3:
    d.comp[d.index] = n
    inc d.index
    true
  else: false

proc add(t: var TimeComposer, n: int): bool =
  if t.index < 4:
    t.comp[t.index] = n
    inc t.index
    true
  else: false

proc addFinal(t: var TimeComposer, n: int): bool =
  if not t.add(n): return false
  while t.index < 4:
    t.comp[t.index] = 0
    inc t.index
  true

func isExpecting(t: TimeComposer, n: int): bool =
  (t.index == 1 and isMinute(n)) or (t.index == 2 and isSecond(n)) or (t.index == 3 and isMillisecond(n))

proc set(z: var TimeZoneComposer, hours: int) =
  z.sign = if hours < 0: -1 else: 1
  z.hour = hours * z.sign
  z.minute = 0

func isExpecting(z: TimeZoneComposer, n: int): bool = z.hour != kNone and z.minute == kNone and isMinute(n)
func isUTC(z: TimeZoneComposer): bool = z.hour == 0 and z.minute == 0

func readMilliseconds(t: DateToken): int =
  var number = t.value
  var length = t.length
  if length < 3:
    if length == 1: number *= 100
    elif length == 2: number *= 10
  elif length > 3:
    if length > 9: length = 9
    var factor = 1
    while true:
      factor *= 10
      dec length
      if length <= 3: break
    number = number div factor
  number

proc parseES5(s: var Scanner, day: var DayComposer, time: var TimeComposer, tz: var TimeZoneComposer): DateToken =
  if s.peek.isSign:
    let signToken = s.take()
    if not s.peek.isFixed(6): return signToken
    let sign = signToken.sign
    let year = s.take().value
    if sign < 0 and year == 0: return signToken
    discard day.add(sign * year)
  elif s.peek.isFixed(4):
    discard day.add(s.take().value)
  else:
    return s.take()
  if s.skipSymbol('-'):
    if not s.peek.isFixed(2) or not isMonth(s.peek.value): return s.take()
    discard day.add(s.take().value)
    if s.skipSymbol('-'):
      if not s.peek.isFixed(2) or not isDay(s.peek.value): return s.take()
      discard day.add(s.take().value)
  if not (s.peek.kind == tkKeyword and s.peek.keyword == kwTimeSeparator):
    if s.peek.kind != tkEnd: return s.take()
  else:
    discard s.take()
    if not s.peek.isFixed(2) or not between(s.peek.value, 0, 24): return DateToken(kind: tkInvalid)
    let hourIs24 = s.peek.value == 24
    discard time.add(s.take().value)
    if not s.skipSymbol(':'): return DateToken(kind: tkInvalid)
    if not s.peek.isFixed(2) or not isMinute(s.peek.value) or (hourIs24 and s.peek.value > 0):
      return DateToken(kind: tkInvalid)
    discard time.add(s.take().value)
    if s.skipSymbol(':'):
      if not s.peek.isFixed(2) or not isSecond(s.peek.value) or (hourIs24 and s.peek.value > 0):
        return DateToken(kind: tkInvalid)
      discard time.add(s.take().value)
      if s.skipSymbol('.'):
        if s.peek.kind != tkNumber or (hourIs24 and s.peek.value > 0): return DateToken(kind: tkInvalid)
        discard time.add(readMilliseconds(s.take()))
    if s.peek.isKeywordZ:
      discard s.take()
      tz.set(0)
    elif s.peek.isSign:
      tz.sign = s.take().sign
      if s.peek.isFixed(4):
        let hourmin = s.take().value
        let hour = hourmin div 100
        let minute = hourmin mod 100
        if not isHour(hour) or not isMinute(minute): return DateToken(kind: tkInvalid)
        tz.hour = hour
        tz.minute = minute
      else:
        if not s.peek.isFixed(2) or not isHour(s.peek.value): return DateToken(kind: tkInvalid)
        tz.hour = s.take().value
        if not s.skipSymbol(':'): return DateToken(kind: tkInvalid)
        if not s.peek.isFixed(2) or not isMinute(s.peek.value): return DateToken(kind: tkInvalid)
        tz.minute = s.take().value
    if s.peek.kind != tkEnd: return DateToken(kind: tkInvalid)
  if tz.hour == kNone and time.index == 0: tz.set(0)
  day.isoDate = true
  DateToken(kind: tkEnd)

proc write(d: var DayComposer, year, month, date: var int): bool =
  if d.index < 1: return false
  while d.index < 3:
    d.comp[d.index] = 1
    inc d.index
  year = 0  # for KJS compatibility, a missing year is 0, which reads as 2000
  if d.namedMonth == kNone:
    if d.isoDate or not isDay(d.comp[0]):
      year = d.comp[0]
      month = d.comp[1]
      date = d.comp[2]
    else:
      month = d.comp[0]
      date = d.comp[1]
      year = d.comp[2]
  else:
    month = d.namedMonth
    if d.index == 1:
      date = d.comp[0]
    elif not isDay(d.comp[0]):
      year = d.comp[0]
      date = d.comp[1]
    else:
      date = d.comp[0]
      year = d.comp[1]
  if not d.isoDate:
    if between(year, 0, 49): year += 2000
    elif between(year, 50, 99): year += 1900
  isMonth(month) and isDay(date)

proc write(t: var TimeComposer, out4: var array[4, int]): bool =
  while t.index < 4:
    t.comp[t.index] = 0
    inc t.index
  var hour = t.comp[0]
  if t.hourOffset != kNone:
    if not isHour12(hour): return false
    hour = hour mod 12 + t.hourOffset
  let (minute, second, ms) = (t.comp[1], t.comp[2], t.comp[3])
  if not isHour(hour) or not isMinute(minute) or not isSecond(second) or not isMillisecond(ms):
    if hour != 24 or minute != 0 or second != 0 or ms != 0: return false
  out4 = [hour, minute, second, ms]
  true

func write(z: TimeZoneComposer, offset: var float): bool =
  if z.sign != kNone:
    let hour = if z.hour == kNone: 0 else: z.hour
    let minute = if z.minute == kNone: 0 else: z.minute
    let total = float(hour) * 3600 + float(minute) * 60
    if total > 1073741823: return false
    offset = if z.sign < 0: -total else: total
  else:
    offset = NaN
  true

proc parseDate*(text: string): JsDate =
  ## new Date(text)
  var s = initScanner(text)
  var day = DayComposer(namedMonth: kNone)
  var time = TimeComposer(hourOffset: kNone)
  var tz = TimeZoneComposer(sign: kNone, hour: kNone, minute: kNone)
  var token = parseES5(s, day, time, tz)
  if token.kind == tkInvalid: return NaN
  var hasReadNumber = day.index > 0
  while token.kind != tkEnd:
    if token.kind == tkNumber:
      hasReadNumber = true
      let n = token.value
      if s.skipSymbol(':'):
        if s.skipSymbol(':'):
          if time.index != 0: return NaN
          discard time.add(n)
          discard time.add(0)
        else:
          if not time.add(n): return NaN
          if s.peek.isSymbol('.'): discard s.take()
      elif s.skipSymbol('.') and time.isExpecting(n):
        discard time.add(n)
        if s.peek.kind != tkNumber: return NaN
        let ms = readMilliseconds(s.take())
        if ms < 0: return NaN
        discard time.addFinal(ms)
      elif tz.isExpecting(n):
        tz.minute = n
      elif time.isExpecting(n):
        discard time.addFinal(n)
        let p = s.peek
        if p.kind != tkEnd and p.kind != tkWhiteSpace and not p.isKeywordZ and not p.isSign: return NaN
      else:
        if not day.add(n): return NaN
        discard s.skipSymbol('-')
    elif token.kind == tkKeyword:
      if token.keyword == kwAmPm and time.index != 0:
        time.hourOffset = token.value
      elif token.keyword == kwMonthName:
        day.namedMonth = token.value
        discard s.skipSymbol('-')
      elif token.keyword == kwTimeZoneName and hasReadNumber:
        tz.set(token.value)
      else:
        if hasReadNumber: return NaN
        if s.peek.kind == tkNumber: return NaN
    elif token.isSign and (tz.isUTC or time.index != 0):
      tz.sign = token.sign
      var n = 0
      var length = 0
      if s.peek.kind == tkNumber:
        let t = s.take()
        length = t.length
        n = t.value
      hasReadNumber = true
      if s.peek.isSymbol(':'):
        tz.hour = n
        tz.minute = kNone
      elif length == 2 or length == 1:
        tz.hour = n
        tz.minute = 0
      elif length == 4 or length == 3:
        tz.hour = n div 100
        tz.minute = n mod 100
      else:
        return NaN
    elif (token.isSign or token.isSymbol(')')) and hasReadNumber:
      return NaN
    token = s.take()
  var year, month, date: int
  var clock: array[4, int]
  var offset: float
  if not (day.write(year, month, date) and time.write(clock) and tz.write(offset)): return NaN
  var tv = makeDate(makeDay(float(year), float(month - 1), float(date)),
                    makeTime(float(clock[0]), float(clock[1]), float(clock[2]), float(clock[3])))
  if offset == offset: tv -= offset * 1000
  timeClip(tv)
