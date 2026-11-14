## port-of: src/diagrams/journey/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let journey* = Diagram(
  diagramType: "journey",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = JourneyDb()
    db.title = title
    parseJourney(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderJourney(JourneyModel(model), config, options))
