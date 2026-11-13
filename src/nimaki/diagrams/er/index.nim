## port-of: src/diagrams/er/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let er* = Diagram(
  diagramType: "er",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newErDb()
    if title != "": db.title = title
    parseEr(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderEr(ErDb(model), config, options))
