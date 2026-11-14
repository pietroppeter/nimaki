## port-of: src/diagrams/er/markers.ts
## port-status: conformant
import ../../svg/builder

const MARKER_LENGTH* = 18.0
  ## How far a marker reaches back along its line from the box it touches.

const
  BAR = 5.0
  FOOT = 6.0
  FOOT_LENGTH = 10.0
  RING = 3.5

# Draws a crow's foot cardinality marker over the end of a line that meets a box at (x, y)
# while travelling along the unit vector (dx, dy). Types are Mermaid's lower-cased cardinalities.
proc erMarker*(kind: string, x, y, dx, dy: float): string =
  proc at(back, side: float): string =
    num(x - dx * back - dy * side) & "," & num(y - dy * back + dx * side)
  proc bar(back: float): string = "M" & at(back, -BAR) & "L" & at(back, BAR)
  let foot = "M" & at(0, -FOOT) & "L" & at(FOOT_LENGTH, 0) & "L" & at(0, FOOT)
  proc ring(back: float): string =
    "<circle class=\"pele-marker\" cx=\"" & num(x - dx * back) & "\" cy=\"" & num(y - dy * back) & "\" r=\"" &
      num(RING) & "\" fill=\"var(--_bg)\"/>"
  proc path(d: string): string = "<path class=\"pele-marker\" d=\"" & d & "\"/>"

  case kind
  of "only_one": path(bar(6) & bar(10))
  of "zero_or_one": path(bar(6)) & ring(13.5)
  of "one_or_more": path(foot & bar(FOOT_LENGTH + 3.5))
  of "zero_or_more": path(foot) & ring(FOOT_LENGTH + RING + 0.5)
  of "md_parent":
    "<path class=\"pele-marker\" d=\"M" & at(0, 0) & "L" & at(6, 4) & "L" & at(12, 0) & "L" & at(6, -4) &
      "Z\" fill=\"var(--_bg)\"/>"
  else: ""
