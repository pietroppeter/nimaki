## port-of: src/diagrams/gantt/types.ts
## port-status: draft
##
## Port notes: a `Date | undefined` is a `JsDate` and a flag saying whether it is set; an
## undefined string is "".
import ../../jsdate

type
  GanttRaw* = object
    data*: string
    start*: string        ## the start as written
    hasStart*: bool       ## false for undefined
    stop*: string         ## Pele's `end`

  GanttTask* = ref object
    id*: string
    task*: string
      ## The task's label, under the name Mermaid gives it.
    section*: string
    startTime*, endTime*: JsDate
    hasStart*, hasEnd*: bool
      ## Unset until `getTasks` has scheduled the task, and still unset when what it refers to never resolves.
    renderEndTime*: JsDate
    hasRenderEnd*: bool
      ## Where the bar ends when excluded days pushed the task's end out; unset when the end was given as a date.
    manualEndTime*: bool
    processed*: bool
    active*, done*, crit*, milestone*, vert*: bool
    order*: int
      ## Row index in source order; -1 for vertical markers, which take no row.
    classes*: seq[string]
    prevTaskId*: string
    hasPrev*: bool
    raw*: GanttRaw
