## port-of: src/diagrams/ishikawa/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let ishikawa* = Diagram(
  diagramType: "ishikawa",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = IshikawaDb()
    db.title = title
    parseIshikawa(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderIshikawa(IshikawaDb(model), config, options))
