## port-part-of: src/svg/edges.ts
## port-status: draft
##
## Only the arrow marker for now, which timeline draws; the rest of edges.ts comes with the
## layered layout.
import builder

const ARROW* = 8.0

func markerTrim*(kind: string): float =
  if kind == "arrow_point": ARROW - 1 elif kind == "arrow_circle": ARROW elif kind == "arrow_cross": 4 else: 0

func marker*(kind: string, x, y, dx, dy: float, color: string, stroke = "none"): string =
  ## Draws a marker whose tip is at (x, y), pointing along (dx, dy).
  let nx = -dy
  let ny = dx
  if kind == "arrow_point":
    let bx = x - dx * ARROW
    let by = y - dy * ARROW
    let half = ARROW * 0.42
    return "<path class=\"pele-marker\" d=\"M" & num(x) & "," & num(y) & "L" & num(bx + nx * half) & "," &
      num(by + ny * half) & "L" & num(bx - nx * half) & "," & num(by - ny * half) & "Z\" fill=\"" &
      color & "\" stroke=\"" & stroke & "\"/>"
  if kind == "arrow_circle":
    return "<circle class=\"pele-marker\" cx=\"" & num(x - dx * 4) & "\" cy=\"" & num(y - dy * 4) &
      "\" r=\"3.5\" fill=\"" & color & "\" stroke=\"" & stroke & "\"/>"
  if kind == "arrow_cross":
    let cx = x - dx * 4
    let cy = y - dy * 4
    let a = 3.5
    let ux = (dx + nx) * a
    let uy = (dy + ny) * a
    let vx = (dx - nx) * a
    let vy = (dy - ny) * a
    return "<path class=\"pele-marker\" d=\"M" & num(cx - ux) & "," & num(cy - uy) & "L" & num(cx + ux) &
      "," & num(cy + uy) & "M" & num(cx - vx) & "," & num(cy - vy) & "L" & num(cx + vx) & "," &
      num(cy + vy) & "\"/>"
  ""
