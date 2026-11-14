## port-of: src/diagrams/railroad/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import types, db, render

let railroad* = Diagram(
  diagramType: "railroad",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    parseRailroad(source, title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderRailroad(RailroadModel(model), config, options))
