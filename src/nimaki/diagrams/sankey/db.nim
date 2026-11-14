## port-of: src/diagrams/sankey/db.ts
## port-status: conformant
##
## A link names its ends by their index in `nodes` (Pele keeps the node objects themselves).
import std/tables

type
  SankeyNode* = object
    id*: string
    index*: int

  SankeyLink* = object
    source*, target*: int   ## indices in `nodes`
    value*: float

  SankeyDb* = ref object of RootObj
    nodes*: seq[SankeyNode]
    links*: seq[SankeyLink]
    title*, accTitle*, accDescr*: string   ## "" for undefined
    lookup: Table[string, int]

  SankeyModel* = SankeyDb

proc findOrCreateNode*(db: SankeyDb, id: string): int =
  if id notin db.lookup:
    db.lookup[id] = db.nodes.len
    db.nodes.add SankeyNode(id: id, index: db.nodes.len)
  db.lookup[id]

proc addLink*(db: SankeyDb, source, target: int, value: float) =
  db.links.add SankeyLink(source: source, target: target, value: value)
