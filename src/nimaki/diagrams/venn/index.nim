## port-of: src/diagrams/venn/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let venn* = Diagram(
  diagramType: "venn",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = VennDb()
    if title != "": db.title = title
    parseVenn(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderVenn(VennDb(model), config, options))
