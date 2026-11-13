## devlog: 13 Nov 2026 B | Dates on a line: gantt charts | nimaki draws Mermaid's gantt charts byte for byte as Pele does, which meant bringing JavaScript's dates to Nim first: its calendar, its UTC time values and V8's forgiving date parser.
## kind: port
import std/[strformat, strutils, json, tables, options]
import nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/jsdate
import nimaki/diagrams/gantt/dates

nbInit
nb.usePost()

let difftest = parseFile(docsDir / "data" / "difftest.json")
var cases = initTable[string, int]()
for r in difftest["types"]: cases[r["type"].getStr] = r["cases"].getInt
let fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]

nbText: &"""
## The findings, first

- **Gantt charts are done.** The {cases["gantt"]} corpus cases come out of nimaki identical to
  Pele's, byte for byte, and so do {fuzz["gantt"]["cases"].getInt.thousands} generated charts
  that CI now checks on every pull request.
- **Most of the work is dates.** A gantt chart is a list of tasks placed on a time axis. To
  place them as Pele does, the port needs JavaScript's `Date` (its calendar arithmetic and its
  parser), the parts of the dayjs library Mermaid uses to read dates in a chart's format, and
  the parts of d3 that choose and write the ticks of a time axis. Pele has its own copies of
  the last two. The port adds the first, as `jsdate.nim`.
- **Local time is UTC.** The referee runs Pele with `TZ=UTC`, so the port's local time is UTC
  too. That choice is a new decision record, 0012.
- **Node's date parser, ported.** When a date does not fit the chart's format, Mermaid gives it
  to `new Date(text)`. That is V8's parser in Node, and the port follows it rule by rule. A test
  checks it against Node on about 3,000 strings.
- **Ten files, about 2,700 lines** (nine for gantt, one for dates). They matched on the first run.

## What a gantt chart is

A *gantt chart* plans work over time. Each *task* is a bar that starts at a date and lasts for a
while. Tasks are grouped in *sections*. A task can start *after* another one ends, and days can be
*excluded*, so that a five-day task skips a weekend. Mermaid writes one like this:
"""

let ganttText = """gantt
  title A small plan
  dateFormat YYYY-MM-DD
  excludes weekends
  section Design
    Research      :done, r1, 2025-12-22, 4d
    Sketches      :active, s1, after r1, 3d
  section Build
    Write code    :crit, c1, after s1, 5d
    Review        :milestone, after c1, 0d
"""

nbText: &"""
```mermaid
{ganttText.strip}
```
"""

nbCode:
  # The referee's fixed now, 1 January 2026, so that the today line and Pele's agree.
  let ganttSvg = render(ganttText, RenderOptions(now: fixedNow)).svg
  echo "identical to Pele's: ", ganttSvg == peleSvg(ganttText)

nbSvg ganttSvg, "A small plan, drawn by nimaki; Pele draws the same bytes. The grey bands are the excluded weekends, and the line is today, 1 January 2026, the fixed now of the referee."

nbText: """
## Scheduling: up to eleven passes

The parser reads each task line into raw text: an optional id, a start, and an end or a duration.
Then `getTasks` *schedules* the tasks, turning that text into dates. A start can be a date, `after`
some tasks (the latest end among them), or nothing at all (the end of the task before). An end
can be a date, `until` some tasks, or a duration such as `3d` or `1w`. A task may refer to one
defined below it, so Mermaid schedules every task again and again, up to eleven passes, until
all are resolved. When days are excluded, the end moves out by one day for each excluded day the
task covers.

## Reading a date: strictly, then loosely

A date is read in the chart's `dateFormat` (`YYYY-MM-DD` by default) by dayjs, *strictly*. dayjs
parses the text with the format, then writes the parsed date back in the format, and accepts the
date only if it gets the same text again. So 30 February is not a date, because it writes back as
2 March. Pele has its own copy of the parts of dayjs Mermaid needs, with the same quirks. The
port copies Pele's copy:
"""

nbCode:
  let now = fixedNow
  for text in ["2026-02-28", "2026-02-30", "2026-2-28"]:
    let parsed = parseStrict(text, "YYYY-MM-DD", fromTime(now))
    echo text.alignLeft(12), if parsed.isSome: isoDate(parsed.get) else: "not a date in this format"

nbText: """
A start that is not a date in the format gets a second chance, from JavaScript's own parser,
`new Date(text)`. The language only fixes what that does for ISO 8601 text such as
`2026-01-05T10:00Z`; every other form is up to the engine. Node runs V8, and V8 reads a lot: month
names, slashes, `PM`, time zone names. It also has quirks, such as giving the year 2001 to a date
written without one. The port follows V8's parser, its ISO reading first and then its legacy one:
"""

nbCode:
  for text in ["2026-01-05", "Jan 5, 2026", "1/5/2026 10:00 PM", "5 January", "Monday"]:
    let d = parseDate(text)
    echo text.alignLeft(20), if d.isValid: isoDate(d) & " " & $int(d.getHours) & "h" else: "Invalid Date"

nbText: """
Underneath, a date is what JavaScript keeps inside a `Date`: one number, the milliseconds since
1 January 1970, UTC. Years, months and days are computed from that number with the formulas of
the ECMAScript specification, and back again, including how the setters overflow: day 32 of
January is 1 February. In Nim that is a `float` named `JsDate`. A setter returns the new value
instead of changing the date in place.

## The axis

The time axis is d3's. When the chart does not set a `tickInterval`, d3 picks the tick step from a
ladder of round durations (one second, five seconds... a day, a week, a month, a year), the one
nearest to the span divided by about ten. Then it walks the calendar from the first tick to the
last. Each label is written with a d3 format such as `%Y-%m-%d` or `%b %d`. A narrow host gets a
narrower chart, with fewer ticks:
"""

nbCode:
  let narrow = render(ganttText, RenderOptions(maxWidth: some(390.0), now: fixedNow))
  echo "width ", narrow.width, ", identical to Pele's: ", narrow.svg == peleSvg(ganttText, %*{"maxWidth": 390})

nbSvg narrow.svg, "The same plan for a phone."

nbNote """
- JavaScript's `Date` is `src/nimaki/jsdate.nim`, a new file that ports no Pele file: it follows
  the ECMAScript specification and V8's `dateparser`. Decision 0012 records why local time is UTC.
- Pele keeps a task's undefined start or end as `undefined`. Here a date is NaN together with a
  flag for whether it is set.
- A `RenderOptions.now` of 0 means "now", as everywhere in nimaki, where Pele would read it as
  1970.
""", nkNim, "In the port"

nbNote &"""
- The {cases["gantt"]} corpus cases: identical.
- Generated charts before merging: 2,000 cases, then 5,000 on each of four seeds, all identical.
  The generator writes dates in a dozen formats, `after` and `until`, durations, exclusions,
  tick intervals, axis formats and broken lines. About two in three draw; the rest check
  Mermaid's error messages. CI runs {fuzz["gantt"]["cases"].getInt.thousands} on every pull request.
- `tests/test_jsdate.nim`: `new Date(text)` on about 3,000 strings, and the calendar setters on
  2,000 dates, identical to Node.
""", nkDone, "Checked"

nbNote """
- Pele's gantt tests (`tests/gantt/`) are not ported. The corpus and the fuzzer check the
  model through the drawing.
- `parseDate` is checked on generated strings, not on every rule of V8's parser one by one.
- Every file is `draft` until a second reading against the TypeScript.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- **Gantt is done** on the [coverage map](../../coverage/) and the [roadmap](../../roadmap/).
- **Dates are available** to any later type that needs them, through `jsdate.nim`.

## Sources

- Pele at the pin: [`src/diagrams/gantt/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/src/diagrams/gantt),
  read for this step.
- ECMAScript's [Date objects](https://tc39.es/ecma262/#sec-date-objects), whose algorithms
  `jsdate.nim` follows.
- V8's date parser, [`src/date/dateparser-inl.h`](https://github.com/v8/v8/blob/main/src/date/dateparser-inl.h),
  followed as it was remembered, then checked against Node (`tests/test_jsdate.nim`). It was not
  read for this step.
- The code of this step: [`src/nimaki/diagrams/gantt/`](https://github.com/pietroppeter/nimaki/tree/main/src/nimaki/diagrams/gantt),
  [`src/nimaki/jsdate.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/jsdate.nim),
  [`tools/fuzz.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/fuzz.nim).
"""

nbSave
