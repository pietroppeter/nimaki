## port-of: src/diagrams/mindmap/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let mindmap* = Diagram(
  diagramType: "mindmap",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = MindmapDb(title: title)
    parseMindmap(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderMindmap(MindmapModel(model), config, options))
