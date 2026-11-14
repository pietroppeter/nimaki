## port-of: src/diagrams/kanban/parser.ts
## port-status: conformant
import ../common/outline
import db

proc tokenize*(src: string): Tokens = outline.tokenize(src, true)

proc parseKanban*(src: string, db: KanbanDb) =
  parseOutline(src, true,
    proc (node: OutlineNode) =
      db.addNode(node.level, node.id, node.descr, node.kind, node.hasShapeData, node.shapeData),
    proc (decoration: Decoration) = db.decorateNode(decoration))
