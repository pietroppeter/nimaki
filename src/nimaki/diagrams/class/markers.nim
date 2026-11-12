## port-of: src/diagrams/class/markers.ts
## port-status: draft
import ../../svg/[builder, edges]
import graph

const
  TRIANGLE = 12.0
  DIAMOND = 16.0
  HALF = 6.0
  RING = 5.0

proc classMarkerTrim*(kind: EndMarker): float =
  ## How far the line stops short of the node so that it meets the back of the marker.
  case kind
  of "extension": TRIANGLE
  of "composition", "aggregation": DIAMOND
  of "lollipop": 2 * RING
  of "dependency": markerTrim("arrow_point")
  else: 0

proc classMarker*(kind: EndMarker, x, y, dx, dy: float, color: string): string =
  ## Draws an end marker whose tip is at (x, y), pointing along (dx, dy).
  let nx = -dy
  let ny = dx
  case kind
  of "extension":
    let bx = x - dx * TRIANGLE
    let by = y - dy * TRIANGLE
    "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & num(bx + nx * HALF) & "," &
      num(by + ny * HALF) & "L" & num(bx - nx * HALF) & "," & num(by - ny * HALF) &
      "Z\" stroke-linejoin=\"round\"/>"
  of "composition", "aggregation":
    let mx = x - (dx * DIAMOND) / 2
    let my = y - (dy * DIAMOND) / 2
    let half = HALF - 1
    "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & num(mx + nx * half) & "," &
      num(my + ny * half) & "L" & num(x - dx * DIAMOND) & "," & num(y - dy * DIAMOND) & "L" &
      num(mx - nx * half) & "," & num(my - ny * half) & "Z\" stroke-linejoin=\"round\"" &
      (if kind == "composition": " fill=\"" & color & "\"" else: "") & "/>"
  of "lollipop":
    "<circle class=\"pele-marker\" cx=\"" & num(x - dx * RING) & "\" cy=\"" & num(y - dy * RING) &
      "\" r=\"5\"/>"
  of "dependency":
    marker("arrow_point", x, y, dx, dy, color)
  else: ""
