## port-of: src/diagrams/treeview/index.ts
## port-status: conformant
import ../../types
import ../../preprocess
import model, render

let treeView* = Diagram(
  diagramType: "treeView",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildTreeView(readTreeView(source), title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderTreeView(TreeViewModel(model), config, options))
