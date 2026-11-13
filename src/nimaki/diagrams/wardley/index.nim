## port-of: src/diagrams/wardley/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import model, parser, render

let wardley* = Diagram(
  diagramType: "wardley",
  section: "wardley-beta",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildWardley(parseWardley(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderWardley(WardleyModel(model), config, options))
