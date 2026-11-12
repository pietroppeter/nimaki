## port-of: src/diagrams/swimlane/index.ts
## port-status: draft
import std/options
import ../../layout/[compound, lanes, layered]
import ../../svg/[builder, ink, theme]
import ../../text/[icons, label]
import ../../types
import ../../preprocess
import ../flowchart/[db, graph, render]
import ../flowchart/index as flowchartIndex

const DEFAULT_LANE = "__swimlane_default__"

proc prepare(graph: var FlowGraph) =
  ## Nodes outside every lane share one unnamed lane, as in Mermaid. Lanes all run the same way,
  ## so a `direction` inside a subgraph has no effect.
  var loose = false
  for node in graph.nodes:
    if node.isGroup: node.dir = ""
    elif node.parentId.isNone: loose = true
  if not loose: return
  for node in graph.nodes:
    if not node.isGroup and node.parentId.isNone: node.parentId = some(DEFAULT_LANE)
  graph.nodes.add GraphNode(id: DEFAULT_LANE, label: "", labelType: "text", shape: "rect",
                            isGroup: true, parentId: none(string), cssStyles: @[],
                            cssCompiledStyles: @[], cssClasses: "", dir: "")

proc drawLane(c: CNode, label: Label, style: ResolvedStyle, classes, id: string, dir: Dir,
              icons: IconResolver): string =
  ## A lane: an outline the length of the diagram, with its title in a band at the start.
  let left = c.x - c.w / 2
  let top = c.y - c.h / 2
  let sideways = dir == "LR" or dir == "RL"
  let cx = if sideways: left + c.padTop / 2 else: c.x
  let cy = if sideways: c.y else: top + c.padTop / 2
  let text = labelSvg(label, cx, cy, " class=\"pele-cluster-label\"" & inkFill(style.shape, style.text, "var(--_m)") &
                      style.text, icons)
  "<g class=\"pele-cluster pele-lane" & classes & "\" data-id=\"" & id & "\">" &
    "<rect x=\"" & num(left) & "\" y=\"" & num(top) & "\" width=\"" & num(c.w) & "\" height=\"" & num(c.h) &
    "\" fill=\"none\" stroke=\"var(--_b)\"/>" &
    "<rect x=\"" & num(left) & "\" y=\"" & num(top) & "\" width=\"" & num(if sideways: c.padTop else: c.w) &
    "\" height=\"" & num(if sideways: c.h else: c.padTop) & "\" fill=\"var(--_a)\" stroke=\"var(--_b)\"" &
    style.shape & "/>" &
    (if sideways and text != "": "<g transform=\"rotate(-90 " & num(cx) & " " & num(cy) & ")\">" & text & "</g>"
     else: text) &
    "</g>"

proc laneBand(c: CNode, dir: Dir): array[4, float] =
  let left = c.x - c.w / 2
  let top = c.y - c.h / 2
  if dir == "LR" or dir == "RL": [left, top, left + c.padTop, top + c.h]
  else: [left, top, left + c.w, top + c.padTop]

let variant = FlowVariant(
  kind: "swimlane",
  prepare: prepare,
  layout: proc (nodes: seq[CNode], edges: seq[CEdge], dir: Dir, opt: LayeredOptions, tight: bool): CompoundResult =
    laneLayout(nodes, edges, dir, opt, if tight: 12.0 else: LANE_PAD),
  drawGroup: drawLane,
  filledBox: laneBand)

let swimlane* = Diagram(
  ## A swimlane diagram is a flowchart whose top-level subgraphs are lanes: same syntax, same model.
  diagramType: "swimlane",
  math: true,
  parse: flowchartIndex.flowchart.parse,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderFlowchart(FlowDb(model), config, options, variant))
