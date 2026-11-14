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
import ../../jsregex

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

const RE_ADVANCED = jsre"/\[([^\]]+)]|Q|wo|ww|w|WW|W|zzz|z|gggg|GGGG|Do|X|x|k{1,2}|S/g"
const RE_FORMAT = jsre"/\[([^\]]+)]|YYYY|YY|M{1,4}|D{1,2}|d{1,4}|H{1,2}|h{1,2}|a|A|m{1,2}|s{1,2}|Z{1,2}|SSS/g"

proc isoDate*(date: JsDate): string

type MatchCache = tuple[text: string, matches: seq[JsMatch], valid: bool]

var lastAdvanced, lastFormat: MatchCache
  ## The matches of the last format string, kept: a chart formats every day of its range with
  ## one format, and a long one (Pele's stress tests write 12,000 characters) would be read
  ## again for each day. The matches depend on the text alone, so the output is the same.

proc matchesIn(re: JsRegExp, text: string, cache: var MatchCache): seq[JsMatch] =
  if not cache.valid or cache.text != text: cache = (text, text.matchAll(re), true)
  cache.matches

template replaceEach(text: string, matches: seq[JsMatch], m, by: untyped): string =
  ## `text.replace(re, (m) => by)`, from the matches of `re` in `text`.
  var output = ""
  var last = 0
  for m in matches:
    output.add text[last ..< m.index]
    output.add by
    last = m.stop
  output.add text[last .. ^1]
  output

proc format*(date: JsDate, temp: string): Option[string] =
  ## Returns none for the week-of-year and time zone name tokens, which need dayjs plugins Mermaid
  ## does not load and so fail there.
  if not date.isValid: return some("Invalid Date")
  let str = if temp == "": DEFAULT_FORMAT else: temp
  if str == "YYYY-MM-DD": return some(isoDate(date))
  var unsupported = false
  let advanced = str.replaceEach(RE_ADVANCED.matchesIn(str, lastAdvanced), m):
    case m[0]
    of "Q": jsString(ceil((date.getMonth + 1) / 3))
    of "Do": "[" & ordinal(date.getDate) & "]"
    of "GGGG": jsString(weekThursday(date).getFullYear)
    of "W": jsString(isoWeek(date))
    of "WW": pad(isoWeek(date), 2)
    of "k": jsString(if date.getHours == 0: 24.0 else: date.getHours)
    of "kk": pad(if date.getHours == 0: 24.0 else: date.getHours, 2)
    of "X": jsString(floor(date / 1000))
    of "x": jsString(date)
    of "gggg", "wo", "w", "ww", "z", "zzz":
      unsupported = true
      m[0]
    else: m[0]
  if unsupported: return none(string)
  let hours = date.getHours
  let h12 = (let r = hours mod 12; if r == 0: 12.0 else: r)
  let output = advanced.replaceEach(RE_FORMAT.matchesIn(advanced, lastFormat), m):
    if m[1] != "": m[1]
    else:
      case m[0]
      of "YY":
        let y = jsString(date.getFullYear)
        if y.len > 2: y[^2 .. ^1] else: y
      of "YYYY": pad(date.getFullYear, 4)
      of "M": jsString(date.getMonth + 1)
      of "MM": pad(date.getMonth + 1, 2)
      of "MMM": MONTHS[int(date.getMonth)][0 ..< 3]
      of "MMMM": MONTHS[int(date.getMonth)]
      of "D": jsString(date.getDate)
      of "DD": pad(date.getDate, 2)
      of "d": jsString(date.getDay)
      of "dd": WEEKDAYS[int(date.getDay)][0 ..< 2]
      of "ddd": WEEKDAYS[int(date.getDay)][0 ..< 3]
      of "dddd": WEEKDAYS[int(date.getDay)]
      of "H": jsString(hours)
      of "HH": pad(hours, 2)
      of "h": jsString(h12)
      of "hh": pad(h12, 2)
      of "a": (if hours < 12: "am" else: "pm")
      of "A": (if hours < 12: "AM" else: "PM")
      of "m": jsString(date.getMinutes)
      of "mm": pad(date.getMinutes, 2)
      of "s": jsString(date.getSeconds)
      of "ss": pad(date.getSeconds, 2)
      of "SSS": pad(date.getMilliseconds, 3)
      of "Z": zone(date)
      else: zone(date).replace(":", "")
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

  Reader = proc (f: var Fields, input: string): bool {.noSideEffect.}

  Step = object
    literal: string
    isReader: bool
    re: JsRegExp
    read: Reader

func unset(): Fields =
  Fields(year: NaN, month: NaN, day: NaN, hours: NaN, minutes: NaN, seconds: NaN, milliseconds: NaN,
         week: NaN, offset: NaN, afternoon: -1)

func truthy(x: float): bool = x == x and x != 0


const RE_TOKENS =
  jsre"/(\[[^[]*\])|([-_:/.,()\s]+)|(A|a|Q|YYYY|YY?|ww?|MM?M?M?|Do|DD?|hh?|HH?|mm?|ss?|S{1,3}|z|ZZ?)/g"
const RE_LITERAL = jsre"/\[[^\]]+]/g"
const MATCH_1 = jsre"/\d/"
const MATCH_2 = jsre"/\d\d/"
const MATCH_3 = jsre"/\d{3}/"
const MATCH_4 = jsre"/\d{4}/"
const MATCH_1_TO_2 = jsre"/\d\d?/"
const MATCH_SIGNED = jsre"/[+-]?\d+/"
const MATCH_OFFSET = jsre"/[+-]\d\d:?(\d\d)?|Z/"
const MATCH_WORD = jsre"/\d*[^-_:/,()\s\d]+/"

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
  let parts = input.match(jsre"/([+-]|\d\d)/g")
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
  let digits = jsre"/\d+/".exec(input)
  if not digits.found: return false
  # dayjs keeps the digits as a string here, so even "0" counts as a day having been given.
  f.day = num(digits[0])
  f.dayGiven = true
  for k in 1 .. 31:
    if ordinal(float(k)) == input: f.day = float(k)
  true

func step(re: JsRegExp, read: Reader): Step = Step(isReader: true, re: re, read: read)

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

var lastCompiled: tuple[temp: string, steps: Option[seq[Step]], valid: bool]

proc compileNew(temp: string): Option[seq[Step]] =
  # dayjs expands localized tokens through a locale table the English locale does not have, and fails.
  if jsre"/[Ll]/".test(temp.replace(RE_LITERAL, "")): return none(seq[Step])
  let tokens = temp.match(RE_TOKENS)
  if tokens.len == 0: return none(seq[Step])
  var steps: seq[Step]
  for token in tokens:
    let reader = readerFor(token)
    steps.add(if reader.isSome: reader.get else: Step(literal: token.replace(jsre"/^\[|\]$/g", "")))
  some(steps)

proc compile(temp: string): Option[seq[Step]] =
  ## dayjs reads the format again for every date; the steps depend on the format alone, so the
  ## port keeps those of the last one (a chart parses all its dates with one format).
  if not lastCompiled.valid or lastCompiled.temp != temp:
    lastCompiled = (temp, compileNew(temp), true)
  lastCompiled.steps

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
    let m = step.re.exec(slice)
    if not m.found: return NaN
    let matched = m[0]
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
