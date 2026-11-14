## port-of: src/diagrams/radar/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import model, parser, render

let radar* = Diagram(
  diagramType: "radar",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildRadar(parseRadar(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderRadar(RadarModel(model), config, options))
