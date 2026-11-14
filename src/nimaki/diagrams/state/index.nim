## port-of: src/diagrams/state/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let state* = Diagram(
  diagramType: "state",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let db = newStateDb()
    if title != "": db.title = title
    discard parseState(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderState(StateDb(model), config, options))
