## port-of: src/diagrams/sankey/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let sankey* = Diagram(
  diagramType: "sankey",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = SankeyDb()
    if title != "": db.title = title
    parseSankey(prepareTextForParsing(source), db, source)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderSankey(SankeyModel(model), config, options))
