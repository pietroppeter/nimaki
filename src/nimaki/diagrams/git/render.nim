## port-of: src/diagrams/git/render.ts
## port-status: conformant
import std/[algorithm, options, tables]
from std/math import ceil
import ../../js
import ../../preprocess
import ../../svg/[builder, palette, root, theme]
import ../../text/[label, measurer]
import ../../types
import ../../util/yaml
import ../common/[fit, fit_width]
import db

const
  DOT = 7.0
  STEP = 44.0
  LANE = 44.0
  CURVE = 36.0
    ## Shorter than a step, so a curve between lanes never runs through a commit on a lane it crosses.
  GAP = 8.0
  LABEL_GAP = 20.0
  TAIL = 20.0
  NOTCH = 7.0
  TAG_GAP = 6.0
  HALF = 0.7071067811865476 ## Math.SQRT1_2
  CLASSES = ["normal", "reverse", "highlight", "merge", "cherry-pick"]

type View = ref object
  commit: GitCommit
  index: int
  lane: int
  m: float
  label: Label
  hasLabel: bool   ## `label` undefined when false
  tags: seq[Label]

proc flag(config: Config, key: string, fallback: bool): bool =
  let value = config["gitGraph"][key]
  if value != nil and value.kind == yBool: value.b else: fallback

func tagWidth(tag: Label): float = NOTCH + 4 + tag.width + 6

proc symbol(kind: int, x, y: float, color: string): string =
  let at = "cx=\"" & num(x) & "\" cy=\"" & num(y) & "\""
  if kind == HIGHLIGHT:
    return "<rect x=\"" & num(x - DOT - 1) & "\" y=\"" & num(y - DOT - 1) & "\" width=\"16\" height=\"16\" rx=\"2\" fill=\"" & color & "\"/>"
  if kind == MERGE:
    return "<circle " & at & " r=\"6\" fill=\"var(--_bg)\" stroke=\"" & color & "\" stroke-width=\"2\"/><circle " & at & " r=\"2.5\" fill=\"" & color & "\"/>"
  let dot = "<circle " & at & " r=\"7\" fill=\"" & color & "\"/>"
  if kind == REVERSE:
    return dot & "<path d=\"M" & num(x - 3) & "," & num(y - 3) & "l6,6M" & num(x - 3) & "," & num(y + 3) &
      "l6,-6\" fill=\"none\" stroke=\"var(--_bg)\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>"
  if kind == CHERRY_PICK:
    return dot &
      "<path d=\"M" & num(x - 2.6) & "," & num(y + 1) & "L" & num(x + 0.8) & "," & num(y - 4.2) & "L" & num(x + 2.6) & "," &
      num(y + 1) & "\" fill=\"none\" stroke=\"var(--_bg)\" stroke-linejoin=\"round\"/>" &
      "<circle cx=\"" & num(x - 2.6) & "\" cy=\"" & num(y + 2.2) & "\" r=\"1.8\" fill=\"var(--_bg)\"/>" &
      "<circle cx=\"" & num(x + 2.6) & "\" cy=\"" & num(y + 2.2) & "\" r=\"1.8\" fill=\"var(--_bg)\"/>"
  dot

proc draw(model: GitModel, config: Config, options: RenderOptions, direction: GitDirection): Rendered

proc renderGit*(model: GitModel, config: Config, options: RenderOptions): Rendered =
  if model.direction != "LR": return draw(model, config, options, model.direction)
  turnToFit(options, proc (down: bool): Rendered = draw(model, config, options, if down: "TB" else: "LR"))

proc draw(model: GitModel, config: Config, options: RenderOptions, direction: GitDirection): Rendered =
  let size = options.fontSize.get(16)
  let small = jsRound(size * 0.75)
  let measurer = measurerOf(options)
  let pad = options.padding.get(8)

  let showBranches = flag(config, "showBranches", true)
  let showCommitLabel = flag(config, "showCommitLabel", true)
  let rotate = flag(config, "rotateCommitLabel", true)
  let parallel = flag(config, "parallelCommits", false)
  let vertical = direction != "LR"
  let flip = direction == "BT"

  var laneOf = initTable[string, int]()
  for index, name in model.lanes: laneOf[name] = index
  let laneCount = model.lanes.len
  let medium = jsRound(size * 0.875)
  # Mermaid writes branch names, tags, and commit ids as plain text, so tags in them show as written.
  var names: seq[Label]
  for name in model.lanes: names.add plainLabel(if showBranches: name else: "", measurer, medium, 4000)

  var views: seq[View]
  var byId = initTable[string, View]()
  var sorted: seq[GitCommit]
  for commit in model.commits.values: sorted.add commit
  sorted.sort(proc (a, b: GitCommit): int = cmp(a.seq, b.seq))
  for commit in sorted:
    let labelled = showCommitLabel and commit.kind != CHERRY_PICK and (commit.kind != MERGE or commit.customId)
    var tags: seq[Label]
    for tag in commit.tags:
      let label = plainLabel(tag, measurer, small, 4000)
      if label.lines.len > 0: tags.add label
    let view = View(commit: commit, index: views.len, lane: laneOf.getOrDefault(commit.branch, 0), m: 0,
                    hasLabel: labelled, tags: tags)
    if labelled: view.label = plainLabel(commit.id, measurer, small, 4000)
    views.add view
    byId[commit.id] = view

  # Room each commit needs: along the main axis on either side, and across it towards the
  # previous lane (`lo`) and the next one (`hi`). Tags sit on one side of a lane and ids on the other.
  var half = newSeq[float](views.len)
  var tagHalf = newSeq[float](views.len)
  var lo = newSeq[float](laneCount)
  var hi = newSeq[float](laneCount)
  for i in 0 ..< laneCount:
    lo[i] = DOT
    hi[i] = DOT
  for k, view in views:
    var tagsMain = 0.0
    var tagsCross = 0.0
    for tag in view.tags:
      let w = tagWidth(tag)
      if vertical:
        tagsMain = max(tagsMain, tag.height)
        tagsCross += w + 4
      else:
        tagsMain = max(tagsMain, w)
        tagsCross += tag.height + 3
    var labelMain = 0.0
    var labelCross = 0.0
    if view.hasLabel and view.label.lines.len > 0:
      if rotate:
        labelCross = 3 + HALF * (view.label.width + view.label.height)
      else:
        labelMain = if vertical: view.label.height else: view.label.width
        labelCross = 6 + (if vertical: view.label.width else: view.label.height)
    half[k] = max(DOT, max(tagsMain / 2, labelMain / 2))
    tagHalf[k] = tagsMain / 2
    let tagSide = DOT + (if view.tags.len > 0: TAG_GAP + tagsCross else: 0)
    let labelSide = DOT + labelCross
    let lane = view.lane
    lo[lane] = max(lo[lane], if vertical: labelSide else: tagSide)
    hi[lane] = max(hi[lane], if vertical: tagSide else: labelSide)

  # In a left-to-right graph the tags stand over their commit. A connector that comes down from
  # a lane above joins the commit's lane this far before the commit, clear of the tags, and the
  # commit is placed far enough along to leave room for that.
  var lead = newSeq[float](views.len)
  if not vertical:
    for k, view in views:
      if tagHalf[k] == 0: continue
      for id in view.commit.parents:
        let parent = byId.getOrDefault(id, nil)
        if parent != nil and parent.lane < view.lane: lead[k] = tagHalf[k] + 4
  proc space(p, k: int): float =
    max(STEP, max(half[p] + half[k] + GAP, if lead[k] > 0: half[p] + CURVE + lead[k] else: 0.0))

  for k, view in views:
    if not parallel:
      view.m = if k == 0: 0.0 else: views[k - 1].m + space(k - 1, k)
      continue
    # Mermaid's `parallelCommits`: a commit sits one step after its furthest parent, so branches
    # that grow side by side share positions instead of taking turns.
    var m = 0.0
    for id in view.commit.parents:
      let parent = byId.getOrDefault(id, nil)
      if parent == nil or parent.index >= k: continue
      m = max(m, parent.m + space(parent.index, k))
    view.m = m
  var stop = 0.0
  for view in views: stop = max(stop, view.m)

  var cross = newSeq[float](laneCount)
  for i in 0 ..< laneCount:
    let name = names[i]
    let reach = if name.lines.len == 0: 0.0 elif vertical: name.width / 2 + 8 else: name.height / 2 + 2
    lo[i] = max(lo[i], reach)
    hi[i] = max(hi[i], reach)
    if i > 0: cross[i] = cross[i - 1] + max(LANE, hi[i - 1] + lo[i] + GAP)

  proc px(m, c: float): float = (if vertical: c else: m)
  proc py(m, c: float): float = (if vertical: (if flip: -m else: m) else: c)
  proc point(m, c: float): string = num(px(m, c)) & "," & num(py(m, c))

  var minX = Inf
  var minY = Inf
  var maxX = -Inf
  var maxY = -Inf
  proc grow(x0, y0, x1, y1: float) =
    if x0 < minX: minX = x0
    if y0 < minY: minY = y0
    if x1 > maxX: maxX = x1
    if y1 > maxY: maxY = y1

  var branches = ""
  if showBranches:
    for i in 0 ..< laneCount:
      let name = names[i]
      let color = seriesColor(i)
      let c = cross[i]
      let w = name.width + 16
      let h = name.height + 4
      let start = if name.lines.len == 0: -LABEL_GAP else: -LABEL_GAP - (if vertical: h else: w)
      let cx = px(start + (if vertical: h else: w) / 2, c)
      let cy = py(start + (if vertical: h else: w) / 2, c)
      grow(px(-LABEL_GAP, c), py(-LABEL_GAP, c), px(-LABEL_GAP, c), py(-LABEL_GAP, c))
      grow(px(stop + TAIL, c), py(stop + TAIL, c), px(stop + TAIL, c), py(stop + TAIL, c))
      branches.add "<g class=\"pele-branch\" data-id=\"" & escText(model.lanes[i]) & "\">" &
        "<path class=\"pele-lane\" d=\"M" & point(-LABEL_GAP, c) & "L" & point(stop + TAIL, c) & "\" stroke=\"" &
        color & "\" stroke-dasharray=\"2 4\"/>"
      if name.lines.len > 0:
        grow(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
        let ink = seriesInkFill(i)
        branches.add "<rect x=\"" & num(cx - w / 2) & "\" y=\"" & num(cy - h / 2) & "\" width=\"" & num(w) &
          "\" height=\"" & num(h) & "\" fill=\"" & color & "\"" & ROUNDED & "/>" &
          labelSvg(name, cx, cy, " class=\"pele-label\"" & (if ink != "": ink else: " fill=\"var(--_bg)\""))
      branches.add "</g>"

  # Positions of the commits on each lane, to tell whether a connector may run along it.
  var taken = newSeq[seq[float]](laneCount)
  for view in views: taken[view.lane].add view.m
  if parallel:
    for list in taken.mitems: list.sort(proc (a, b: float): int = cmp(a, b))
  proc busy(lane: int, start, to: float): bool =
    let list = taken[lane]
    var low = 0
    var high = list.len
    while low < high:
      let mid = (low + high) shr 1
      if list[mid] <= start: low = mid + 1
      else: high = mid
    low < list.len and list[low] < to

  var curves = ""
  var lines = ""
  for view in views:
    let commit = view.commit
    let c2 = cross[view.lane]
    let m2 = view.m
    for j in 0 ..< commit.parents.len:
      let parent = byId.getOrDefault(commit.parents[j], nil)
      if parent == nil or parent == view: continue
      let c1 = cross[parent.lane]
      let m1 = parent.m
      if parent.lane == view.lane:
        lines.add "<path class=\"pele-edge\" d=\"M" & point(m1, c1) & "L" & point(m2, c2) & "\" stroke=\"" &
          seriesColor(view.lane) & "\"/>"
        continue
      let merged = j > 0 and commit.kind == MERGE
      let picked = j > 0 and not merged
      var d = "M" & point(m1, c1)
      if m2 <= m1:
        let mid = (m1 + m2) / 2
        d.add "C" & point(mid, c1) & " " & point(mid, c2) & " " & point(m2, c2)
      elif not merged and not busy(view.lane, m1, m2):
        # Leaves the parent at once and runs along the child's lane.
        let s = min(CURVE, m2 - m1)
        d.add "C" & point(m1 + s / 2, c1) & " " & point(m1 + s / 2, c2) & " " & point(m1 + s, c2) & "L" & point(m2, c2)
      else:
        # Turns in just before the child, or before its tags when it comes from their side.
        let to = if parent.lane < view.lane and m2 - lead[view.index] > m1: m2 - lead[view.index] else: m2
        var s = min(CURVE, to - m1)
        var along = c1
        if not merged or busy(parent.lane, m1, m2):
          # Neither lane is free to run along. Between two lanes, past the ids of one and before
          # the tags of the next, a strip stays empty, and the connector takes that.
          along = if c1 > c2: c2 + hi[view.lane] + GAP / 2 else: c2 - lo[view.lane] - GAP / 2
          s = min(CURVE, (to - m1) / 2)
          d.add "C" & point(m1 + s / 2, c1) & " " & point(m1 + s / 2, along) & " " & point(m1 + s, along)
        d.add "L" & point(to - s, along) & "C" & point(to - s / 2, along) & " " & point(to - s / 2, c2) & " " & point(to, c2)
        if to < m2: d.add "L" & point(m2, c2)
      curves.add "<path class=\"pele-edge" &
        (if merged: " pele-edge-merge" elif picked: " pele-edge-cherry-pick" else: "") & "\" d=\"" & d & "\" " &
        "stroke=\"" & seriesColor(if merged: parent.lane else: view.lane) & "\"" &
        (if picked: " stroke-dasharray=\"4 3\"" else: "") & "/>"

  var commits = ""
  for view in views:
    let commit = view.commit
    let tags = view.tags
    let x = px(view.m, cross[view.lane])
    let y = py(view.m, cross[view.lane])
    let kind = if commit.customType != NO_TYPE: commit.customType else: commit.kind
    grow(x - DOT - 1, y - DOT - 1, x + DOT + 1, y + DOT + 1)
    # Merges and cherry-picks carry a message Mermaid makes up; only a written one is worth showing.
    let written = commit.kind < MERGE and commit.message != ""
    var body = if written: "<title>" & escText(commit.message) & "</title>" else: ""
    body.add symbol(kind, x, y, seriesColor(view.lane))

    if view.hasLabel and view.label.lines.len > 0:
      let label = view.label
      let w = label.width
      let h = label.height
      proc back(cx, cy: float): string =
        "<rect x=\"" & num(cx - w / 2 - 2) & "\" y=\"" & num(cy - h / 2 + 2) & "\" width=\"" & num(w + 4) &
          "\" height=\"" & num(h - 4) & "\" rx=\"3\" fill=\"var(--_bg)\"/>"
      if rotate:
        # The text ends beside the commit and trails back the way the history came.
        let k = (HALF * h) / 2
        let ax = if vertical: x - DOT - 3 - k else: x + 3
        let ay = if vertical: y else: y + DOT + 3 + k
        let reach = HALF * w + k
        grow(ax - reach, (if flip: ay - reach else: ay - k), ax + k, (if flip: ay + k else: ay + reach))
        body.add "<g class=\"pele-commit-label\" transform=\"rotate(" & (if flip: "45" else: "-45") & " " & num(ax) &
          " " & num(ay) & ")\">" & back(ax - w / 2, ay) & labelSvg(label, ax - w / 2, ay, "") & "</g>"
      else:
        let cx = if vertical: x - DOT - 6 - w / 2 else: x
        let cy = if vertical: y else: y + DOT + 6 + h / 2
        grow(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
        body.add "<g class=\"pele-commit-label\">" & back(cx, cy) & labelSvg(label, cx, cy, "") & "</g>"

    # Beside the lane the tags form a row; above it they stack, the first one furthest out.
    var offset = DOT + TAG_GAP
    var t = if vertical: 0 else: tags.len - 1
    while t >= 0 and t < tags.len:
      let tag = tags[t]
      let w = tagWidth(tag)
      let h = tag.height
      let left = if vertical: x + offset else: x - w / 2
      let cy = if vertical: y else: y - offset - h / 2
      offset += (if vertical: w + 4 else: h + 3)
      grow(left, cy - h / 2, left + w, cy + h / 2)
      body.add "<g class=\"pele-tag\">" &
        "<path d=\"M" & num(left) & "," & num(cy) & "L" & num(left + NOTCH) & "," & num(cy - h / 2) & "H" & num(left + w) &
        "V" & num(cy + h / 2) & "H" & num(left + NOTCH) & "Z\" fill=\"var(--_s)\" stroke=\"var(--_b)\" stroke-linejoin=\"round\"/>" &
        "<circle cx=\"" & num(left + NOTCH) & "\" cy=\"" & num(cy) & "\" r=\"1.5\" fill=\"var(--_b)\"/>" &
        labelSvg(tag, left + NOTCH + 4 + tag.width / 2, cy, " fill=\"var(--_fg)\"") &
        "</g>"
      t += (if vertical: 1 else: -1)

    let merge = if commit.kind == MERGE and kind != MERGE: " pele-commit-merge" else: ""
    commits.add "<g class=\"pele-commit pele-commit-" & (if kind >= 0 and kind < CLASSES.len: CLASSES[kind] else: CLASSES[0]) &
      merge & "\" data-id=\"" & escText(commit.id) & "\">" & body & "</g>"

  if minX > maxX: grow(0, 0, 0, 0)
  let title = layoutLabel(model.title, false, measurer, size, 4000, Bold)
  let titleHeight = if title.height > 0: title.height + 16 else: 0.0
  let inner = max(maxX - minX, title.width)
  let width = ceil(inner + 2 * pad)
  let height = ceil(maxY - minY + titleHeight + 2 * pad)
  let dx = pad - minX + (inner - (maxX - minX)) / 2
  let dy = pad + titleHeight - minY

  let content =
    labelSvg(title, width / 2, pad + title.height / 2, " class=\"pele-title\" font-weight=\"var(--_tw)\"") &
    "<g transform=\"translate(" & num(dx) & "," & num(dy) & ")\">" &
    (if branches != "": "<g class=\"pele-branches\" fill=\"none\" font-size=\"" & jsString(medium) & "\">" & branches & "</g>" else: "") &
    (if curves != "" or lines != "": "<g class=\"pele-edges\" fill=\"none\" stroke-width=\"2\" stroke-linecap=\"round\">" & curves & lines & "</g>" else: "") &
    (if commits != "": "<g class=\"pele-commits\" font-size=\"" & jsString(small) & "\" fill=\"var(--_m)\">" & commits & "</g>" else: "") &
    "</g>"

  Rendered(svg: svgDocument("gitGraph", width, height, size, options,
                            Accessible(accTitle: model.accTitle, accDescr: model.accDescr), content),
           width: width, height: height, links: @[])
