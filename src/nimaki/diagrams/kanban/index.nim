## port-of: src/diagrams/kanban/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import db, parser, render

let kanban* = Diagram(
  diagramType: "kanban",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = KanbanDb(title: title)
    parseKanban(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderKanban(KanbanModel(model), config, options))
