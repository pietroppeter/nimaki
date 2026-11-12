## port-of: src/diagrams/treemap/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import model, parser, render

let treemap* = Diagram(
  diagramType: "treemap",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildTreemap(parseTreemap(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderTreemap(TreemapModel(model), config, options))
