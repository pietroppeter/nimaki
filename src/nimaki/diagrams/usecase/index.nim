## port-of: src/diagrams/usecase/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import parser, render
import types as usecaseTypes

let usecase* = Diagram(
  diagramType: "usecase",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    parseUsecase(source, title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderUsecase(UsecaseModel(model), config, options))
