## port-of: src/diagrams/packet/index.ts
## port-status: draft
import ../../types
import ../../preprocess
import model, parser, render

let packet* = Diagram(
  diagramType: "packet",
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    buildPacket(parsePacket(source), config, title),
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderPacket(PacketModel(model), config, options))
