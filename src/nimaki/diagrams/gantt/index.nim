## port-of: src/diagrams/gantt/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import ../../util/yaml
import db, parser, render

let gantt* = Diagram(
  diagramType: "gantt",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let model = newGanttDb()
    if title != "": model.title = title
    let mode = config["gantt"]["displayMode"]
    if mode != nil and mode.kind == yString: model.displayMode = mode.s
    parseGantt(source, model)
    model,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderGantt(GanttDb(model), config, options))
