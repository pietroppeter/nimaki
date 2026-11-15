## port-of: src/diagrams/sankey/db.ts
## port-status: conformant
##
## A link holds the node objects of its ends, as Pele's does; the layout reads their `index`.
import std/tables

type
  SankeyNode* = ref object
    id*: string
    index*: int

  SankeyLink* = object
    source*, target*: SankeyNode
    value*: float

  SankeyDb* = ref object of RootObj
    nodes*: seq[SankeyNode]
    links*: seq[SankeyLink]
    title*, accTitle*, accDescr*: string   ## "" for undefined
    lookup: Table[string, SankeyNode]

  SankeyModel* = SankeyDb

proc findOrCreateNode*(db: SankeyDb, id: string): SankeyNode =
  result = db.lookup.getOrDefault(id)
  if result == nil:
    result = SankeyNode(id: id, index: db.nodes.len)
    db.lookup[id] = result
    db.nodes.add result

proc addLink*(db: SankeyDb, source, target: SankeyNode, value: float) =
  db.links.add SankeyLink(source: source, target: target, value: value)
