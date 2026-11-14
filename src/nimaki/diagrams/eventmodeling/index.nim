## port-of: src/diagrams/eventmodeling/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import model, parser, render

let eventmodeling* = Diagram(
  diagramType: "eventmodeling",
  keepComments: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildEventModel(parseEventModel(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderEventModel(EventModelingModel(model), config, options))
