## port-of: src/diagrams/flowchart/graph.ts
## port-status: draft
import std/[options, sets, strutils, tables]
import ../../js
import ../../util/yaml
import db, types

type
  GraphNode* = ref object
    id*: string
    label*: string               ## "" for undefined (Pele treats the two alike)
    labelType*: LabelType
    shape*: string
    isGroup*: bool
    parentId*: Option[string]
    cssStyles*: seq[string]
    cssCompiledStyles*: seq[string]
    cssClasses*: string
    dir*: string                 ## "" for undefined
    link*: string                ## "" for undefined, and so are the strings below
    linkTarget*: string
    tooltip*: string
    icon*: string
    pos*: string
    img*: string
    assetWidth*: float           ## NaN for undefined
    assetHeight*: float
    constraint*: string
    colorIndex*: int             ## -1 for undefined
    metadata*: YamlValue         ## nil for undefined

  GraphEdge* = ref object
    id*: string
    isUserDefinedId*: bool
    start*: string
    `end`*: string
    `type`*: string
    label*: string
    labelType*: LabelType
    thickness*: string           ## "" for undefined
    pattern*: string
    minlen*: int                 ## NO_LENGTH for undefined
    arrowTypeStart*: string
    arrowTypeEnd*: string
    cssCompiledStyles*: seq[string]
    style*: seq[string]
    classes*: string
    animate*: YamlValue
    animation*: YamlValue
    curve*: string               ## "" for undefined

  FlowGraph* = object
    nodes*: seq[GraphNode]
    edges*: seq[GraphEdge]

proc shapeOf(vertex: FlowNode): string =
  if vertex.img != "": return "imageSquare"
  if vertex.icon != "":
    if vertex.form == "circle": return "iconCircle"
    if vertex.form == "square": return "iconSquare"
    if vertex.form == "rounded": return "iconRounded"
    return "icon"
  case vertex.`type`
  of "square", "":
    "squareRect"
  of "round":
    "roundedRect"
  else:
    vertex.`type`

proc arrows(t: string): (string, string) =
  case t
  of "arrow_point", "arrow_circle", "arrow_cross":
    return ("none", t)
  of "double_arrow_point", "double_arrow_circle", "double_arrow_cross":
    let single = t.replace("double_", "")
    return (single, single)
  else: discard
  ("none", "arrow_point")

proc isCollapsedView(metadata: YamlValue): bool =
  ## metadata?.view === 'collapsed'
  let v = metadata["view"]
  v != nil and v.kind == yString and v.s == "collapsed"

# Resolves a parsed flowchart into the nodes and edges that are actually drawn:
# group membership, collapsed subgraphs, class styles and edge defaults.
proc buildFlowGraph*(model: FlowDb, defaultCurve = ""): FlowGraph =
  ## `defaultCurve` "" is undefined.
  var nodes: seq[GraphNode]
  var edges: seq[GraphEdge]
  let subgraphs = model.subgraphs

  proc compiled(classNames: seq[string]): seq[string] =
    for name in classNames:
      let def = model.classes.getOrDefault(name, nil)
      if def == nil: continue
      for s in def.styles: result.add s.jsTrim
      for s in def.textStyles: result.add s.jsTrim

  var subgraphParent = initTable[string, string]()
  for sg in subgraphs:
    for childId in sg.nodes:
      if model.subgraph(childId) != nil: subgraphParent[childId] = sg.id

  var declarationIndex = initTable[string, int]()
  var childrenOf = initOrderedTable[string, seq[string]]()
  for sg in subgraphs:
    if not subgraphParent.hasKey(sg.id): continue
    let parent = subgraphParent[sg.id]
    childrenOf.mgetOrPut(parent, @[]).add sg.id
  var nextIndex = 0
  for sg in subgraphs:
    if subgraphParent.hasKey(sg.id): continue
    var pending = @[sg.id]
    while pending.len > 0:
      let id = pending.pop()
      if declarationIndex.hasKey(id): continue
      declarationIndex[id] = nextIndex
      inc nextIndex
      if childrenOf.hasKey(id):
        let kids = childrenOf[id]
        for i in countdown(kids.high, 0): pending.add kids[i]

  proc isCollapsed(id: string): bool =
    let sg = model.subgraph(id)
    sg != nil and isCollapsedView(sg.metadata)
  var anyCollapsed = false
  for sg in subgraphs:
    if isCollapsedView(sg.metadata): anyCollapsed = true
  # The outermost collapsed subgraph around each subgraph, resolved once per chain of parents.
  var outermost = initTable[string, Option[string]]()
  proc outermostCollapsed(id: string): Option[string] =
    var chain: seq[string]
    var seen = initHashSet[string]()
    var current = some(id)
    while current.isSome and not outermost.hasKey(current.get) and current.get notin seen:
      seen.incl current.get
      chain.add current.get
      current = if subgraphParent.hasKey(current.get): some(subgraphParent[current.get]) else: none(string)
    var res = if current.isSome: outermost.getOrDefault(current.get, none(string)) else: none(string)
    for i in countdown(chain.high, 0):
      if res.isNone and isCollapsed(chain[i]): res = some(chain[i])
      outermost[chain[i]] = res
    res

  var hidden = initHashSet[string]()
  var collapsedInto = initTable[string, string]()
  if anyCollapsed:
    for sg in subgraphs:
      let ancestorOpt = outermostCollapsed(sg.id)
      if ancestorOpt.isNone: continue
      let ancestor = ancestorOpt.get
      if sg.id != ancestor:
        hidden.incl sg.id
        collapsedInto[sg.id] = ancestor
      for childId in sg.nodes:
        if childId == ancestor: continue
        hidden.incl childId
        collapsedInto[childId] = ancestor

  var parentOf = initTable[string, string]()
  var groups = initHashSet[string]()
  for i in countdown(subgraphs.high, 0):
    let sg = subgraphs[i]
    if sg.id in hidden: continue
    if sg.nodes.len > 0: groups.incl sg.id
    for id in sg.nodes: parentOf[id] = sg.id

  proc parentOfId(id: string): Option[string] =
    if parentOf.hasKey(id): some(parentOf[id]) else: none(string)

  var byId = initTable[string, GraphNode]()
  for i in countdown(subgraphs.high, 0):
    let sg = subgraphs[i]
    if sg.id in hidden: continue
    let collapsed = isCollapsedView(sg.metadata)
    let node = GraphNode(
      id: sg.id,
      label: sg.title,
      labelType: sg.labelType,
      parentId: parentOfId(sg.id),
      cssStyles: @[],
      cssCompiledStyles: compiled(sg.classes),
      cssClasses: sg.classes.join(" "),
      shape: if collapsed: "collapsedGroup" else: "rect",
      dir: sg.dir,
      isGroup: not collapsed,
      colorIndex: declarationIndex.getOrDefault(sg.id, -1),
      assetWidth: NaN,
      assetHeight: NaN,
    )
    if not collapsed: node.metadata = sg.metadata
    nodes.add node
    byId[sg.id] = node

  for vertex in model.nodes.values:
    if vertex.id in hidden: continue
    let existing = byId.getOrDefault(vertex.id, nil)
    if existing != nil:
      existing.cssStyles = vertex.styles
      existing.cssCompiledStyles = compiled(vertex.classes)
      existing.cssClasses = vertex.classes.join(" ")
      continue
    let isGroup = vertex.id in groups
    let node = GraphNode(
      id: vertex.id,
      label: vertex.text.get(""),
      labelType: vertex.labelType,
      parentId: parentOfId(vertex.id),
      cssStyles: vertex.styles,
      cssCompiledStyles: compiled(@["default", "node"] & vertex.classes),
      cssClasses: "default " & vertex.classes.join(" "),
      dir: vertex.dir,
      link: vertex.link,
      linkTarget: vertex.linkTarget,
      tooltip: model.tooltips.getOrDefault(vertex.id, ""),
      icon: vertex.icon,
      pos: vertex.pos,
      img: vertex.img,
      assetWidth: vertex.assetWidth,
      assetHeight: vertex.assetHeight,
      constraint: vertex.constraint,
      colorIndex: -1,
      isGroup: isGroup,
      shape: if isGroup: "rect" else: shapeOf(vertex),
    )
    nodes.add node

  for index, raw in model.edges:
    let start = collapsedInto.getOrDefault(raw.start, raw.start)
    let e = collapsedInto.getOrDefault(raw.`end`, raw.`end`)
    if start == e and (collapsedInto.hasKey(raw.start) or collapsedInto.hasKey(raw.`end`)): continue

    let (arrowStart, arrowEnd) = arrows(raw.`type`)
    var styles = model.defaultEdgeStyle
    for s in raw.style: styles.add s
    let plain = raw.stroke == "invisible" or raw.`type` == "arrow_open"
    edges.add GraphEdge(
      id: if raw.id != "": raw.id else: "L_" & start & "_" & e & "_" & $index,
      isUserDefinedId: raw.isUserDefinedId,
      start: start,
      `end`: e,
      `type`: if raw.`type` != "": raw.`type` else: "normal",
      label: raw.text,
      labelType: raw.labelType,
      thickness: raw.stroke,
      pattern: raw.stroke,
      minlen: raw.length,
      classes: if raw.stroke == "invisible": "" else: "edge-thickness-normal edge-pattern-solid flowchart-link",
      arrowTypeStart: if plain: "none" else: arrowStart,
      arrowTypeEnd: if plain: "none" else: arrowEnd,
      cssCompiledStyles: compiled(raw.classes),
      style: styles,
      animate: raw.animate,
      animation: raw.animation,
      curve: if raw.interpolate != "": raw.interpolate
             elif model.defaultInterpolate != "": model.defaultInterpolate
             else: defaultCurve,
    )

  FlowGraph(nodes: nodes, edges: edges)
