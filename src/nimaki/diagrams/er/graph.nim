## port-of: src/diagrams/er/graph.ts
## port-status: conformant
import std/[options, sets, strutils, tables]
import ../../js
import db, types

type
  ErGraphNode* = object
    id*: string
    label*: string
    alias*: string
    attributes*: seq[ErAttribute]
    isGroup*: bool
    parentId*: Option[string]
    cssStyles*: seq[string]
    cssCompiledStyles*: seq[string]
    cssClasses*: string
    dir*: string                 ## "" for undefined
    labelType*: string

  ErGraphEdge* = object
    id*: string
    start*: string
    stop*: string                ## Pele's `end`
    label*: string
    arrowTypeStart*: string
    arrowTypeEnd*: string
    dashed*: bool                ## `pattern: 'dashed'` (else 'solid')

  ErGraph* = object
    nodes*: seq[ErGraphNode]
    edges*: seq[ErGraphEdge]

# Resolves a parsed ER diagram into what is drawn: subgraphs as groups, entities as nodes with
# their class styles, and relationships as edges with a marker type at each end.
proc buildErGraph*(model: ErDb): ErGraph =
  let subgraphs = model.subgraphs

  proc compiled(classNames: seq[string]): seq[string] =
    for name in classNames:
      let def = model.classes.getOrDefault(name, nil)
      if def == nil: continue
      for style in def.styles: result.add style.jsTrim
      for style in def.textStyles: result.add style.jsTrim

  var parentOf = initTable[string, string]()
  var subgraphIds = initHashSet[string]()
  for i in countdown(subgraphs.high, 0):
    let subgraph = subgraphs[i]
    subgraphIds.incl subgraph.id
    for id in subgraph.nodes: parentOf[id] = subgraph.id

  proc parent(id: string): Option[string] =
    if parentOf.hasKey(id): some(parentOf[id]) else: none(string)

  for i in countdown(subgraphs.high, 0):
    let subgraph = subgraphs[i]
    result.nodes.add ErGraphNode(
      id: subgraph.id,
      label: subgraph.title,
      isGroup: true,
      parentId: parent(subgraph.id),
      cssStyles: subgraph.cssStyles,
      cssCompiledStyles: compiled(subgraph.classes),
      cssClasses: subgraph.classes.join(" "),
      dir: subgraph.dir,
      labelType: subgraph.labelType,
    )

  # A name that is also a subgraph id stands for the subgraph. Mermaid drops such an entity and
  # leaves relationships written before the subgraph pointing at nothing; here they follow it.
  var moved = initTable[string, string]()
  for name, entity in model.entities:
    if name in subgraphIds:
      moved[entity.id] = name
      continue
    result.nodes.add ErGraphNode(
      id: entity.id,
      label: entity.label,
      alias: entity.alias,
      attributes: entity.attributes,
      isGroup: false,
      parentId: parent(name),
      cssStyles: entity.cssStyles,
      cssCompiledStyles: compiled(entity.cssClasses.split(' ')),
      cssClasses: entity.cssClasses,
      labelType: "markdown",
    )

  for index, relationship in model.relationships:
    result.edges.add ErGraphEdge(
      id: "id_" & relationship.entityA & "_" & relationship.entityB & "_" & $index,
      start: moved.getOrDefault(relationship.entityA, relationship.entityA),
      stop: moved.getOrDefault(relationship.entityB, relationship.entityB),
      label: relationship.roleA,
      arrowTypeStart: relationship.relSpec.cardB.toLowerAscii,
      arrowTypeEnd: relationship.relSpec.cardA.toLowerAscii,
      dashed: relationship.relSpec.relType != "IDENTIFYING",
    )
