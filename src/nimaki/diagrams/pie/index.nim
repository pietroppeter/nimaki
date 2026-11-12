## port-of: src/diagrams/pie/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import model, parser, render

let pie* = Diagram(
  diagramType: "pie",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildPie(parsePie(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderPie(PieModel(model), config, options))
