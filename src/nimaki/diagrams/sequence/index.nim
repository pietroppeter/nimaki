## port-of: src/diagrams/sequence/index.ts
## port-status: draft
import std/options
import ../../types
import ../../preprocess
import ../../util/yaml
import db, parser, render

let sequence* = Diagram(
  diagramType: "sequence",
  math: true,
  parse: proc (source: string, config: Config, title: string, lineOffset: int,
               limits: ParseLimits): RootRef =
    let seqConf = config["sequence"]
    let wrap = config["wrap"]
    let seqWrap = seqConf["wrap"]
    let db = newSeqDb(SeqDbOptions(
      wrap: (if wrap != nil and wrap.kind == yBool: some(wrap.b) else: none(bool)),
      sequenceWrap: some(seqWrap != nil and seqWrap.kind == yBool and seqWrap.b)))
    if title != "": db.setDiagramTitle(title)
    parseSequence(source, db)
    db,
  render: proc (model: RootRef, config: Config, options: RenderOptions): Rendered =
    renderSequence(SeqDb(model), config, options))
