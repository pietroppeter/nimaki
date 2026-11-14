## port-of: src/diagrams/cynefin/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import model, parser, render

let cynefin* = Diagram(
  diagramType: "cynefin",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildCynefin(parseCynefin(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderCynefin(CynefinModel(model), config, options))
