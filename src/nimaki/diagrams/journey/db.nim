## port-of: src/diagrams/journey/db.ts
## port-status: draft
import std/[algorithm, sets, strutils]
import ../../js
import ../../jsregex

type
  JourneyTask* = object
    task*: string
    score*: float
      ## As written: any number, or NaN when the score is not one.
    people*: seq[string]
    section*: string
      ## Name of the section in force when the task was declared, "" before the first one.

  JourneyDb* = ref object of RootObj
    ## Pele's JourneyDb, which is also the JourneyModel.
    title*: string       ## "" for undefined
    accTitle*: string    ## "" for undefined
    accDescr*: string    ## "" for undefined
    sections*: seq[string]
    tasks*: seq[JourneyTask]
    currentSection: string

  JourneyModel* = JourneyDb

proc journeyActors*(tasks: seq[JourneyTask]): seq[string] =
  ## Everyone named on a task, once each, in code unit order.
  var names = initOrderedSet[string]()
  for task in tasks:
    for name in task.people: names.incl name
  for name in names: result.add name
  result.sort(jsCompare)

proc setDiagramTitle*(db: JourneyDb, text: string) = db.title = text

proc setAccTitle*(db: JourneyDb, text: string) =
  ## text.replace(/^\s+/g, '')
  db.accTitle = text.replace(jsre"/^\s+/g", "")

proc setAccDescription*(db: JourneyDb, text: string) =
  db.accDescr = text.replace(jsre"/\n\s+/g", "\n")

proc addSection*(db: JourneyDb, text: string) =
  db.currentSection = text
  db.sections.add text

proc addTask*(db: JourneyDb, task, data: string) =
  ## `data` is the rest of the line from its first colon: `:score` or `:score:actor, actor`.
  let pieces = data[1 .. ^1].split(':')
  var people: seq[string]
  if pieces.len != 1:
    for name in pieces[1].split(','): people.add jsTrim(name)
  db.tasks.add JourneyTask(task: task, score: jsToNumber(pieces[0]), people: people,
                           section: db.currentSection)

proc getActors*(db: JourneyDb): seq[string] = journeyActors(db.tasks)

