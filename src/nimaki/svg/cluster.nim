## port-of: src/svg/cluster.ts
## port-status: conformant
import std/[tables, math]
import ../js
import ../layout/compound
import ../text/[label, icons]
import builder

type Crossings* = Table[int, seq[float]]
  ## The x of every route point, by its rounded y: the edges that cross a cluster's top border.

proc markCrossings*(crossings: var Crossings, route: seq[float]) =
  var k = 0
  while k < route.len:
    let key = int(jsRound(route[k + 1]))
    crossings.mgetOrPut(key, @[]).add route[k]
    k += 3

proc clusterTitleX*(c: CNode, width: float, crossings: Crossings, pad: float): float =
  ## Picks where a cluster title sits along the top edge so that edges entering there do not cross it.
  if width == 0: return c.x
  let top = c.y - c.h / 2
  let left = c.x - c.w / 2
  let half = width / 2
  let candidates = [left + pad - 6 + half, c.x, left + c.w - pad + 6 - half]
  let key = int(jsRound(top))
  if key notin crossings: return candidates[0]
  let xs = crossings[key]
  var best = candidates[0]
  var bestGap = -1.0
  for x in candidates:
    var gap = Inf
    for cx in xs:
      if cx > left and cx < left + c.w: gap = min(gap, abs(cx - x) - half)
    if gap >= 6: return x
    if gap > bestGap + 0.5:
      bestGap = gap
      best = x
  best

proc titleCrossed*(c: CNode, width, x: float, crossings: Crossings): bool =
  ## Whether an edge that enters at the top runs through a title placed at `x`.
  if width <= 0: return false
  let key = int(jsRound(c.y - c.h / 2))
  if key notin crossings: return false
  let left = c.x - c.w / 2
  for cx in crossings[key]:
    if cx > left and cx < left + c.w and abs(cx - x) < width / 2 + 4: return true
  false

proc struckTitle*(label: Label, x, y: float, attrs, id: string, nodes: seq[CNode], index: int,
                  icons: IconResolver = nil): string =
  ## A title that an edge runs through, to be drawn over the edges: the text, on an outline in the
  ## color of the cluster behind it, so that only the line is seen to stop short of the letters.
  ## `nodes` and `index` find how many clusters deep the title is, each of which tints the background.
  var depth = 1
  var p = nodes[index].parent
  while p >= 0 and depth < 8:
    inc depth
    p = nodes[p].parent
  # Each cluster is half its fill over what is behind it.
  let fill = "color-mix(in srgb,var(--_a) " & num(100 * (1 - pow(0.5, float(depth)))) & "%,var(--_bg))"
  "<g class=\"pele-cluster-title\" data-id=\"" & id & "\">" &
    labelSvg(label, x, y, " fill=\"none\" stroke=\"" & fill & "\" stroke-width=\"5\" stroke-linejoin=\"round\"", icons) &
    labelSvg(label, x, y, attrs, icons) &
    "</g>"
