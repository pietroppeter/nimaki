## port-of: src/diagrams/timeline/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let timeline* = Diagram(
  diagramType: "timeline",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newTimelineDb()
    db.title = title
    parseTimeline(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderTimeline(TimelineModel(model), config, options))
