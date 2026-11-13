## port-of: src/diagrams/gantt/db.ts
## port-status: draft
##
## Port notes: the `warn` option of Pele's database is not ported (nothing in a render reads it).
## Options' `now` of 0 stands for "not given", as everywhere in nimaki.
import std/[options, sets, strutils, tables, times, unicode]
from std/math import floor
import ../../errors
import ../../js
import ../../jsdate
import ../../util/url
import dates, types

export types

const
  WORK_LIMIT = 4e8
    ## Scheduling walks tasks day by day and parses dates with a format the diagram supplies. This bounds
    ## the total, in rough character operations, so a hostile diagram fails instead of hanging.
  DAY_STEP = 400
  DATED_STEP = 200
  FORMAT_STEP = 400

proc clock*(now: float): float =
  ## The one place the current time is read.
  if now != 0 and now == now and now != Inf and now != -Inf: now else: floor(epochTime() * 1000)

func isNumericFormat(s: string): bool =
  ## /^[YMDHhmsSZXx\-/.:, T]*$/
  for c in s:
    if c notin {'Y', 'M', 'D', 'H', 'h', 'm', 's', 'S', 'Z', 'X', 'x', '-', '/', '.', ':', ',', ' ', 'T'}: return false
  true

func allDigits(s: string): bool =
  ## /^\d+$/
  if s.len == 0: return false
  for c in s:
    if c notin {'0'..'9'}: return false
  true

proc parseDuration*(str: string): (float, Unit) =
  ## /^(\d+(?:\.\d+)?)([Mdhmswy]|ms)$/ on the trimmed text
  let s = jsTrim(str)
  var i = 0
  while i < s.len and s[i] in {'0'..'9'}: inc i
  if i == 0: return (NaN, "ms")
  var j = i
  if j < s.len and s[j] == '.':
    var k = j + 1
    while k < s.len and s[k] in {'0'..'9'}: inc k
    if k > j + 1: j = k
  let unit = s[j .. ^1]
  if unit notin ["M", "d", "h", "m", "s", "w", "y", "ms"]: return (NaN, "ms")
  (jsParseFloat(s[0 ..< j]), unit)

func splitTokens(txt: string): seq[string] =
  ## txt.split(/[\s,]+/)
  var cur = ""
  var i = 0
  var sep = false
  while i < txt.len:
    let n = spaceLenAt(txt, i)
    if n > 0 or txt[i] == ',':
      if not sep:
        result.add cur
        cur = ""
        sep = true
      i += max(n, 1)
    else:
      sep = false
      cur.add txt[i]
      inc i
  result.add cur

proc mergeTokens(existing: seq[string], txt: string): seq[string] =
  result = existing
  for token in splitTokens(unicode.toLower(txt)):
    if token != "" and token notin result: result.add token

type
  GanttDb* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    dateFormat*: string
    axisFormat*: string
    tickInterval*: string                  ## "" for undefined
    todayMarker*: string
    includes*, excludes*: seq[string]
    inclusiveEndDates*: bool
    topAxis*: bool
    displayMode*: string
    weekday*: string                       ## "" for undefined
    weekend*: string
    sections*: seq[string]
    links*: OrderedTable[string, string]
    tasks*: seq[GanttTask]

    byId: Table[string, GanttTask]
    currentSection: string
    taskCount: int
    lastOrder: int
    lastTaskId: string
    hasLastTask: bool
    now: float
    work: float
    includeSet, excludeSet: HashSet[string]
    excludedDays: array[7, bool]
    datedTokens: bool

proc newGanttDb*(): GanttDb =
  GanttDb(weekend: "saturday")

proc semantic(message: string): ref PeleError = newPeleError(message, "semantic", "gantt")

proc setDateFormat*(db: GanttDb, txt: string) = db.dateFormat = txt
proc enableInclusiveEndDates*(db: GanttDb) = db.inclusiveEndDates = true
proc enableTopAxis*(db: GanttDb) =
  ## Mermaid's grammar calls a method its database does not define (`TopAxis`), so `topAxis` crashes there.
  db.topAxis = true
proc setAxisFormat*(db: GanttDb, txt: string) = db.axisFormat = txt
proc setTickInterval*(db: GanttDb, txt: string) = db.tickInterval = txt
proc setTodayMarker*(db: GanttDb, txt: string) = db.todayMarker = txt
proc setIncludes*(db: GanttDb, txt: string) = db.includes = mergeTokens(db.includes, txt)
proc setExcludes*(db: GanttDb, txt: string) = db.excludes = mergeTokens(db.excludes, txt)
proc setWeekday*(db: GanttDb, txt: string) = db.weekday = txt
proc setWeekend*(db: GanttDb, startDay: string) = db.weekend = startDay
proc setDiagramTitle*(db: GanttDb, txt: string) = db.title = txt
proc setAccTitle*(db: GanttDb, txt: string) = db.accTitle = jsTrimStart(txt)

func dropBreakSpaces(text: string): string =
  ## text.replace(/\n\s+/g, '\n')
  var i = 0
  while i < text.len:
    if text[i] == '\n':
      result.add '\n'
      inc i
      while i < text.len:
        let n = spaceLenAt(text, i)
        if n == 0: break
        i += n
      continue
    result.add text[i]
    inc i

proc setAccDescription*(db: GanttDb, txt: string) = db.accDescr = dropBreakSpaces(txt)

proc addSection*(db: GanttDb, txt: string) =
  db.currentSection = txt
  db.sections.add txt

func tagOf(s: string): string =
  ## /^\s*(active|done|crit|milestone|vert)\s*$/: the tag, or ""
  let t = jsTrim(s)
  # jsTrim drops what \s matches at both ends, so the rest must be the tag itself
  if t in ["active", "done", "crit", "milestone", "vert"]: t else: ""

proc addTask*(db: GanttDb, descr: string, dataStr: string) =
  var data = (if dataStr.startsWith(":"): dataStr[1 .. ^1] else: dataStr).split(',')
  let task = GanttTask(task: descr, section: db.currentSection, order: -1,
                       prevTaskId: db.lastTaskId, hasPrev: db.hasLastTask,
                       raw: GanttRaw(data: dataStr))
  while data.len > 0:
    let tag = tagOf(data[0])
    if tag == "": break
    case tag
    of "active": task.active = true
    of "done": task.done = true
    of "crit": task.crit = true
    of "milestone": task.milestone = true
    else: task.vert = true
    data.delete(0)
  # Mermaid fails with a TypeError on both of these.
  if data.len == 0:
    raise semantic("Task \"" & jsTrim(descr) & "\" needs a duration or an end date.")
  if data.len > 3:
    raise semantic("Task \"" & jsTrim(descr) & "\" has too many fields. A task takes an id, a start, and an end or duration.")
  for i in 0 ..< data.len: data[i] = jsTrim(data[i])
  if data.len == 3:
    task.id = data[0]
  else:
    inc db.taskCount
    task.id = "task" & $db.taskCount
  if data.len > 1:
    task.raw.start = data[^2]
    task.raw.hasStart = true
  task.raw.stop = data[^1]
  if not task.vert:
    task.order = db.lastOrder
    inc db.lastOrder
  db.tasks.add task
  db.lastTaskId = task.id
  db.hasLastTask = true
  db.byId[task.id] = task

proc setClass*(db: GanttDb, ids: string, className: string) =
  for id in ids.split(','):
    if id in db.byId: db.byId[id].classes.add className

proc setLink*(db: GanttDb, ids: string, link: string) =
  let href = safeUrl(link)
  for id in ids.split(','):
    if id in db.byId: db.links[id] = href
  db.setClass(ids, "clickable")

proc setClickEvent*(db: GanttDb, ids: string) =
  ## Callbacks are recognized and never run; the task is only marked clickable, as in Mermaid.
  db.setClass(ids, "clickable")

proc spend(db: GanttDb, units: float) =
  db.work += units
  if db.work > WORK_LIMIT:
    raise newPeleError("The gantt chart takes too much work to schedule.", "limit", "gantt")

proc isInvalidDate*(db: GanttDb, date: JsDate): bool =
  ## Whether a day is excluded. A day matches a token by its weekday name, by its date as YYYY-MM-DD,
  ## or by its date written in the chart's own format.
  let weekday = db.excludedDays[int(date.getDay)]
  if not db.datedTokens: return weekday
  let temp = jsTrim(db.dateFormat)
  let dateOnly = isoDate(date)
  var formatted = some(dateOnly)
  db.spend(DATED_STEP)
  if temp != "YYYY-MM-DD":
    db.spend(float(FORMAT_STEP + utf16Len(temp) * 8))
    formatted = format(date, temp)
  proc listed(s: HashSet[string]): bool = dateOnly in s or (formatted.isSome and formatted.get in s)
  if listed(db.includeSet): return false
  weekday or listed(db.excludeSet)

proc parse(db: GanttDb, str, temp: string): Option[JsDate] =
  db.spend(float((utf16Len(temp) + 1) * (utf16Len(str) + 1)))
  parseStrict(str, temp, fromTime(db.now))

proc today(db: GanttDb): JsDate = fromTime(db.now).setHours(0, 0, 0, 0)

proc references(db: GanttDb, list: string): seq[GanttTask] =
  for id in list.split(' '):
    if id == "": continue
    if id in db.byId: result.add db.byId[id]

func referenceList(str, keyword: string): (bool, string) =
  ## /^keyword\s+([\d\w- ]+)/: the list after the keyword
  if not str.startsWith(keyword): return (false, "")
  var i = keyword.len
  let blank = i
  while i < str.len:
    let n = spaceLenAt(str, i)
    if n == 0: break
    i += n
  if i == blank: return (false, "")
  # \s+ gives back blanks when the list would otherwise be empty; a space is in the list anyway
  var j = i
  while j < str.len and (isWordChar(str[j]) or str[j] in {'-', ' '}): inc j
  if j > i: return (true, str[i ..< j])
  # Otherwise \s+ gives back its run down to the last space in it, which the list then is.
  var k = i - 1
  while k > blank and str[k] != ' ': dec k
  if k > blank: return (true, " ")
  (false, "")

proc getStartDate(db: GanttDb, raw: string): (bool, JsDate) =
  let str = jsTrim(raw)
  let temp = jsTrim(db.dateFormat)
  if (temp == "x" or temp == "X") and allDigits(str):
    let date = fromTime(jsToNumber(str))
    if not date.isValid: raise semantic("Invalid date:" & str)
    return (true, date)
  let (isAfter, list) = referenceList(str, "after")
  if isAfter:
    var latest: GanttTask = nil
    for task in db.references(list):
      if latest == nil or task.endTime > latest.endTime: latest = task
    if latest == nil: return (true, db.today())
    return (latest.hasEnd, latest.endTime)
  let parsed = db.parse(str, temp)
  if parsed.isSome: return (true, parsed.get)
  # What does not fit the format gets a second chance with the JavaScript date parser, as in Mermaid.
  let date = parseDate(str)
  if not date.isValid or date.getFullYear < -10000 or date.getFullYear > 10000:
    raise semantic("Invalid date:" & str)
  (true, date)

proc getEndDate(db: GanttDb, startTime: JsDate, raw: string): (bool, JsDate) =
  let str = jsTrim(raw)
  let (isUntil, list) = referenceList(str, "until")
  if isUntil:
    var earliest: GanttTask = nil
    for task in db.references(list):
      if earliest == nil or task.startTime < earliest.startTime: earliest = task
    if earliest == nil: return (true, db.today())
    return (earliest.hasStart, earliest.startTime)
  let temp = jsTrim(db.dateFormat)
  let parsed = db.parse(str, temp)
  if parsed.isSome: return (true, if db.inclusiveEndDates: addDays(parsed.get, 1) else: parsed.get)
  let (value, unit) = parseDuration(str)
  if value != value: return (true, startTime)
  let stop = add(startTime, value, unit)
  (true, if stop.isValid: stop else: startTime)

proc checkTaskDates(db: GanttDb, task: GanttTask) =
  ## Pushes the end of a task out by one day for every excluded day it covers.
  if db.excludes.len == 0 or task.manualEndTime: return
  var cursor = addDays(task.startTime, 1)
  var endTime = task.endTime
  let maxEndTime = addDays(endTime, 10000)
  var invalid = false
  var renderEndTime = NaN
  var hasRender = false
  while cursor <= endTime:
    db.spend(DAY_STEP)
    if not invalid:
      renderEndTime = endTime
      hasRender = true
    invalid = db.isInvalidDate(cursor)
    if invalid:
      endTime = endTime.setDate(endTime.getDate + 1)
      if endTime > maxEndTime:
        raise semantic("Failed to find a valid date that was not excluded by `excludes` after 10,000 iterations.")
    cursor = cursor.setDate(cursor.getDate + 1)
  task.endTime = endTime
  task.renderEndTime = renderEndTime
  task.hasRenderEnd = hasRender

proc compileTask(db: GanttDb, task: GanttTask) =
  if not task.raw.hasStart:
    # Mermaid fails with a TypeError when the first task has no start. It starts today here.
    let previous = if task.hasPrev: db.byId.getOrDefault(task.prevTaskId) else: nil
    if previous != nil:
      task.startTime = previous.endTime
      task.hasStart = previous.hasEnd
    else:
      task.startTime = db.today()
      task.hasStart = true
  else:
    let (has, startTime) = db.getStartDate(task.raw.start)
    if has:
      task.startTime = startTime
      task.hasStart = true
  if not task.hasStart: return
  let (hasEnd, endTime) = db.getEndDate(task.startTime, task.raw.stop)
  task.endTime = endTime
  task.hasEnd = hasEnd
  if not hasEnd: return
  task.processed = true
  task.manualEndTime = db.parse(task.raw.stop, "YYYY-MM-DD").isSome
  db.checkTaskDates(task)

proc compileTasks(db: GanttDb): bool =
  result = true
  for task in db.tasks:
    db.compileTask(task)
    result = result and task.processed

proc getTasks*(db: GanttDb, now: float): seq[GanttTask] =
  ## Resolves every task's start and end, from scratch on each call. A task may refer to tasks defined
  ## after it, so, like Mermaid, this makes up to eleven passes, each of which schedules every task again.
  db.now = clock(now)
  db.work = 0
  db.includeSet = toHashSet(db.includes)
  db.excludeSet = toHashSet(db.excludes)
  let weekendStart = if db.weekend == "friday": 5.0 elif db.weekend == "saturday": 6.0 else: NaN
  let weekends = "weekends" in db.excludeSet
  for day in 0 .. 6:
    let iso = float(if day == 0: 7 else: day)
    db.excludedDays[day] = (weekends and (iso == weekendStart or iso == weekendStart + 1)) or
                           WEEKDAYS[day].toLowerAscii in db.excludeSet
  # A date written with only these tokens and separators can never read as a weekday name, so when
  # nothing else is excluded or included there is no need to format each day.
  db.datedTokens = db.includes.len > 0 or not isNumericFormat(jsTrim(db.dateFormat))
  for token in db.excludes:
    if token != "weekends" and token notin ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]:
      db.datedTokens = true
  for task in db.tasks:
    task.hasStart = false
    task.hasEnd = false
    task.startTime = NaN
    task.endTime = NaN
    task.hasRenderEnd = false
    task.processed = false
    task.manualEndTime = false
  var allProcessed = db.compileTasks()
  var i = 0
  while not allProcessed and i < 10:
    allProcessed = db.compileTasks()
    inc i
  db.tasks
