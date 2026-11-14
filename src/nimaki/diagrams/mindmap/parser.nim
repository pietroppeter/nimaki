## port-of: src/diagrams/mindmap/parser.ts
## port-status: conformant
import ../common/outline
import db

proc tokenize*(src: string): Tokens = outline.tokenize(src, false)

proc parseMindmap*(src: string, db: MindmapDb) =
  parseOutline(src, false,
    proc (node: OutlineNode) = db.addNode(node.level, node.id, node.descr, node.kind),
    proc (decoration: Decoration) = db.decorateNode(decoration))
