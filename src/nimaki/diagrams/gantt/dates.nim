## port-of: src/diagrams/gantt/dates.ts
## port-status: draft
##
## The parts of dayjs 1.11 that Mermaid's gantt code relies on, with the plugins it loads (custom parse format,
## advanced format, ISO week) and the English locale: strict parsing against a format, formatting, and calendar
## arithmetic, all in local time. Quirks are kept, because a date is accepted only when formatting the parsed
## result gives back the input.
##
## Port notes: a `Date` is a `JsDate` (src/nimaki/jsdate.nim), and each `d.setX(...)` that changes a
## date in place returns the new value here. An unset field of the parse is NaN.
import std/[options, strutils]
from std/math import floor, ceil, `mod`
import ../../js
import ../../jsdate

const MONTHS* = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                 "October", "November", "December"]
const WEEKDAYS* = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

const
  DAY = 86400000.0
  WEEK = 7 * DAY

type Unit* = string  ## 'ms' | 's' | 'm' | 'h' | 'd' | 'w' | 'M' | 'y'

func pad(value: float, length: int): string =
  let s = jsString(value)
  if s.len >= length: s else: '0'.repeat(length - s.len) & s

func ordinal*(n: float): string =
  const s = ["th", "st", "nd", "rd"]
  let v = n mod 100   # JavaScript's %, with the sign of n
  let i = (v - 20) mod 10
  let suffix = if i >= 0 and i <= 3 and i == floor(i): s[int(i)]
               elif v >= 0 and v <= 3 and v == floor(v): s[int(v)]
               else: s[0]
  jsString(n) & suffix

func zone(date: JsDate): string = "+00:00"  ## the offset is 0, as TZ is UTC

func isoWeekday*(date: JsDate): float =
  ## date.getDay() || 7
  let d = date.getDay
  if d == 0 or d != d: 7.0 else: d

func addDays*(date: JsDate, days: float): JsDate = date.setDate(date.getDate + days)

func daysInMonth(date: JsDate): float =
  var last = newDate(date.getFullYear, date.getMonth + 1, 0)
  last = last.setHours(23, 59, 59, 999)
  last.getDate

func jsMinF(a, b: float): float = (if a != a or b != b: NaN else: min(a, b))

func setCalendar(date: JsDate, apply: proc (d: JsDate): JsDate {.noSideEffect.}): JsDate =
  ## Sets the month or the year, keeping the day of the month unless the new month is shorter.
  var next = date
  next = next.setDate(1)
  next = apply(next)
  next.setDate(jsMinF(date.getDate, daysInMonth(next)))

func add*(date: JsDate, amount: float, unit: Unit): JsDate =
  case unit
  of "M":
    let month = date.getMonth + amount
    setCalendar(date, proc (d: JsDate): JsDate = d.setMonth(month))
  of "y":
    let year = date.getFullYear + amount
    setCalendar(date, proc (d: JsDate): JsDate = d.setFullYear(year))
  of "d": addDays(date, jsRound(amount))
  of "w": addDays(date, jsRound(7 * amount))
  of "h": fromTime(date + amount * 3600000)
  of "m": fromTime(date + amount * 60000)
  of "s": fromTime(date + amount * 1000)
  else: fromTime(date + amount)

func weekThursday(date: JsDate): JsDate = addDays(date, 4 - isoWeekday(date))

func isoWeek(date: JsDate): float =
  let thursday = weekThursday(date)
  let jan1 = newDate(thursday.getFullYear, 0, 1)
  let weekday = isoWeekday(jan1)
  let first = addDays(jan1, 4 - weekday + (if weekday > 4: 7.0 else: 0.0))
  let weeks = (thursday - first) / WEEK
  (if weeks < 0: ceil(weeks) + 0.0 else: floor(weeks)) + 1

const DEFAULT_FORMAT = "YYYY-MM-DDTHH:mm:ssZ"

func bracketEnd(s: string, i: int): int =
  ## /\[([^\]]+)]/ at i: where it ends, or -1
  if i >= s.len or s[i] != '[': return -1
  let close = s.find(']', i + 1)
  if close <= i + 1: -1 else: close + 1

func runOf(s: string, i: int, c: char, most: int): int =
  ## c{1,most} at i: how many
  while result < most and i + result < s.len and s[i + result] == c: inc result

proc isoDate*(date: JsDate): string

proc format*(date: JsDate, temp: string): Option[string] =
  ## Returns none for the week-of-year and time zone name tokens, which need dayjs plugins Mermaid
  ## does not load and so fail there.
  if not date.isValid: return some("Invalid Date")
  let str = if temp == "": DEFAULT_FORMAT else: temp
  if str == "YYYY-MM-DD": return some(isoDate(date))
  var unsupported = false
  # str.replace(/\[([^\]]+)]|Q|wo|ww|w|WW|W|zzz|z|gggg|GGGG|Do|X|x|k{1,2}|S/g, ...)
  var advanced = ""
  var i = 0
  template rest(t: string): bool = str.continuesWith(t, i)
  while i < str.len:
    let b = bracketEnd(str, i)
    if b >= 0:
      advanced.add str[i ..< b]
      i = b
      continue
    if rest("Q"):
      advanced.add jsString(ceil((date.getMonth + 1) / 3)); i += 1
    elif rest("wo") or rest("ww"):
      unsupported = true; advanced.add str[i .. i + 1]; i += 2
    elif rest("w"):
      unsupported = true; advanced.add "w"; i += 1
    elif rest("WW"):
      advanced.add pad(isoWeek(date), 2); i += 2
    elif rest("W"):
      advanced.add jsString(isoWeek(date)); i += 1
    elif rest("zzz"):
      unsupported = true; advanced.add "zzz"; i += 3
    elif rest("z"):
      unsupported = true; advanced.add "z"; i += 1
    elif rest("gggg"):
      unsupported = true; advanced.add "gggg"; i += 4
    elif rest("GGGG"):
      advanced.add jsString(weekThursday(date).getFullYear); i += 4
    elif rest("Do"):
      advanced.add "[" & ordinal(date.getDate) & "]"; i += 2
    elif rest("X"):
      advanced.add jsString(floor(date / 1000)); i += 1
    elif rest("x"):
      advanced.add jsString(date); i += 1
    elif rest("k"):
      let h = date.getHours
      let hours = if h == 0: 24.0 else: h
      if rest("kk"):
        advanced.add pad(hours, 2); i += 2
      else:
        advanced.add jsString(hours); i += 1
    else:
      advanced.add str[i]; i += 1
  if unsupported: return none(string)
  let hours = date.getHours
  # advanced.replace(/\[([^\]]+)]|YYYY|YY|M{1,4}|D{1,2}|d{1,4}|H{1,2}|h{1,2}|a|A|m{1,2}|s{1,2}|Z{1,2}|SSS/g, ...)
  var output = ""
  i = 0
  let s = advanced
  while i < s.len:
    let b = bracketEnd(s, i)
    if b >= 0:
      output.add s[i + 1 ..< b - 1]
      i = b
      continue
    let c = s[i]
    case c
    of 'Y':
      if s.continuesWith("YYYY", i):
        output.add pad(date.getFullYear, 4); i += 4
      elif s.continuesWith("YY", i):
        let y = jsString(date.getFullYear)
        output.add(if y.len > 2: y[^2 .. ^1] else: y); i += 2
      else:
        output.add c; inc i
    of 'M':
      let n = runOf(s, i, 'M', 4)
      let m = date.getMonth
      output.add(case n
        of 1: jsString(m + 1)
        of 2: pad(m + 1, 2)
        of 3: MONTHS[int(m)][0 ..< 3]
        else: MONTHS[int(m)])
      i += n
    of 'D':
      let n = runOf(s, i, 'D', 2)
      output.add(if n == 1: jsString(date.getDate) else: pad(date.getDate, 2))
      i += n
    of 'd':
      let n = runOf(s, i, 'd', 4)
      let d = int(date.getDay)
      output.add(case n
        of 1: jsString(float(d))
        of 2: WEEKDAYS[d][0 ..< 2]
        of 3: WEEKDAYS[d][0 ..< 3]
        else: WEEKDAYS[d])
      i += n
    of 'H':
      let n = runOf(s, i, 'H', 2)
      output.add(if n == 1: jsString(hours) else: pad(hours, 2))
      i += n
    of 'h':
      let n = runOf(s, i, 'h', 2)
      let h12 = (let r = hours mod 12; if r == 0: 12.0 else: r)
      output.add(if n == 1: jsString(h12) else: pad(h12, 2))
      i += n
    of 'a':
      output.add(if hours < 12: "am" else: "pm"); inc i
    of 'A':
      output.add(if hours < 12: "AM" else: "PM"); inc i
    of 'm':
      let n = runOf(s, i, 'm', 2)
      output.add(if n == 1: jsString(date.getMinutes) else: pad(date.getMinutes, 2))
      i += n
    of 's':
      let n = runOf(s, i, 's', 2)
      output.add(if n == 1: jsString(date.getSeconds) else: pad(date.getSeconds, 2))
      i += n
    of 'Z':
      let n = runOf(s, i, 'Z', 2)
      output.add(if n == 1: zone(date) else: zone(date).replace(":", ""))
      i += n
    of 'S':
      if s.continuesWith("SSS", i):
        output.add pad(date.getMilliseconds, 3); i += 3
      else:
        output.add c; inc i
    else:
      output.add c; inc i
  some(output)

proc isoDate*(date: JsDate): string =
  let year = date.getFullYear
  let month = date.getMonth + 1
  let day = date.getDate
  (if year >= 1000 and year <= 9999: jsString(year) else: pad(year, 4)) &
    (if month < 10: "-0" else: "-") & jsString(month) & (if day < 10: "-0" else: "-") & jsString(day)

# ---------------------------------------------------------------------------------------------
# Parsing

type
  Fields = object
    year, month, day, hours, minutes, seconds, milliseconds, week, offset: float  ## NaN: unset
    dayGiven: bool
    afternoon: int  ## -1 unset, 0 false, 1 true

  Matcher = proc (s: string): (int, int) {.noSideEffect.}
    ## the first match in s: its start and end, or (-1, -1)
  Reader = proc (f: var Fields, input: string): bool {.noSideEffect.}

  Step = object
    literal: string
    isReader: bool
    re: Matcher
    read: Reader

func unset(): Fields =
  Fields(year: NaN, month: NaN, day: NaN, hours: NaN, minutes: NaN, seconds: NaN, milliseconds: NaN,
         week: NaN, offset: NaN, afternoon: -1)

func truthy(x: float): bool = x == x and x != 0

func isDigit(s: string, i: int): bool = i < s.len and s[i] in {'0'..'9'}

func search(s: string, at: proc (s: string, i: int): int {.noSideEffect.}): (int, int) =
  ## The leftmost match of a pattern given as a matcher at each position.
  var i = 0
  while i <= s.len:
    let e = at(s, i)
    if e >= 0: return (i, e)
    if i < s.len: i += codePointAt(s, i).size else: inc i
  (-1, -1)

func digitsExactly(n: int): Matcher =
  ## /\d{n}/
  result = proc (s: string): (int, int) =
    search(s, proc (s: string, i: int): int =
      for k in 0 ..< n:
        if not isDigit(s, i + k): return -1
      i + n)

let MATCH_1 = digitsExactly(1)
let MATCH_2 = digitsExactly(2)
let MATCH_3 = digitsExactly(3)
let MATCH_4 = digitsExactly(4)
let MATCH_1_TO_2: Matcher = proc (s: string): (int, int) =
  ## /\d\d?/
  search(s, proc (s: string, i: int): int =
    if not isDigit(s, i): -1 elif isDigit(s, i + 1): i + 2 else: i + 1)
let MATCH_SIGNED: Matcher = proc (s: string): (int, int) =
  ## /[+-]?\d+/
  search(s, proc (s: string, i: int): int =
    var j = i
    if j < s.len and s[j] in {'+', '-'} and isDigit(s, j + 1): inc j
    if not isDigit(s, j): return -1
    while isDigit(s, j): inc j
    j)
let MATCH_OFFSET: Matcher = proc (s: string): (int, int) =
  ## /[+-]\d\d:?(\d\d)?|Z/
  search(s, proc (s: string, i: int): int =
    if i < s.len and s[i] in {'+', '-'} and isDigit(s, i + 1) and isDigit(s, i + 2):
      var j = i + 3
      if j < s.len and s[j] == ':': inc j
      if isDigit(s, j) and isDigit(s, j + 1): j += 2
      return j
    if i < s.len and s[i] == 'Z': i + 1 else: -1)

func isWordStop(s: string, i: int): bool =
  ## [-_:/,()\s\d]
  s[i] in {'-', '_', ':', '/', ',', '(', ')', '0'..'9'} or isJsSpaceAt(s, i)

let MATCH_WORD: Matcher = proc (s: string): (int, int) =
  ## /\d*[^-_:/,()\s\d]+/
  search(s, proc (s: string, i: int): int =
    var j = i
    while isDigit(s, j): inc j
    if j >= s.len or isWordStop(s, j): return -1
    while j < s.len and not isWordStop(s, j): j += codePointAt(s, j).size
    j)

func num(input: string): float = jsToNumber(input)

proc field(name: string): Reader =
  result = proc (f: var Fields, input: string): bool =
    let v = num(input)
    case name
    of "seconds": f.seconds = v
    of "minutes": f.minutes = v
    of "hours": f.hours = v
    of "day": f.day = v
    of "week": f.week = v
    of "month": f.month = v
    else: f.year = v
    true

let readOffset: Reader = proc (f: var Fields, input: string): bool =
  if input == "Z":
    f.offset = 0
    return true
  # input.match(/([+-]|\d\d)/g)
  var parts: seq[string]
  var i = 0
  while i < input.len:
    if input[i] in {'+', '-'}:
      parts.add $input[i]; inc i
    elif isDigit(input, i) and isDigit(input, i + 1):
      parts.add input[i .. i + 1]; i += 2
    else: inc i
  let second = if parts.len > 2: num(parts[2]) else: NaN
  let minutes = num(parts[1]) * 60 + (if truthy(second): second else: 0.0)
  f.offset = if minutes == 0: 0.0 elif parts[0] == "+": -minutes else: minutes
  true

proc monthName(names: seq[string]): Reader =
  result = proc (f: var Fields, input: string): bool =
    let index = names.find(input) + 1
    if index < 1: return false
    f.month = float(if index mod 12 != 0: index mod 12 else: index)
    true

proc readDo(f: var Fields, input: string): bool =
  # input.match(/\d+/)
  var i = 0
  while i < input.len and not isDigit(input, i): inc i
  if i >= input.len: return false
  var j = i
  while isDigit(input, j): inc j
  # dayjs keeps the digits as a string here, so even "0" counts as a day having been given.
  f.day = num(input[i ..< j])
  f.dayGiven = true
  for k in 1 .. 31:
    if ordinal(float(k)) == input: f.day = float(k)
  true

func step(re: Matcher, read: Reader): Step = Step(isReader: true, re: re, read: read)

proc readerFor(token: string): Option[Step] =
  case token
  of "A": some(step(MATCH_WORD, proc (f: var Fields, input: string): bool =
                f.afternoon = ord(input == "PM"); true))
  of "a": some(step(MATCH_WORD, proc (f: var Fields, input: string): bool =
                f.afternoon = ord(input == "pm"); true))
  of "Q": some(step(MATCH_1, proc (f: var Fields, input: string): bool =
                f.month = (num(input) - 1) * 3 + 1; true))
  of "S": some(step(MATCH_1, proc (f: var Fields, input: string): bool =
                f.milliseconds = num(input) * 100; true))
  of "SS": some(step(MATCH_2, proc (f: var Fields, input: string): bool =
                f.milliseconds = num(input) * 10; true))
  of "SSS": some(step(MATCH_3, proc (f: var Fields, input: string): bool =
                f.milliseconds = num(input); true))
  of "s", "ss": some(step(MATCH_1_TO_2, field("seconds")))
  of "m", "mm": some(step(MATCH_1_TO_2, field("minutes")))
  of "H", "h", "HH", "hh": some(step(MATCH_1_TO_2, field("hours")))
  of "D": some(step(MATCH_1_TO_2, field("day")))
  of "DD": some(step(MATCH_2, field("day")))
  of "Do": some(step(MATCH_WORD, readDo))
  of "w": some(step(MATCH_1_TO_2, field("week")))
  of "ww": some(step(MATCH_2, field("week")))
  of "M": some(step(MATCH_1_TO_2, field("month")))
  of "MM": some(step(MATCH_2, field("month")))
  of "MMM":
    var names: seq[string]
    for m in MONTHS: names.add m[0 ..< 3]
    some(step(MATCH_WORD, monthName(names)))
  of "MMMM": some(step(MATCH_WORD, monthName(@MONTHS)))
  of "Y": some(step(MATCH_SIGNED, field("year")))
  of "YY": some(step(MATCH_2, proc (f: var Fields, input: string): bool =
                f.year = num(input) + (if num(input) > 68: 1900.0 else: 2000.0); true))
  of "YYYY": some(step(MATCH_4, field("year")))
  of "Z", "ZZ": some(step(MATCH_OFFSET, readOffset))
  else: none(Step)

func formatTokenEnd(s: string, i: int): int =
  ## The end of a match of RE_TOKENS at i, or -1:
  ## /(\[[^[]*\])|([-_:/.,()\s]+)|(A|a|Q|YYYY|YY?|ww?|MM?M?M?|Do|DD?|hh?|HH?|mm?|ss?|S{1,3}|z|ZZ?)/
  if s[i] == '[':
    # [^[]* runs to the next '[' and gives back characters until a ']'
    var stop = s.find('[', i + 1)
    if stop == -1: stop = s.len
    let close = s.rfind(']', start = i + 1, last = stop - 1)
    if close > i: return close + 1
  block separators:
    var j = i
    while j < s.len:
      if s[j] in {'-', '_', ':', '/', '.', ',', '(', ')'}: inc j
      elif isJsSpaceAt(s, j): j += spaceLenAt(s, j)
      else: break
    if j > i: return j
  template at(t: string): bool = s.continuesWith(t, i)
  case s[i]
  of 'A', 'a', 'Q', 'z': i + 1
  of 'Y': (if at("YYYY"): i + 4 elif at("YY"): i + 2 else: i + 1)
  of 'w', 'h', 'H', 'm', 's', 'D', 'Z':
    if s[i] == 'D' and at("Do"): i + 2
    elif i + 1 < s.len and s[i + 1] == s[i]: i + 2
    else: i + 1
  of 'M': i + runOf(s, i, 'M', 4)
  of 'S': i + runOf(s, i, 'S', 3)
  else: -1

func dropLiterals(s: string): string =
  ## s.replace(/\[[^\]]+]/g, '')
  var i = 0
  while i < s.len:
    let b = bracketEnd(s, i)
    if b >= 0:
      i = b
      continue
    result.add s[i]
    inc i

proc compile(temp: string): Option[seq[Step]] =
  # dayjs expands localized tokens through a locale table the English locale does not have, and fails.
  let bare = dropLiterals(temp)
  if 'L' in bare or 'l' in bare: return none(seq[Step])
  var steps: seq[Step]
  var i = 0
  while i < temp.len:
    let e = formatTokenEnd(temp, i)
    if e < 0:
      i += codePointAt(temp, i).size
      continue
    let token = temp[i ..< e]
    let reader = readerFor(token)
    if reader.isSome:
      steps.add reader.get
    else:
      # token.replace(/^\[|\]$/g, '')
      var lit = token
      if lit.startsWith("["): lit = lit[1 .. ^1]
      if lit.endsWith("]"): lit = lit[0 ..< lit.len - 1]
      steps.add Step(literal: lit)
    i = e
  if steps.len == 0: return none(seq[Step])
  some(steps)

proc loose(input: string, temp: string, now: JsDate): JsDate =
  if temp == "x" or temp == "X": return fromTime((if temp == "X": 1000.0 else: 1.0) * jsToNumber(input))
  let compiled = compile(temp)
  if compiled.isNone: return NaN
  var f = unset()
  var rest = input
  var start = 0
  for step in compiled.get:
    if not step.isReader:
      start += utf16Len(step.literal)
      continue
    let slice = substringFrom(rest, start)
    let (a, b) = step.re(slice)
    if a < 0: return NaN
    let matched = slice[a ..< b]
    if not step.read(f, matched): return NaN
    # dayjs drops the first occurrence of the matched text, wherever it is, and does not move `start`.
    rest = rest.replaceFirst(matched, "")
  if f.afternoon != -1 and f.hours == f.hours:
    if f.afternoon == 1:
      if f.hours < 12: f.hours += 12
    elif f.hours == 12:
      f.hours = 0
  let day = if f.dayGiven or truthy(f.day): f.day
            elif not truthy(f.year) and not truthy(f.month): now.getDate
            else: 1.0
  let year = if truthy(f.year): f.year else: now.getFullYear
  var month = 0.0
  if not (truthy(f.year) and not truthy(f.month)):
    month = if f.month > 0: f.month - 1 else: now.getMonth
  let hours = if truthy(f.hours): f.hours else: 0.0
  let minutes = if truthy(f.minutes): f.minutes else: 0.0
  let seconds = if truthy(f.seconds): f.seconds else: 0.0
  let ms = if truthy(f.milliseconds): f.milliseconds else: 0.0
  if f.offset == f.offset:
    return dateUTC(year, month, day, hours, minutes, seconds, ms + f.offset * 60000)
  # Applying a week number needs a dayjs plugin Mermaid does not load.
  if truthy(f.week): return NaN
  newDate(year, month, day, hours, minutes, seconds, ms)

proc parseStrict*(input: string, temp: string, now: JsDate): Option[JsDate] =
  ## Parses the way `dayjs(input, format, true)` does. `now` supplies the fields the format leaves out.
  let date = loose(input, temp, now)
  if date.isValid and format(date, temp) == some(input): some(date) else: none(JsDate)
