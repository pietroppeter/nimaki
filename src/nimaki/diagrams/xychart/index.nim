## port-of: src/diagrams/xychart/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let xychart* = Diagram(
  diagramType: "xychart",
  section: "xyChart",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newXyChartDb()
    db.title = title
    parseXyChart(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderXyChart(XyChartDb(model), config, options))
