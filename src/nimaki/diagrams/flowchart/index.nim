## port-of: src/diagrams/flowchart/index.ts
## port-status: draft
import std/options
import ../../types
import ../../preprocess
import ../../util/yaml
import db, parser, render

let flowchart* = Diagram(
  diagramType: "flowchart",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let flow = config["flowchart"]
    let inherit = flow["inheritDir"]
    let db = newFlowDb(FlowDbOptions(inheritDir: inherit != nil and inherit.kind == yBool and inherit.b,
                                     maxEdges: some(limits.maxEdges)))
    if title != "": db.title = title
    parseFlowchart(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderFlowchart(FlowDb(model), config, options))
