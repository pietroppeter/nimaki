## port-of: src/diagrams/requirement/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let requirement* = Diagram(
  diagramType: "requirement",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newRequirementDb()
    if title != "": db.title = title
    parseRequirement(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderRequirement(RequirementDb(model), config, options))
