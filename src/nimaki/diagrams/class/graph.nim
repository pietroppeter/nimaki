## port-of: src/diagrams/class/graph.ts
## port-status: draft
import std/tables
import db

type
  NodeShape* = string ## 'rect' | 'classBox' | 'note' | 'interface'
  EndMarker* = string ## 'aggregation' | 'extension' | 'composition' | 'dependency' | 'lollipop' | 'none'

  GraphNode* = ref object
    id*: string
    label*: string
    isGroup*: bool
    shape*: NodeShape
    parentId*: string     ## "" for undefined
    parent*: int
      ## Index of the namespace node this one is drawn in, or -1.
    classNode*: ClassNode ## nil for none
    colorIndex*: int
      ## Position among the classes, in declaration order. Namespaces and notes have none (-1).

  GraphEdge* = ref object
    id*: string
    start*, stop*: string
    source*, target*: int
      ## Indexes into the node list. Ids alone are ambiguous: a class may be named `note0` or `interface0`.
    label*: string        ## "" for undefined
    arrowTypeStart*, arrowTypeEnd*: EndMarker
    startLabelRight*, endLabelLeft*: string
    pattern*: string      ## 'solid' | 'dashed' | 'dotted'
    classes*: string

  ClassGraph* = object
    nodes*: seq[GraphNode]
    edges*: seq[GraphEdge]

const MARKERS = ["aggregation", "extension", "composition", "dependency", "lollipop"]

func marker(kind: RelationEnd): EndMarker =
  if kind >= 0 and kind < MARKERS.len: MARKERS[kind] else: "none"

proc buildClassGraph*(model: ClassDb, hierarchical = true): ClassGraph =
  ## Resolves a parsed class diagram into the nodes and edges that are drawn. With `hierarchical`
  ## off, only namespaces the source declares are kept and each is labeled with its full name.
  var nodes: seq[GraphNode]
  var edges: seq[GraphEdge]
  var namespaceAt = initTable[string, int]()
  var classAt = initTable[string, int]()
  var interfaceAt = initTable[string, int]()

  var declared = initTable[string, string]()
  proc declaredAncestor(id: string): string =
    if hierarchical or id == "": return id
    var chain: seq[string]
    var current = id
    var found = ""
    while current != "":
      if current in declared:
        found = declared[current]
        break
      let ns = model.namespaces.getOrDefault(current, nil)
      if ns == nil: break
      if ns.explicit:
        found = current
        break
      chain.add current
      current = ns.parent
    for visited in chain: declared[visited] = found
    found
  proc group(id: string): int = (if id == "": -1 else: namespaceAt.getOrDefault(id, -1))

  for ns in model.namespaces.values:
    if not hierarchical and not ns.explicit: continue
    namespaceAt[ns.id] = nodes.len
    nodes.add GraphNode(id: ns.id, label: (if hierarchical: ns.label else: ns.id), isGroup: true,
                        shape: "rect", parentId: (if hierarchical: ns.parent else: ""), parent: -1,
                        colorIndex: -1)
  for node in nodes: node.parent = group(node.parentId)

  var colorIndex = 0
  for classNode in model.classes.values:
    let parentId = declaredAncestor(classNode.parent)
    classAt[classNode.id] = nodes.len
    nodes.add GraphNode(id: classNode.id, label: classNode.label, isGroup: false, shape: "classBox",
                        parentId: parentId, parent: group(parentId), classNode: classNode,
                        colorIndex: colorIndex)
    inc colorIndex

  for note in model.notes.values:
    let parentId = declaredAncestor(note.parent)
    let target = if note.class == "": -1 else: classAt.getOrDefault(note.class, -1)
    if target >= 0:
      edges.add GraphEdge(id: "edgeNote" & $note.index, start: note.id, stop: nodes[target].id,
                          source: nodes.len, target: target, label: "", arrowTypeStart: "none",
                          arrowTypeEnd: "none", startLabelRight: "", endLabelLeft: "",
                          pattern: "dotted", classes: "relation")
    nodes.add GraphNode(id: note.id, label: note.text, isGroup: false, shape: "note",
                        parentId: parentId, parent: group(parentId), colorIndex: -1)

  # Mermaid leaves every lollipop interface outside the namespaces. Here it stays beside its class.
  for item in model.interfaces:
    let owner = classAt.getOrDefault(item.classId, -1)
    interfaceAt[item.id] = nodes.len
    nodes.add GraphNode(id: item.id, label: item.label, isGroup: false, shape: "interface",
                        parentId: "", parent: (if owner < 0: -1 else: nodes[owner].parent),
                        colorIndex: -1)

  var count = 0
  for relation in model.relations:
    inc count
    let type1 = relation.relation.type1
    let type2 = relation.relation.type2
    # addRelation swaps in an interface for the lollipop end of a relation with no other marker.
    let startIsInterface = type1 == LOLLIPOP and type2 == NONE
    let endIsInterface = not startIsInterface and type2 == LOLLIPOP and type1 == NONE
    edges.add GraphEdge(
      id: "id_" & relation.id1 & "_" & relation.id2 & "_" & $count,
      start: relation.id1,
      stop: relation.id2,
      source: (if startIsInterface: interfaceAt else: classAt).getOrDefault(relation.id1, -1),
      target: (if endIsInterface: interfaceAt else: classAt).getOrDefault(relation.id2, -1),
      label: relation.title,
      arrowTypeStart: marker(type1),
      arrowTypeEnd: marker(type2),
      startLabelRight: (if relation.relationTitle1 == "none": "" else: relation.relationTitle1),
      endLabelLeft: (if relation.relationTitle2 == "none": "" else: relation.relationTitle2),
      pattern: (if relation.relation.lineType == 1: "dashed" else: "solid"),
      classes: "relation")

  ClassGraph(nodes: nodes, edges: edges)
