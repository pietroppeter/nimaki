## port-of: src/diagrams/gantt/axis.ts
## port-status: draft
##
## Time axis support, following d3-time and d3-time-format (English locale, local time), which Mermaid uses:
## the `axisFormat` specifiers, tick intervals with d3's `every` rule, and its choice of automatic ticks.
##
## Port notes: a calendar's `floor` and `offset` change a date in place, as in Pele, through `var`.
import std/[options, strutils]
from std/math import floor, `mod`
import ../../js
import ../../jsmath
import ../../jsdate
import dates
import ../../jsregex

const
  SECOND = 1000.0
  MINUTE = 60 * SECOND
  HOUR = 60 * MINUTE
  DAY = 24 * HOUR
  WEEK = 7 * DAY
  MONTH = 30 * DAY
  YEAR = 365 * DAY

type
  TickUnit* = string  ## 'millisecond' | 'second' | 'minute' | 'hour' | 'day' | 'week' | 'month' | 'year'

  Calendar = object
    floor: proc (d: var JsDate) {.noSideEffect.}
    offset: proc (d: var JsDate, step: float) {.noSideEffect.}
    field: proc (d: JsDate): float {.noSideEffect.}
      ## The value d3 tests against a step: a tick falls where it is a multiple of the step. nil when none.
    cycle: float
      ## How many values `field` cycles through, which bounds how far apart filtered ticks can be.
    ms: float

func finite(x: float): bool = x == x and x != Inf and x != -Inf

func startOfDay(d: var JsDate) = d = d.setHours(0, 0, 0, 0)

func weekCalendar(weekStart: float): Calendar =
  Calendar(
    floor: proc (d: var JsDate) =
      d = d.setDate(d.getDate - ((d.getDay + 7 - weekStart) mod 7))
      startOfDay(d),
    offset: proc (d: var JsDate, step: float) = d = d.setDate(d.getDate + step * 7),
    cycle: Inf, ms: WEEK)

func calendar(unit: TickUnit): Calendar =
  case unit
  of "millisecond":
    Calendar(floor: proc (d: var JsDate) = discard,
             offset: proc (d: var JsDate, step: float) = d = fromTime(d + step), cycle: Inf, ms: 1)
  of "second":
    Calendar(floor: proc (d: var JsDate) = d = fromTime(d - d.getMilliseconds),
             offset: proc (d: var JsDate, step: float) = d = fromTime(d + step * SECOND),
             field: proc (d: JsDate): float = d.getSeconds, cycle: 60, ms: SECOND)
  of "minute":
    Calendar(floor: proc (d: var JsDate) = d = fromTime(d - d.getMilliseconds - d.getSeconds * SECOND),
             offset: proc (d: var JsDate, step: float) = d = fromTime(d + step * MINUTE),
             field: proc (d: JsDate): float = d.getMinutes, cycle: 60, ms: MINUTE)
  of "hour":
    Calendar(floor: proc (d: var JsDate) =
               d = fromTime(d - d.getMilliseconds - d.getSeconds * SECOND - d.getMinutes * MINUTE),
             offset: proc (d: var JsDate, step: float) = d = fromTime(d + step * HOUR),
             field: proc (d: JsDate): float = d.getHours, cycle: 24, ms: HOUR)
  of "day":
    Calendar(floor: startOfDay,
             offset: proc (d: var JsDate, step: float) = d = d.setDate(d.getDate + step),
             field: proc (d: JsDate): float = d.getDate - 1, cycle: 31, ms: DAY)
  of "month":
    Calendar(floor: proc (d: var JsDate) =
               d = d.setDate(1)
               startOfDay(d),
             offset: proc (d: var JsDate, step: float) = d = d.setMonth(d.getMonth + step),
             field: proc (d: JsDate): float = d.getMonth, cycle: 12, ms: MONTH)
  else:
    Calendar(floor: proc (d: var JsDate) =
               d = d.setMonth(0, 1)
               startOfDay(d),
             offset: proc (d: var JsDate, step: float) = d = d.setFullYear(d.getFullYear + step),
             cycle: Inf, ms: YEAR)

func span(start, stop: JsDate, unit: float): float =
  ## Whole units between two floored dates, discounting a change of UTC offset between them.
  floor((stop - start - (stop.getTimezoneOffset - start.getTimezoneOffset) * MINUTE) / unit)

func jsMod(a, b: float): float =
  ## ((a % b) + b) % b
  ((a mod b) + b) mod b

func every(unit: TickUnit, step: float, weekStart: float): Calendar =
  ## The interval d3's `unit.every(step)` gives.
  let base = if unit == "week": weekCalendar(weekStart) else: calendar(unit)
  if step <= 1: return base
  if unit == "millisecond":
    result = base
    result.floor = proc (d: var JsDate) = d = fromTime(floor(d / step) * step)
    result.offset = proc (d: var JsDate, n: float) = d = fromTime(d + n * step)
    return
  if unit == "year":
    result = base
    result.floor = proc (d: var JsDate) =
      d = d.setFullYear(floor(d.getFullYear / step) * step)
      base.floor(d)
    result.offset = proc (d: var JsDate, n: float) = d = d.setFullYear(d.getFullYear + n * step)
    return
  if unit == "week":
    var epoch = fromTime(0)
    base.floor(epoch)
    let e = epoch
    result = base
    result.floor = proc (d: var JsDate) =
      base.floor(d)
      base.offset(d, -jsMod(span(e, d, WEEK), step))
    result.offset = proc (d: var JsDate, n: float) = base.offset(d, n * step)
    return
  let field = base.field
  let test = proc (d: JsDate): bool {.noSideEffect.} = field(d) mod step == 0
  result = base
  result.floor = proc (d: var JsDate) =
    # Date overflow makes field(d) NaN, which can never match the interval.
    base.floor(d)
    while finite(d) and not test(d):
      d = fromTime(d - 1)
      base.floor(d)
  result.offset = proc (d: var JsDate, n: float) =
    var i = 0.0
    while i < n and finite(d):
      while true:
        base.offset(d, 1)
        if not (finite(d) and not test(d)): break
      i += 1

func range(calendar: Calendar, start, stop: float, limit: float): Option[seq[float]] =
  ## Ticks from start to stop inclusive, or none when there would be more than `limit`.
  var d = fromTime(start - 1)
  calendar.floor(d)
  calendar.offset(d, 1)
  calendar.floor(d)
  var output: seq[float]
  var previous = -Inf
  while d <= stop and d > previous:
    if float(output.len) >= limit: return none(seq[float])
    previous = d
    output.add previous
    calendar.offset(d, 1)
    calendar.floor(d)
  some(output)

func tickStep(start, stop, count: float): float =
  let step = (stop - start) / max(0.0, count)
  let power = floor(log10(step))
  let error = step / pow(10, power)
  let factor = if error >= sqrt(50.0): 10.0 elif error >= sqrt(10.0): 5.0 elif error >= 1.4142135623730951: 2.0 else: 1.0
  pow(10, power) * factor

const AUTO: array[18, (string, float, float)] = [
  ("second", 1.0, SECOND),
  ("second", 5.0, 5 * SECOND),
  ("second", 15.0, 15 * SECOND),
  ("second", 30.0, 30 * SECOND),
  ("minute", 1.0, MINUTE),
  ("minute", 5.0, 5 * MINUTE),
  ("minute", 15.0, 15 * MINUTE),
  ("minute", 30.0, 30 * MINUTE),
  ("hour", 1.0, HOUR),
  ("hour", 3.0, 3 * HOUR),
  ("hour", 6.0, 6 * HOUR),
  ("hour", 12.0, 12 * HOUR),
  ("day", 1.0, DAY),
  ("day", 2.0, 2 * DAY),
  ("week", 1.0, WEEK),
  ("month", 1.0, MONTH),
  ("month", 3.0, 3 * MONTH),
  ("year", 1.0, YEAR),
]

func autoTicks*(start, stop, count: float): seq[float] =
  ## About `count` ticks at round times, chosen the way d3's time scale chooses them.
  let target = (stop - start) / count
  var i = 0
  while i < AUTO.len and AUTO[i][2] <= target: inc i
  var cal: Calendar
  if i == AUTO.len:
    cal = every("year", max(1.0, tickStep(start / YEAR, stop / YEAR, count)), 0)
  elif i == 0:
    cal = every("millisecond", max(tickStep(start, stop, count), 1.0), 0)
  else:
    let k = if target / AUTO[i - 1][2] < AUTO[i][2] / target: i - 1 else: i
    cal = every(AUTO[k][0], AUTO[k][1], 0)
  range(cal, start, stop, 4 * count + 8).get(@[])

const RE_INTERVAL = jsre"/^([1-9]\d*)(millisecond|second|minute|hour|day|week|month)$/"
const WEEK_STARTS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

func intervalTicks*(interval: string, weekday: string, start, stop: float, limit: float): Option[seq[float]] =
  ## Ticks for a `tickInterval` such as `1week`, or none when it is not one or asks for more than `limit`.
  let m = RE_INTERVAL.exec(interval)
  if not m.found: return none(seq[float])
  let step = jsToNumber(m[1])
  let unit = m[2]
  let cal = every(unit, step, float(max(0, WEEK_STARTS.find(weekday))))
  if (stop - start) / (min(step, cal.cycle) * cal.ms) > limit: return none(seq[float])
  range(cal, start, stop, limit)

func pad(value: float, fill: string, width: int): string =
  let sign = if value < 0: "-" else: ""
  let digits = jsString(if sign != "": -value else: value)
  sign & (if digits.len < width: fill.repeat(width - digits.len) & digits else: digits)

func floored(date: JsDate, cal: Calendar): JsDate =
  result = date
  cal.floor(result)

func weekOfYear(date: JsDate, weekStart: float): float =
  ## Weeks since the last `weekStart` day before the year began, which is d3's %U and %W.
  let week = weekCalendar(weekStart)
  let yearStart = floored(date, calendar("year"))
  span(floored(fromTime(yearStart - 1), week), floored(date, week), WEEK)

func isoThursday(date: JsDate): JsDate =
  ## The Thursday that decides which ISO week and ISO year a date belongs to.
  let thursday = weekCalendar(4)
  let day = date.getDay
  let late = day >= 4 or day == 0
  result = floored(if late: date else: fromTime(date - 1), thursday)
  if not late:
    thursday.offset(result, 1)
    thursday.floor(result)

func directive(c: string, d: JsDate, p: string): string

func timeFormat*(specifier: string, date: JsDate): string =
  ## Formats a date with a d3 time format specifier such as `%Y-%m-%d`.
  var output = ""
  var start = 0
  let n = specifier.len
  var i = 0
  while i < n:
    if specifier[i] != '%':
      inc i
      continue
    output.add specifier[start ..< i]
    inc i
    var c = if i < n: specifier[i ..< i + codePointAt(specifier, i).size] else: ""
    var fill: string
    if c == "-" or c == "_" or c == "0":
      fill = (if c == "-": "" elif c == "_": " " else: "0")
      inc i
      c = if i < n: specifier[i ..< i + codePointAt(specifier, i).size] else: ""
    else:
      fill = if c == "e": " " else: "0"
    output.add directive(c, date, fill)
    i += max(c.len, 1)
    start = min(i, n)
  output & specifier[start ..< n]

func directive(c: string, d: JsDate, p: string): string =
  case c
  of "a": WEEKDAYS[int(d.getDay)][0 ..< 3]
  of "A": WEEKDAYS[int(d.getDay)]
  of "b": MONTHS[int(d.getMonth)][0 ..< 3]
  of "B": MONTHS[int(d.getMonth)]
  of "c": timeFormat("%x, %X", d)
  of "d", "e": pad(d.getDate, p, 2)
  of "f": pad(d.getMilliseconds, p, 3) & "000"
  of "g": pad(isoThursday(d).getFullYear mod 100, p, 2)
  of "G": pad(isoThursday(d).getFullYear mod 10000, p, 4)
  of "H": pad(d.getHours, p, 2)
  of "I": pad((let h = d.getHours mod 12; if h == 0 or h != h: (if h == 0: 12.0 else: 12.0) else: h), p, 2)
  of "j": pad(1 + span(floored(d, calendar("year")), floored(d, calendar("day")), DAY), p, 3)
  of "L": pad(d.getMilliseconds, p, 3)
  of "m": pad(d.getMonth + 1, p, 2)
  of "M": pad(d.getMinutes, p, 2)
  of "p": (if d.getHours >= 12: "PM" else: "AM")
  of "q": jsString(1 + floor(d.getMonth / 3))
  of "Q": jsString(d)
  of "s": jsString(floor(d / 1000))
  of "S": pad(d.getSeconds, p, 2)
  of "u": jsString(if d.getDay == 0 or d.getDay != d.getDay: 7.0 else: d.getDay)
  of "U": pad(weekOfYear(d, 0), p, 2)
  of "V":
    let thursday = isoThursday(d)
    let yearStart = floored(thursday, calendar("year"))
    let first = floored(yearStart, weekCalendar(4))
    pad(span(first, thursday, WEEK) + (if yearStart.getDay == 4: 1.0 else: 0.0), p, 2)
  of "w": jsString(d.getDay)
  of "W": pad(weekOfYear(d, 1), p, 2)
  of "x": timeFormat("%-m/%-d/%Y", d)
  of "X": timeFormat("%-I:%M:%S %p", d)
  of "y": pad(d.getFullYear mod 100, p, 2)
  of "Y": pad(d.getFullYear mod 10000, p, 4)
  of "Z":
    let z = d.getTimezoneOffset
    let a = abs(z)
    (if z > 0: "-" else: "+") & pad(floor(a / 60), "0", 2) & pad(a mod 60, "0", 2)
  of "%": "%"
  else: c
