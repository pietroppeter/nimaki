## port-of: src/diagrams/architecture/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let architecture* = Diagram(
  diagramType: "architecture",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = ArchitectureDb()
    if title != "": db.title = title
    populate(parseArchitecture(source), db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderArchitecture(ArchitectureDb(model), config, options))
