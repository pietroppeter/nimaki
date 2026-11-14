## port-of: src/diagrams/wardley/model.ts
## port-status: draft
import std/[options, strutils]
import ../../errors
import ../../js
import builder, parser
import ../../jsregex

type
  WardleyModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    built*: WardleyBuildResult              ## Pele spreads it into the model

proc toPercent(value: float, context: string): float =
  ## Values up to 1 are fractions; larger ones are already percentages.
  let normalized = if value <= 1: value * 100 else: value
  if normalized < 0 or normalized > 100:
    raise newPeleError(context & " must be between 0-1 (decimal) or 0-100 (percentage). Received: " &
                       jsString(value), "semantic", "wardley")
  normalized

proc toCoordinates(visibility, evolution: float, context: string): tuple[x, y: float] =
  let x = toPercent(evolution, context & " evolution")
  (x, toPercent(visibility, context & " visibility"))

func flowFromPort(port: string): string =
  if port == "+<>": "bidirectional" elif port == "+<": "backward" elif port == "+>": "forward" else: ""

func flowFromArrow(arrow: string): tuple[flow: string, label: Option[string]] =
  if not arrow.startsWith("+"): return
  let stop = arrow.find('\'', 2)
  if arrow.len > 1 and arrow[1] == '\'' and stop != -1: result.label = some(arrow[2 ..< stop])
  if "<>" in arrow: result.flow = "bidirectional"
  elif "<" in arrow: result.flow = "backward"
  elif ">" in arrow: result.flow = "forward"

func offsets(label: Option[LabelAst]): (Option[float], Option[float]) =
  if label.isNone: return (none(float), none(float))
  let l = label.get
  (some((if l.negX: -1.0 else: 1.0) * l.offsetX), some((if l.negY: -1.0 else: 1.0) * l.offsetY))

proc populate*(ast: WardleyAst, db: WardleyBuilder) =
  ## Mermaid's populateDb: fills the builder from the syntax tree, in Mermaid's order.
  if ast.size.isSome: db.setSize(ast.size.get.width, ast.size.get.height)

  if ast.evolution.isSome:
    var stages: seq[string]
    var boundaries: seq[float]
    for stage in ast.evolution.get:
      stages.add(if stage.secondName.isSome: jsTrim(stage.name) & " / " & jsTrim(stage.secondName.get)
                 else: jsTrim(stage.name))
      if stage.boundary.isSome: boundaries.add stage.boundary.get
    db.setAxes(stages, boundaries)

  for anchor in ast.anchors:
    let at = toCoordinates(anchor.visibility, anchor.evolution, "Anchor \"" & anchor.name & "\"")
    db.addNode(NodeInput(id: anchor.name, label: anchor.name, x: at.x, y: at.y, className: "anchor"))

  for component in ast.components:
    let at = toCoordinates(component.visibility, component.evolution, "Component \"" & component.name & "\"")
    let (ox, oy) = offsets(component.label)
    db.addNode(NodeInput(id: component.name, label: component.name, x: at.x, y: at.y, className: "component",
                         labelOffsetX: ox, labelOffsetY: oy, full: true, inertia: some(component.inertia),
                         sourceStrategy: component.decorator))

  for note in ast.notes:
    let at = toCoordinates(note.visibility, note.evolution, "Note \"" & note.text & "\"")
    db.addNote(WardleyNote(text: note.text, x: at.x, y: at.y))

  for pipeline in ast.pipelines:
    let parent = db.getNode(pipeline.parent)
    if parent == nil or parent.y.isNone:
      raise newPeleError("Pipeline \"" & pipeline.parent & "\" must reference an existing component with coordinates.",
                         "semantic", "wardley")
    let y = parent.y.get
    db.startPipeline(pipeline.parent)
    for component in pipeline.components:
      let id = pipeline.parent & "_" & component.name
      let (ox, oy) = offsets(component.label)
      let x = toPercent(component.evolution, "Pipeline component \"" & component.name & "\" evolution")
      db.addNode(NodeInput(id: id, label: component.name, x: x, y: y, className: "pipeline-component",
                           labelOffsetX: ox, labelOffsetY: oy, full: true))
      db.addPipelineComponent(pipeline.parent, id)

  for link in ast.links:
    let dashed = link.arrow != "" and ("-.->" in link.arrow or ".-." in link.arrow)
    let fromArrow = flowFromArrow(link.arrow)
    var flow = flowFromPort(link.fromPort)
    if flow == "": flow = flowFromPort(link.toPort)
    if flow == "": flow = fromArrow.flow
    db.addLink(WardleyLink(source: db.resolveNodeId(link.start), target: db.resolveNodeId(link.to),
                           dashed: dashed, label: (if fromArrow.label.isSome: fromArrow.label else: link.linkLabel),
                           flow: flow))

  for evolve in ast.evolves:
    let node = db.getNode(evolve.component)
    if node != nil and node.y.isSome:
      db.addTrend(WardleyTrend(nodeId: evolve.component,
                               targetX: toPercent(evolve.target, "Evolve target for \"" & evolve.component & "\""),
                               targetY: node.y.get))

  if ast.annotations.len > 0:
    let at = toCoordinates(ast.annotations[0].x, ast.annotations[0].y, "Annotations box")
    db.setAnnotationsBox(at.x, at.y)

  for annotation in ast.annotation:
    let at = toCoordinates(annotation.x, annotation.y, "Annotation " & jsString(annotation.number))
    db.addAnnotation(WardleyAnnotation(number: annotation.number, coordinates: @[(at.x, at.y)], text: annotation.text))

  for accelerator in ast.accelerators:
    let at = toCoordinates(accelerator.x, accelerator.y, "Accelerator \"" & accelerator.name & "\"")
    db.addAccelerator(WardleyForce(name: accelerator.name, x: at.x, y: at.y))

  for deaccelerator in ast.deaccelerators:
    let at = toCoordinates(deaccelerator.x, deaccelerator.y, "Deaccelerator \"" & deaccelerator.name & "\"")
    db.addDeaccelerator(WardleyForce(name: deaccelerator.name, x: at.x, y: at.y))

func dropBreakSpaces(text: string): string =
  text.replace(jsre"/\n\s+/g", "\n")

proc buildWardley*(ast: WardleyAst, title: string): WardleyModel =
  let db = WardleyBuilder()
  populate(ast, db)
  WardleyModel(
    title: (if ast.title != "": ast.title else: title),
    accTitle: (if ast.accTitle != "": ast.accTitle.replace(jsre"/^\s+/g", "") else: ""),
    accDescr: (if ast.accDescr != "": dropBreakSpaces(ast.accDescr) else: ""),
    built: db.build())
