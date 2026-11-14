## port-of: src/diagrams/c4/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let c4* = Diagram(
  diagramType: "c4",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newC4Db()
    if title != "": db.title = title
    parseC4(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderC4(C4Db(model), config, options))
