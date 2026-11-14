## port-of: src/diagrams/wardley/builder.ts
## port-status: conformant
##
## Optional fields are `Option`s where Pele tells undefined from a value; a strategy or a flow
## is "" for none.
import std/[tables, options]
import ../../errors

type
  WardleyNode* = ref object
    ## Coordinates are percentages: x is evolution, y is visibility.
    id*: string
    label*: string
    x*, y*: Option[float]
    className*: string            ## "anchor", "component" or "pipeline-component"; "" for none
    labelOffsetX*, labelOffsetY*: Option[float]
    inPipeline*: bool
    isPipelineParent*: bool
    inertia*: Option[bool]
    sourceStrategy*: string       ## "build", "buy", "outsource", "market"; "" for none

  NodeInput* = object
    ## The object Pele passes to addNode. `full` says that it sets `inertia` and
    ## `sourceStrategy` (even to undefined), as a component does and an anchor does not.
    id*, label*: string
    x*, y*: float
    className*: string
    labelOffsetX*, labelOffsetY*: Option[float]
    full*: bool
    inertia*: Option[bool]
    sourceStrategy*: string

  WardleyLink* = object
    source*, target*: string
    dashed*: bool
    label*: Option[string]
    flow*: string                 ## "forward", "backward", "bidirectional"; "" for none

  WardleyTrend* = object
    nodeId*: string
    targetX*, targetY*: float

  WardleyPipeline* = ref object
    nodeId*: string
    componentIds*: seq[string]

  WardleyAnnotation* = object
    number*: float
    coordinates*: seq[tuple[x, y: float]]
    text*: string                 ## "" for none

  WardleyNote* = object
    text*: string
    x*, y*: float

  WardleyForce* = object
    name*: string
    x*, y*: float

  WardleyAxesConfig* = object
    stages*: seq[string]
    stageBoundaries*: seq[float]
      ## Right edge of each stage, from 0 to 1.

  WardleyBuildResult* = object
    nodes*: seq[WardleyNode]
    links*: seq[WardleyLink]
    trends*: seq[WardleyTrend]
    pipelines*: seq[WardleyPipeline]
    annotations*: seq[WardleyAnnotation]
    notes*: seq[WardleyNote]
    accelerators*: seq[WardleyForce]
    deaccelerators*: seq[WardleyForce]
    annotationsBox*: Option[tuple[x, y: float]]
    axes*: WardleyAxesConfig
    size*: Option[tuple[width, height: float]]

  WardleyBuilder* = ref object
    nodes: OrderedTable[string, WardleyNode]
    labels: Option[Table[string, string]]
    links: seq[WardleyLink]
    trends: OrderedTable[string, WardleyTrend]
    pipelines: OrderedTable[string, WardleyPipeline]
    annotations: seq[WardleyAnnotation]
    notes: seq[WardleyNote]
    accelerators: seq[WardleyForce]
    deaccelerators: seq[WardleyForce]
    annotationsBox: Option[tuple[x, y: float]]
    axes: WardleyAxesConfig
    size: Option[tuple[width, height: float]]

proc addNode*(b: WardleyBuilder, node: NodeInput) =
  ## A node added again keeps its class and label offsets unless the new one sets them.
  let existing = b.nodes.getOrDefault(node.id, WardleyNode(id: node.id, label: node.label))
  let merged = WardleyNode(id: node.id, label: node.label, x: some(node.x), y: some(node.y),
    className: (if node.className != "": node.className else: existing.className),
    labelOffsetX: (if node.labelOffsetX.isSome: node.labelOffsetX else: existing.labelOffsetX),
    labelOffsetY: (if node.labelOffsetY.isSome: node.labelOffsetY else: existing.labelOffsetY),
    inPipeline: existing.inPipeline, isPipelineParent: existing.isPipelineParent,
    inertia: (if node.full: node.inertia else: existing.inertia),
    sourceStrategy: (if node.full: node.sourceStrategy else: existing.sourceStrategy))
  b.nodes[node.id] = merged
  b.labels = none(Table[string, string])

proc addLink*(b: WardleyBuilder, link: WardleyLink) = b.links.add link

proc addTrend*(b: WardleyBuilder, trend: WardleyTrend) = b.trends[trend.nodeId] = trend

proc startPipeline*(b: WardleyBuilder, nodeId: string) =
  b.pipelines[nodeId] = WardleyPipeline(nodeId: nodeId)
  if nodeId in b.nodes: b.nodes[nodeId].isPipelineParent = true

proc addPipelineComponent*(b: WardleyBuilder, pipelineNodeId, componentId: string) =
  if pipelineNodeId in b.pipelines: b.pipelines[pipelineNodeId].componentIds.add componentId
  if componentId in b.nodes: b.nodes[componentId].inPipeline = true

proc addAnnotation*(b: WardleyBuilder, annotation: WardleyAnnotation) = b.annotations.add annotation
proc addNote*(b: WardleyBuilder, note: WardleyNote) = b.notes.add note
proc addAccelerator*(b: WardleyBuilder, f: WardleyForce) = b.accelerators.add f
proc addDeaccelerator*(b: WardleyBuilder, f: WardleyForce) = b.deaccelerators.add f
proc setAnnotationsBox*(b: WardleyBuilder, x, y: float) = b.annotationsBox = some((x, y))

proc setAxes*(b: WardleyBuilder, stages: seq[string], stageBoundaries: seq[float]) =
  b.axes = WardleyAxesConfig(stages: stages, stageBoundaries: stageBoundaries)

proc setSize*(b: WardleyBuilder, width, height: float) = b.size = some((width, height))

proc getNode*(b: WardleyBuilder, id: string): WardleyNode = b.nodes.getOrDefault(id, nil)

proc resolveNodeId*(b: WardleyBuilder, name: string): string =
  ## A name is a node id, or else the label of the first node that has it. Pipeline components
  ## have ids like "Parent_Child" and are linked by label.
  if name in b.nodes: return name
  if b.labels.isNone:
    var labels = initTable[string, string]()
    for id, node in b.nodes:
      if node.label notin labels: labels[node.label] = id
    b.labels = some(labels)
  b.labels.get.getOrDefault(name, name)

proc build*(b: WardleyBuilder): WardleyBuildResult =
  for node in b.nodes.values:
    if node.x.isNone or node.y.isNone:
      raise newPeleError("Node \"" & node.label & "\" is missing coordinates", "semantic", "wardley")
    result.nodes.add node
  result.links = b.links
  for t in b.trends.values: result.trends.add t
  for p in b.pipelines.values: result.pipelines.add p
  result.annotations = b.annotations
  result.notes = b.notes
  result.accelerators = b.accelerators
  result.deaccelerators = b.deaccelerators
  result.annotationsBox = b.annotationsBox
  result.axes = b.axes
  result.size = b.size
