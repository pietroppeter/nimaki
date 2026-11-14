## port-of: src/diagrams/info/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import model, parser, render

let info* = Diagram(
  diagramType: "info",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildInfo(parseInfo(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderInfo(InfoModel(model), config, options))
