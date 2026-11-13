## port-of: src/diagrams/agentflow/shapes.ts
## port-status: draft
##
## Pele reports the shapes it replaces as diagnostics; nothing drawn reads them, so the port
## only replaces them.
import std/sets
import ../flowchart/shapes as flowShapes

const SHAPE_ALIASES* = [
  ("task", "roundedRect"),
  ("tool", "subroutine"),
  ("input", "lean-right"),
  ("decision", "diamond"),
  ("refdoc", "lin-doc"),
  ("action", "hexagon"),
  ("round", "rect"),
]

let REMOVED_SHAPES* = toHashSet([
  "doc", "stadium", "terminal", "circle", "trapezoid", "inv_trapezoid", "inv-trapezoid",
  "doublecircle", "double-circle", "typeDeclaration", "procs", "lean_left", "lean-left", "in-out",
  "cylinder", "ellipse", "odd", "tag-rect", "tagged-rectangle", "delay", "half-rounded-rectangle",
  "lin-rect", "lined-rectangle", "win-pane", "window-pane", "curv-trap", "curved-trapezoid",
])

let ALLOWED_SHAPES* = toHashSet([
  "roundedRect", "subroutine", "subprocess", "subproc", "framed-rectangle", "lean-right",
  "diamond", "lin-doc", "lined-document", "hexagon", "hex", "connector", "collapsedGroup",
])

const DEFAULT_SHAPE* = "roundedRect"

func resolveShapeAlias*(shape: string): string =
  ## "" is undefined (and an empty name, which Pele returns as it is).
  if shape == "": return shape
  for (alias, name) in SHAPE_ALIASES:
    if alias == shape: return name
  shape

# Mermaid looks a shape name up with `in` on a plain object, so `constructor` passes there too.
proc isValidShape*(name: string): bool =
  flowShapes.isValidShape(name) or name == "constructor"

proc normaliseShape*(shape: string): string =
  ## What `normaliseNodeShapes` does to the shape of a node that is not a group.
  result = shape
  if result == "" or result == "squareRect" or result == "rect": result = DEFAULT_SHAPE
  if result in REMOVED_SHAPES: result = DEFAULT_SHAPE
  elif result notin ALLOWED_SHAPES: result = DEFAULT_SHAPE
