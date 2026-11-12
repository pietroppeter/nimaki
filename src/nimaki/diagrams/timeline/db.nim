## port-of: src/diagrams/timeline/db.ts
## port-status: draft
import ../../errors
import ../../js

type
  TimelinePeriod* = object
    text*: string
    events*: seq[string]
    section*: string
      ## Name of the section in force when the period was declared, "" before the first one.
    sectionIndex*: int
      ## Index into `sections` of that section, -1 before the first one.

  TimelineDb* = ref object of RootObj
    ## Pele's TimelineDb, which is also the TimelineModel.
    title*: string       ## "" for undefined
    accTitle*: string    ## "" for undefined
    accDescr*: string    ## "" for undefined
    direction*: string   ## "LR" or "TD"
    sections*: seq[string]
    periods*: seq[TimelinePeriod]
    currentSection: string

  TimelineModel* = TimelineDb

proc newTimelineDb*(): TimelineDb = TimelineDb(direction: "LR")

proc getCommonDb*(db: TimelineDb): TimelineDb =
  ## The grammar reaches the title and accessibility setters through this.
  db

proc setDiagramTitle*(db: TimelineDb, text: string) = db.title = text

proc setAccTitle*(db: TimelineDb, text: string) =
  ## text.replace(/^\s+/g, '')
  db.accTitle = jsTrimStart(text)

proc setAccDescription*(db: TimelineDb, text: string) =
  ## text.replace(/\n\s+/g, '\n')
  var output = ""
  var i = 0
  while i < text.len:
    if text[i] == '\n' and spaceLenAt(text, i + 1) > 0:
      output.add '\n'
      i += 1
      while true:
        let n = spaceLenAt(text, i)
        if n == 0: break
        i += n
      continue
    output.add text[i]
    inc i
  db.accDescr = output

proc setDirection*(db: TimelineDb, direction: string) = db.direction = direction

proc addSection*(db: TimelineDb, text: string) =
  db.currentSection = text
  db.sections.add text

proc addTask*(db: TimelineDb, period: string, length = 0, event = "") =
  db.periods.add TimelinePeriod(
    text: period,
    events: (if event != "": @[event] else: @[]),
    section: db.currentSection,
    sectionIndex: db.sections.len - 1)

proc addEvent*(db: TimelineDb, event: string) =
  # Mermaid fails here too, with a TypeError.
  if db.periods.len == 0:
    raise newPeleError("An event needs a time period before it.", "semantic", ErrorInfo(diagramType: "timeline"))
  db.periods[^1].events.add event
