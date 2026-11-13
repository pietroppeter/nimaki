## port-of: src/diagrams/mindmap/db.ts
## port-status: draft
import ../../errors
import ../common/outline

type
  MindmapNode* = ref object
    id*: int
    nodeId*: string
    level*: int
    descr*: string
    kind*: int                ## Pele's `type`: Mermaid's node type
    children*: seq[MindmapNode]
    isRoot*: bool
    section*: int
      ## Index of the first-level branch the node belongs to, wrapping after eleven as in
      ## Mermaid. 0 for the root, which has none (Pele's `section ?? 0` everywhere it is read).
    class*: string            ## "" for undefined
    icon*: string             ## "" for undefined

  MindmapDb* = ref object of RootObj
    ## Pele's MindmapDb, which is also the MindmapModel.
    title*: string            ## "" for undefined
    nodes*: seq[MindmapNode]
      ## In source order, which is depth-first. The first node is the root.
    baseLevel: int
    open: seq[MindmapNode]
      ## The chain of nodes that can still take children, with strictly increasing levels.

  MindmapModel* = MindmapDb

const SECTIONS = 11

proc addNode*(db: MindmapDb, level: int, id, descr: string, kind: int) =
  let isRoot = db.nodes.len == 0
  if isRoot: db.baseLevel = level
  let level = level - db.baseLevel

  # Mermaid's parent is the last node with a smaller indentation, wherever it is in the tree.
  var depth = db.open.len
  while depth > 0 and db.open[depth - 1].level >= level: dec depth
  let parent = if depth > 0: db.open[depth - 1] else: nil
  if parent == nil and not isRoot:
    raise newPeleError("There can be only one root. No parent could be found for (\"" & descr & "\")",
                       "semantic", ErrorInfo(diagramType: "mindmap"))
  let node = MindmapNode(id: db.nodes.len, nodeId: id, level: level, descr: descr, kind: kind, isRoot: isRoot)
  if parent != nil:
    node.section = if parent.isRoot: parent.children.len mod SECTIONS else: parent.section
    parent.children.add node
  db.open.setLen depth
  db.open.add node
  db.nodes.add node

proc decorateNode*(db: MindmapDb, decoration: Decoration) =
  ## Mermaid throws a TypeError when a decoration comes before any node. Here it is ignored.
  if db.nodes.len == 0: return
  let node = db.nodes[^1]
  if decoration.icon != "": node.icon = decoration.icon
  if decoration.class != "": node.class = decoration.class
