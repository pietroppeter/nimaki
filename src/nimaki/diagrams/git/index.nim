## port-of: src/diagrams/git/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import db, parser, render

let gitGraph* = Diagram(
  diagramType: "gitGraph",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildGit(parseGit(source), config, title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderGit(GitModel(model), config, options))
