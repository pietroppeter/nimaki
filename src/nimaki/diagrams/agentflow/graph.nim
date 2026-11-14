## port-of: src/diagrams/agentflow/graph.ts
## port-status: conformant
##
## Pele reports shape and containment problems on the model as diagnostics; nothing drawn reads
## them, so the port leaves the reports out and keeps what they change. `assignColorSlots` and
## `normaliseNodeShapes` are written out here.
import std/[options, sets, strutils, tables]
import ../../js
import ../../util/yaml
import colorSlots, db, shapes, types

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
    colorIndex*: int             ## -1 for undefined
    kind*: string                ## "" for undefined

  GraphEdge* = ref object
    id*: string
    isUserDefinedId*: bool
    start*: string
    stop*: string
    kind*: string
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
    curve*: string               ## "" for undefined

  AgentGraph* = ref object of RootObj
    nodes*: seq[GraphNode]
    edges*: seq[GraphEdge]

proc collapsed(sg: AgentSubgraph): bool =
  let v = sg.metadata["view"]
  v != nil and v.kind == yString and v.s == "collapsed"

# Resolves a parsed agentflow into the nodes and edges that are drawn: flow membership, collapsed
# flows, shapes reduced to the ones agentflow has, class styles and palette slots.
proc buildAgentGraph*(db: AgentflowDb, paletteLength: int, defaultCurve = ""): AgentGraph =
  var nodes: seq[GraphNode]
  var edges: seq[GraphEdge]
  let subgraphs = db.subgraphs

  proc compiled(classNames: seq[string]): seq[string] =
    var output: seq[string]
    for name in classNames:
      let def = db.classes.getOrDefault(name, nil)
      if def == nil: continue
      var next: seq[string]
      for s in output & def.styles: next.add s.jsTrim
      output = next
      next = @[]
      for s in output & def.textStyles: next.add s.jsTrim
      output = next
    output

  # Everything inside a collapsed flow is hidden, and stands for its outermost collapsed flow.
  # Mermaid walks the whole inside of each collapsed flow, in the order the flows closed, and the
  # last walk to reach a thing wins. A thing has one container, so a later walk can only enter an
  # earlier one through its root: it stops there, and the root's owner is followed afterwards.
  var hidden = initOrderedSet[string]()
  var owner = initTable[string, string]()
  var walked = initHashSet[string]()
  for sg in subgraphs:
    if not sg.collapsed or sg.id in hidden: continue
    var pending = @[sg.id]
    while pending.len > 0:
      let s = db.subgraph(pending.pop())
      if s == nil: continue
      for childId in s.nodes:
        if childId == sg.id or childId in hidden: continue
        hidden.incl childId
        owner[childId] = sg.id
        if childId notin walked: pending.add childId
    walked.incl sg.id
  var collapsedInto = initTable[string, string]()
  for id in hidden:
    var path = @[id]
    var top = owner[id]
    while true:
      let known = collapsedInto.hasKey(top)
      let hasUp = known or owner.hasKey(top)
      if not hasUp: break
      let up = if known: collapsedInto[top] else: owner[top]
      if not known: path.add top
      top = up
      if known: break
    for p in path: collapsedInto[p] = top

  var position = initTable[string, int]()
  for i, sg in subgraphs: position[sg.id] = i

  # Two flows can each name the other. The nesting that would close the loop is dropped.
  var parentOf = initTable[string, string]()
  proc closesLoop(childId, parentId: string, at: int): bool =
    # Only a flow handled earlier in this pass can already be above the parent.
    if not position.hasKey(childId) or position[childId] < at: return false
    var current = parentId
    var has = true
    var hops = 0
    while has and hops <= subgraphs.len:
      if current == childId: return true
      has = parentOf.hasKey(current)
      if has: current = parentOf[current]
      inc hops
    false
  for i in countdown(subgraphs.high, 0):
    let sg = subgraphs[i]
    if sg.id in hidden: continue
    for id in sg.nodes:
      if closesLoop(id, sg.id, i): continue
      parentOf[id] = sg.id

  proc parentFor(id: string): Option[string] =
    if parentOf.hasKey(id): some(parentOf[id]) else: none(string)

  var byId = initTable[string, GraphNode]()
  for i in countdown(subgraphs.high, 0):
    let sg = subgraphs[i]
    if sg.id in hidden: continue
    let isCollapsed = sg.collapsed
    let node = GraphNode(
      id: sg.id,
      label: sg.title,
      labelType: sg.labelType,
      parentId: parentFor(sg.id),
      cssCompiledStyles: compiled(sg.classes),
      cssClasses: sg.classes.join(" "),
      shape: if isCollapsed: "collapsedGroup" else: "flowGroup",
      dir: sg.dir,
      isGroup: not isCollapsed,
      colorIndex: -1,
    )
    nodes.add node
    byId[sg.id] = node

  for vertex in db.nodes.values:
    if vertex.id in hidden: continue
    let existing = byId.getOrDefault(vertex.id, nil)
    if existing != nil:
      existing.cssStyles = vertex.styles
      existing.cssCompiledStyles = compiled(vertex.classes)
      existing.cssClasses = vertex.classes.join(" ")
      continue
    let t = resolveShapeAlias(vertex.kind)
    let node = GraphNode(
      id: vertex.id,
      label: vertex.text.get(""),
      labelType: vertex.labelType,
      parentId: parentFor(vertex.id),
      cssStyles: vertex.styles,
      cssCompiledStyles: compiled(@["default", "node"] & vertex.classes),
      cssClasses: "default " & vertex.classes.join(" "),
      dir: vertex.dir,
      link: vertex.link,
      linkTarget: vertex.linkTarget,
      tooltip: db.tooltips.getOrDefault(vertex.id, ""),
      isGroup: false,
      shape: if t == "square" or t == "": "squareRect" else: t,
      colorIndex: -1,
    )
    nodes.add node
    byId[vertex.id] = node

  for index, raw in db.edges:
    let start = collapsedInto.getOrDefault(raw.start, raw.start)
    let stop = collapsedInto.getOrDefault(raw.stop, raw.stop)
    # An edge between two things inside one collapsed flow has nothing left to connect.
    if start == stop and raw.start != raw.stop: continue
    var styles = db.defaultEdgeStyle
    for s in raw.style: styles.add s
    let arrow =
      if raw.kind == "arrow_open": "none"
      elif raw.kind == "arrow_cross" or raw.kind == "arrow_point": raw.kind
      else: "arrow_point"
    edges.add GraphEdge(
      id: if raw.id != "": raw.id else: "L_" & start & "_" & stop & "_" & $index,
      isUserDefinedId: raw.isUserDefinedId,
      start: start,
      stop: stop,
      kind: if raw.kind != "": raw.kind else: "normal",
      label: raw.text,
      labelType: raw.labelType,
      thickness: raw.stroke,
      pattern: raw.stroke,
      minlen: raw.length,
      classes: "edge-thickness-normal edge-pattern-solid flowchart-link",
      arrowTypeStart: "none",
      arrowTypeEnd: arrow,
      cssCompiledStyles: compiled(raw.classes),
      style: styles,
      curve: if raw.interpolate != "": raw.interpolate
             elif db.defaultInterpolate != "": db.defaultInterpolate
             else: defaultCurve,
    )

  for node in nodes:
    if not node.isGroup: node.shape = normaliseShape(node.shape)

  # Containers are numbered in the order they were written: a walk of the nesting, parents first.
  # `subgraphs` itself is in the order the blocks closed, with a nested flow before its parent.
  var children = initTable[string, seq[string]]()
  for sg in subgraphs:
    if not parentOf.hasKey(sg.id): continue
    children.mgetOrPut(parentOf[sg.id], @[]).add sg.id
  var order = initTable[string, int]()
  for sg in subgraphs:
    if parentOf.hasKey(sg.id): continue
    var pending = @[sg.id]
    while pending.len > 0:
      let id = pending.pop()
      if order.hasKey(id): continue
      order[id] = order.len
      if children.hasKey(id):
        let kids = children[id]
        for i in countdown(kids.high, 0): pending.add kids[i]

  var fallback = order.len
  for node in nodes:
    # A collapsed container is drawn as a node but keeps its slot, so collapsing one does not
    # recolor the containers after it.
    if node.isGroup or node.shape == "collapsedGroup":
      var n: int
      if order.hasKey(node.id): n = order[node.id]
      else:
        n = fallback
        inc fallback
      node.colorIndex = containerSlot(n, paletteLength)
      continue
    var kind = ""
    if db.connectors.hasKey(node.id): kind = "connector"
    elif db.nodes.hasKey(node.id): kind = db.vertexKind(db.nodes[node.id])
    if kind != "" and kindSlot(kind) >= 0: node.kind = kind

  AgentGraph(nodes: nodes, edges: edges)
