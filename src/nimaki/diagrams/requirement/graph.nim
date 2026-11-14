## port-of: src/diagrams/requirement/graph.ts
## port-status: conformant
import std/[strutils, tables]
import db, types

type
  GraphNode* = object
    id*: string
    requirement*: Requirement           ## nil for undefined
    element*: RequirementElement        ## nil for undefined
    cssStyles*: seq[string]
    cssClasses*: string

  GraphEdge* = object
    id*: string
    start*: string                      ## "" for undefined
    stop*: string                       ## Pele's `end`; "" for undefined
    hasStart*, hasStop*: bool
    kind*: string
    contains*: bool

  RequirementGraph* = object
    nodes*: seq[GraphNode]
    edges*: seq[GraphEdge]
    direction*: string

# The nodes and edges to lay out: requirements first, then elements, as Mermaid orders them.
proc buildRequirementGraph*(model: RequirementDb): RequirementGraph =
  for requirement in model.requirements.values:
    result.nodes.add GraphNode(id: requirement.name, requirement: requirement, cssStyles: requirement.cssStyles,
                               cssClasses: requirement.classes.join(" "))
  for element in model.elements.values:
    result.nodes.add GraphNode(id: element.name, element: element, cssStyles: element.cssStyles,
                               cssClasses: element.classes.join(" "))
  proc has(id: string): bool = model.requirements.hasKey(id) or model.elements.hasKey(id)
  for index, relation in model.relations:
    result.edges.add GraphEdge(
      id: relation.src & "-" & relation.dst & "-" & $index,
      start: relation.src, hasStart: has(relation.src),
      stop: relation.dst, hasStop: has(relation.dst),
      kind: relation.kind,
      contains: relation.kind == CONTAINS,
    )
  result.direction = model.direction
