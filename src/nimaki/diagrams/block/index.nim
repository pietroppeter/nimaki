## port-of: src/diagrams/block/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let blockDiagram* = Diagram(
  diagramType: "block",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newBlockDb()
    db.title = title
    parseBlock(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderBlock(BlockDb(model), config, options))
