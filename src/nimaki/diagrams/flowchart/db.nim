## port-of: src/diagrams/flowchart/db.ts
## port-status: draft
import std/[options, sets, strutils, tables, unicode]
from std/math import isNaN
import ../../errors
import ../../js
import ../../util/[url, yaml]
import shapes, types
import ../../jsregex

type
  FlowDbOptions* = object
    maxEdges*: Option[int]
    inheritDir*: bool
    direction*: string         ## "" for undefined
    # Pele's `warn` callback is never set by the flowchart's entry point; it is left out.

  Destructed* = tuple[kind, stroke: string, length: int]  ## length NO_LENGTH for undefined

proc labelType(t: string): LabelType =
  ## `t` "" is undefined.
  if t == "markdown" or t == "string" or t == "text": t else: "markdown"

proc unquote(text: string): string =
  if text.startsWith("\"") and text.endsWith("\""): text.substr(1, text.len - 2) else: text

proc countChar(ch: char, str: string): int =
  for c in str:
    if c == ch: inc result

proc destructStartLink(raw: string): Destructed =
  var str = raw.jsTrim
  var t = "arrow_open"
  case (if str.len > 0: str[0] else: '\0')
  of '<':
    t = "arrow_point"
    str = str.substr(1)
  of 'x':
    t = "arrow_cross"
    str = str.substr(1)
  of 'o':
    t = "arrow_circle"
    str = str.substr(1)
  else: discard
  var stroke = "normal"
  if '=' in str: stroke = "thick"
  if '.' in str: stroke = "dotted"
  (t, stroke, NO_LENGTH)

proc destructEndLink(raw: string): Destructed =
  # A link token is ASCII, so a byte is a code unit here.
  let str = raw.jsTrim
  var line = str.substr(0, str.len - 2)
  var t = "arrow_open"
  case (if str.len > 0: str[^1] else: '\0')
  of 'x':
    t = "arrow_cross"
    if str.startsWith("x"):
      t = "double_" & t
      line = line.substr(1)
  of '>':
    t = "arrow_point"
    if str.startsWith("<"):
      t = "double_" & t
      line = line.substr(1)
  of 'o':
    t = "arrow_circle"
    if str.startsWith("o"):
      t = "double_" & t
      line = line.substr(1)
  else: discard
  var stroke = "normal"
  var length = line.len - 1
  if line.startsWith("="): stroke = "thick"
  if line.startsWith("~"): stroke = "invisible"
  let dots = countChar('.', line)
  if dots != 0:
    stroke = "dotted"
    length = dots
  (t, stroke, length)

type FlowDb* = ref object of RootObj
  direction*: string           ## "" for undefined
  nodes*: OrderedTable[string, FlowNode]
  edges*: seq[FlowEdge]
  subgraphs*: seq[FlowSubgraph]
  classes*: Table[string, FlowClassDef]
  tooltips*: Table[string, string]
  defaultEdgeStyle*: seq[string]  ## empty for undefined (only copied from)
  defaultInterpolate*: string     ## "" for undefined
  title*: string
  accTitle*: string
  accDescr*: string

  subgraphLookup: Table[string, FlowSubgraph]
  members: HashSet[string]
  edgeById: Table[string, FlowEdge]
  pairCount: Table[string, int]
  subCount: int
  options: FlowDbOptions

proc newFlowDb*(options = FlowDbOptions()): FlowDb =
  FlowDb(options: options)

proc yamlNumber(v: YamlValue): float =
  ## `Number(v)` for what YAML gives.
  if v == nil: return NaN
  case v.kind
  of yNull: 0.0
  of yBool: (if v.b: 1.0 else: 0.0)
  of yNumber: v.n
  of yString: jsNumber(v.s)
  of ySeq: (if v.items.len == 0: 0.0 elif v.items.len == 1: yamlNumber(ystr(jsStr(v.items[0]))) else: NaN)
  of yMap: NaN

proc addVertex*(db: FlowDb, id: string, textObj = none(FlowText), typ = "",
                style = none(seq[string]), classes = none(seq[string]), dir = "",
                props = none(Table[string, string]), metadata = none(string)) =
  ## `typ` and `dir` "" are undefined.
  if id.len == 0 or id.jsTrim.len == 0: return

  var doc: YamlValue = nil
  if metadata.isSome:
    let m = metadata.get
    let yaml = if '\n' in m: m & "\n" else: "{\n" & m & "\n}"
    var parsed: YamlValue
    try:
      parsed = parseYaml(yaml)
    except YamlError as error:
      raise newPeleError("Metadata of \"" & id & "\" is not valid YAML. " & error.msg, "syntax", "flowchart")
    doc = if parsed.isRecord: parsed else: nil

  let subgraph = db.subgraphLookup.getOrDefault(id, nil)
  if subgraph != nil and doc != nil:
    # `{ ...subgraph.metadata, ...doc }`
    let merged = ymap()
    if subgraph.metadata != nil:
      for k, v in subgraph.metadata.fields: merged[k] = v
    for k, v in doc.fields: merged[k] = v
    subgraph.metadata = merged
    return

  let edge = db.edgeById.getOrDefault(id, nil)
  if edge != nil:
    if doc["animate"] != nil: edge.animate = doc["animate"]
    if doc["animation"] != nil: edge.animation = doc["animation"]
    if doc["curve"] != nil: edge.interpolate = jsStr(doc["curve"])
    return

  var vertex = db.nodes.getOrDefault(id, nil)
  if vertex == nil:
    vertex = FlowNode(id: id, labelType: "text", assetWidth: NaN, assetHeight: NaN)
    db.nodes[id] = vertex

  if textObj.isSome:
    vertex.labelType = textObj.get.kind
    vertex.text = some(unquote(textObj.get.text.jsTrim))
  elif vertex.text.isNone:
    vertex.text = some(id)
  if typ != "": vertex.kind = typ
  if style.isSome:
    for s in style.get: vertex.styles.add s
  if classes.isSome:
    for c in classes.get: vertex.classes.add c
  if dir != "": vertex.dir = dir
  if props.isSome:
    for k, v in props.get: vertex.props[k] = v

  if doc == nil: return

  if truthy(doc["shape"]):
    let shape = jsStr(doc["shape"])
    if shape != unicode.toLower(shape) or '_' in shape:
      raise newPeleError("No such shape: " & shape & ". Shape names should be lowercase.", "semantic", "flowchart")
    if not isValidShape(shape):
      raise newPeleError("No such shape: " & shape & ".", "semantic", "flowchart")
    vertex.kind = shape
  let lv = doc["label"]
  let isLabel = lv != nil and lv.kind == yString
  let label = if isLabel: lv.s else: ""
  if truthy(lv):
    vertex.text = some(jsStr(lv))
    let lt = doc["labelType"]
    vertex.labelType = labelType(if lt != nil and lt.kind == yString: lt.s else: "")
  if truthy(doc["icon"]):
    vertex.icon = jsStr(doc["icon"])
    if label.jsTrim.len == 0 and vertex.text == some(id): vertex.text = some("")
  if truthy(doc["form"]): vertex.form = jsStr(doc["form"])
  if truthy(doc["pos"]): vertex.pos = jsStr(doc["pos"])
  if truthy(doc["img"]):
    vertex.img = jsStr(doc["img"])
    if label.jsTrim.len == 0 and vertex.text == some(id): vertex.text = some("")
  if truthy(doc["constraint"]): vertex.constraint = jsStr(doc["constraint"])
  if truthy(doc["w"]): vertex.assetWidth = yamlNumber(doc["w"])
  if truthy(doc["h"]): vertex.assetHeight = yamlNumber(doc["h"])

proc addSingleLink*(db: FlowDb, start, stop: string, info: Option[FlowLinkInfo], id = "") =
  let edge = FlowEdge(start: start, stop: stop, text: "", labelType: "text",
                      isUserDefinedId: false, interpolate: db.defaultInterpolate, length: NO_LENGTH)
  if info.isSome and info.get.text.isSome:
    let linkText = info.get.text.get
    edge.text = unquote(linkText.text.jsTrim)
    edge.labelType = labelType(linkText.kind)
  if info.isSome:
    edge.kind = info.get.kind
    edge.stroke = info.get.stroke
    edge.length = if info.get.length != NO_LENGTH and info.get.length > 10: 10 else: info.get.length
  let pair = start & "\0" & stop
  let count = db.pairCount.getOrDefault(pair, 0)
  if id != "" and not db.edgeById.hasKey(id):
    edge.id = id
    edge.isUserDefinedId = true
  else:
    edge.id = "L_" & start & "_" & stop & "_" & $(if count == 0: 0 else: count + 1)

  let max = db.options.maxEdges
  if max.isSome and db.edges.len >= max.get:
    raise newPeleError("Edge limit exceeded. The limit is " & $max.get & ".", "limit", "flowchart")
  db.edges.add edge
  db.pairCount[pair] = count + 1
  if not db.edgeById.hasKey(edge.id): db.edgeById[edge.id] = edge

proc addLink*(db: FlowDb, starts, ends: seq[string], linkData: Option[FlowLinkInfo]) =
  # `linkData.id.replace('@', '')` replaces the first one.
  let id = if linkData.isSome and linkData.get.id != "": linkData.get.id.replaceFirst("@", "") else: ""
  let lastStart = starts[^1]
  let firstEnd = ends[0]
  for start in starts:
    for e in ends:
      db.addSingleLink(start, e, linkData, if start == lastStart and e == firstEnd: id else: "")

proc edgeAt(db: FlowDb, pos: string): FlowEdge =
  let n = jsNumber(pos)
  if n.isNaN or n < 0 or n != float(int(n)) or int(n) >= db.edges.len:
    raise newPeleError("The index " & pos & " for linkStyle is out of bounds. Valid indices for linkStyle are between 0 and " &
      $(db.edges.len - 1) & ". (Help: Ensure that the index is within the range of existing edges.)", "semantic", "flowchart")
  db.edges[int(n)]

proc updateLinkInterpolate*(db: FlowDb, positions: seq[string], interpolate: string) =
  for pos in positions:
    if pos == "default": db.defaultInterpolate = interpolate
    else: db.edgeAt(pos).interpolate = interpolate

proc updateLink*(db: FlowDb, positions: seq[string], styleIn: seq[string]) =
  # Pele gives every edge of one statement the same array and pushes `fill:none` into it once,
  # after giving it to the first edge: pushing before the first assignment gives the same styles.
  var style = styleIn
  for pos in positions:
    if pos == "default":
      db.defaultEdgeStyle = style
      continue
    let edge = db.edgeAt(pos)
    var anyFill = false
    for s in style:
      if s.startsWith("fill"): anyFill = true
    if style.len > 0 and not anyFill: style.add "fill:none"
    edge.style = style

proc addClass*(db: FlowDb, ids: string, styles: seq[string]) =
  let style = styles.join(",").replace("\\,", "§§§").replace(",", ";").replace("§§§", ",").split(';')
  for id in ids.split(','):
    var classNode = db.classes.getOrDefault(id, nil)
    if classNode == nil:
      classNode = FlowClassDef(id: id)
      db.classes[id] = classNode
    for s in style:
      if "color" in s: classNode.textStyles.add s.replaceFirst("fill", "bgFill")
      classNode.styles.add s

proc setDirection*(db: FlowDb, dir: string) =
  var d = dir.jsTrim
  if '<' in d: d = "RL"
  if '^' in d: d = "BT"
  if '>' in d: d = "LR"
  if 'v' in d: d = "TB"
  if d == "TD": d = "TB"
  db.direction = d

proc setClass*(db: FlowDb, ids, className: string) =
  for id in ids.split(','):
    if db.nodes.hasKey(id): db.nodes[id].classes.add className
    if db.edgeById.hasKey(id): db.edgeById[id].classes.add className
    if db.subgraphLookup.hasKey(id): db.subgraphLookup[id].classes.add className

proc setTooltip*(db: FlowDb, ids: string, tooltip: Option[string]) =
  if tooltip.isNone: return
  for id in ids.split(','): db.tooltips[id] = tooltip.get

proc setLink*(db: FlowDb, ids, link: string, target = "") =
  let url = link.jsTrim
  for id in ids.split(','):
    let vertex = db.nodes.getOrDefault(id, nil)
    if vertex != nil:
      vertex.link = if url != "": safeUrl(url) else: ""
      vertex.linkTarget = target
  db.setClass(ids, "clickable")

# Callbacks are never executed; the node is only marked clickable, as in Mermaid's strict mode.
proc setClickEvent*(db: FlowDb, ids: string, functionName = "", functionArgs = "") =
  db.setClass(ids, "clickable")

proc setAccTitle*(db: FlowDb, text: string) =
  db.accTitle = text.jsTrimStart  # text.replace(/^\s+/g, '')

proc setAccDescription*(db: FlowDb, text: string) =
  db.accDescr = text.replace(jsre"/\n\s+/g", "\n")

proc hasSpace(s: string): bool =
  ## /\s/.test(s)
  var i = 0
  while i < s.len:
    if isJsSpaceAt(s, i): return true
    inc i
  false

proc addSubGraph*(db: FlowDb, idText: Option[FlowText], list: seq[DocItem],
                  titleText: Option[FlowText], sameText: bool): string =
  ## `sameText` is Pele's `idText === titleText`: the header gave no separate title.
  var hasId = idText.isSome
  var id = if hasId: idText.get.text.jsTrim else: ""
  var title = if titleText.isSome: titleText.get.text else: ""
  if idText.isSome and sameText and hasSpace(title): hasId = false

  var seen = initHashSet[string]()
  var nodeList: seq[string]
  var dir = ""
  for entry in list:
    case entry.kind
    of dkString:
      if entry.s.jsTrim != "" and entry.s notin seen:
        seen.incl entry.s
        nodeList.add entry.s
    of dkList:
      for item in entry.items:
        if item.jsTrim != "" and item notin seen:
          seen.incl item
          nodeList.add item
    of dkDir:
      dir = entry.value
  if dir == "":
    dir = if db.options.inheritDir: (if db.direction != "": db.direction else: db.options.direction) else: ""

  if not hasId: id = "subGraph" & $db.subCount
  inc db.subCount

  let subgraph = FlowSubgraph(id: id, nodes: nodeList, title: title.jsTrim, dir: dir,
                              labelType: labelType(if titleText.isSome: titleText.get.kind else: ""))
  # A node belongs to the first subgraph that lists it, and a subgraph never contains itself.
  var kept: seq[string]
  for nodeId in nodeList:
    if nodeId notin db.members and nodeId != id: kept.add nodeId
  subgraph.nodes = kept
  for nodeId in subgraph.nodes: db.members.incl nodeId

  let existing = db.subgraphLookup.getOrDefault(id, nil)
  if existing != nil:
    for nodeId in subgraph.nodes: existing.nodes.add nodeId
  else: db.subgraphs.add subgraph
  db.subgraphLookup[id] = if existing != nil: existing else: subgraph
  id

proc exists*(db: FlowDb, all: seq[FlowSubgraph], id: string): bool =
  for sg in all:
    if id in sg.nodes: return true
  false

proc makeUniq*(db: FlowDb, sg: FlowSubgraph, all: seq[FlowSubgraph]): seq[string] =
  var taken = initHashSet[string]()
  for other in all:
    for id in other.nodes: taken.incl id
  for id in sg.nodes:
    if id notin taken: result.add id

proc destructLink*(db: FlowDb, stop: string, start = ""): FlowLinkInfo =
  ## `start` "" is undefined.
  let info = destructEndLink(stop)
  if start == "": return FlowLinkInfo(kind: info.kind, stroke: info.stroke, length: info.length)
  var startInfo = destructStartLink(start)
  if startInfo.stroke != info.stroke: return FlowLinkInfo(kind: "INVALID", stroke: "INVALID", length: NO_LENGTH)
  if startInfo.kind == "arrow_open":
    startInfo.kind = info.kind
  else:
    if startInfo.kind != info.kind: return FlowLinkInfo(kind: "INVALID", stroke: "INVALID", length: NO_LENGTH)
    startInfo.kind = "double_" & startInfo.kind
  if startInfo.kind == "double_arrow": startInfo.kind = "double_arrow_point"
  FlowLinkInfo(kind: startInfo.kind, stroke: startInfo.stroke, length: info.length)

proc subgraph*(db: FlowDb, id: string): FlowSubgraph =
  ## nil when there is none.
  db.subgraphLookup.getOrDefault(id, nil)
