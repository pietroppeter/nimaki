## port-of: src/diagrams/class/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let classDiagram* = Diagram(
  diagramType: "class",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newClassDb()
    if title != "": db.title = title
    parseClassDiagram(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderClass(ClassDb(model), config, options))
