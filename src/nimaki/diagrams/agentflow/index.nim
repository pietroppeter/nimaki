## port-of: src/diagrams/agentflow/index.ts
## port-status: draft
import std/options
import ../../types
import ../../preprocess
import ../../util/yaml
import db, parser, render

let agentflow* = Diagram(
  diagramType: "agentflow",
  keepComments: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    # Mermaid reads this setting from the flowchart section for agentflow too.
    let inherit = config["flowchart"]["inheritDir"]
    let dir = config["direction"]
    let db = newAgentflowDb(AgentflowDbOptions(
      inheritDir: inherit != nil and inherit.kind == yBool and inherit.b,
      direction: if dir != nil and dir.kind == yString: dir.s else: "",
      lineOffset: lineOffset,
      source: some(source),
      maxEdges: some(limits.maxEdges)))
    if title != "": db.title = title
    parseAgentflow(source, db)
    discard agentGraph(db, config)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderAgentflow(AgentflowDb(model), config, options))
