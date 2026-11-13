## port-of: src/diagrams/usecase/graph.ts
## port-status: draft
import std/[strutils, tables]
import ../../js
import json, types

type
  JsonRow* = object
    key*: string             ## blank on the second and later values of an array
    accessibleKey*: string   ## the key again, for every row
    value*: string

  UsecaseGraphNode* = ref object
    id*, label*: string
    markdown*: bool
    shape*: string           ## Mermaid's shape names
    isGroup*: bool
    padding*: float
    cssClasses*: string
    cssStyles*, cssCompiledStyles*: seq[string]
    actorType*: string       ## "" for undefined
    business*: bool
    icon*: string
    stereotype*: string
    parentId*: string        ## "" for undefined
    noteTarget*: string
    isJson*: bool
    jsonRows*: seq[JsonRow]
    boundaryType*: string

  UsecaseGraphEdge* = ref object
    id*, start*, stop*: string
    relationshipType*: string
    pattern*: string         ## solid or dotted
    arrowTypeStart*, arrowTypeEnd*: string
    label*: string           ## "" for undefined
    labelMarkdown*: bool
    classes*: string
    style*, cssCompiledStyles*: seq[string]
    animate*: bool
    animation*: string
    minlen*: int
    explicitId*: bool
    internal*: bool          ## the dotted line from a note to what it is about

  UsecaseGraph* = object
    nodes*: seq[UsecaseGraphNode]
    edges*: seq[UsecaseGraphEdge]

const ACTOR_SHAPES = {"normal": "usecaseActor", "hollow": "usecaseActorHollow",
                      "awesome": "usecaseActorAwesome", "icon": "usecaseActorIcon"}.toTable

# Start and end markers for each arrow type, in the order of the Arrow enum.
const MARKERS = [
  ["none", "arrow_point"],
  ["arrow_point", "none"],
  ["none", "none"],
  ["none", "arrow_circle"],
  ["none", "arrow_cross"],
  ["arrow_circle", "none"],
  ["arrow_cross", "none"],
]

proc scalar(value: JsonValue, present = true): string =
  if not present: return "undefined"
  case value.kind
  of jString: value.s
  of jNull: "null"
  of jBool: (if value.b: "true" else: "false")
  of jNumber: jsString(value.n)
  of jArray:
    # String([...]): only reached for an array of scalars inside an array, which is not flattened.
    var parts: seq[string]
    for item in value.items:
      parts.add(if item.kind == jNull: "" else: scalar(item))
    parts.join(",")
  of jObject: "[object Object]"

proc flattenJsonRows*(value: JsonValue, propertyOrder: Table[string, seq[string]]): seq[JsonRow] =
  ## One row for each leaf of a JSON object, depth first in the order the keys were written.
  ## Nesting is kept on a stack of its own, so depth is limited by memory and not by the call stack.
  type Entry = tuple[value: JsonValue, present: bool, path, pointer: string]
  var rows: seq[JsonRow]
  var stack: seq[Entry] = @[(value, true, "", "")]
  var children: seq[Entry]
  while stack.len > 0:
    let (current, present, path, pointer) = stack.pop()
    children.setLen 0
    if present and current.kind == jArray:
      if current.items.len == 0: rows.add JsonRow(key: path, accessibleKey: path, value: "[]")
      else:
        var flat = true
        for item in current.items:
          if item.kind == jArray or item.kind == jObject: flat = false
        if flat:
          for i, item in current.items:
            rows.add JsonRow(key: if i == 0: path else: "", accessibleKey: path, value: scalar(item))
        else:
          for i, item in current.items: children.add (item, true, path & "[" & $i & "]", pointer & "/" & $i)
    elif present and current.kind == jObject:
      let keys = if pointer in propertyOrder: propertyOrder[pointer] else: objectKeys(current)
      if keys.len == 0: rows.add JsonRow(key: path, accessibleKey: path, value: "{}")
      for key in keys:
        let (has, child) = current.get(key)
        children.add (child, has, if path != "": path & "." & key else: key,
                      pointer & "/" & key.replace("~", "~0").replace("/", "~1"))
    else: rows.add JsonRow(key: path, accessibleKey: path, value: scalar(current, present))
    for i in countdown(children.high, 0): stack.add children[i]
  rows

proc classList(names: varargs[string]): string =
  var kept: seq[string]
  for name in names:
    if name != "": kept.add name
  kept.join(" ")

proc markers(relationship: Relationship): array[2, string] =
  if relationship.kind == "generalization": return ["none", "extension"]
  if relationship.kind != "association": return MARKERS[SOLID_ARROW]
  if relationship.arrowType >= 0 and relationship.arrowType < MARKERS.len: MARKERS[relationship.arrowType]
  else: MARKERS[LINE_SOLID]

proc buildUsecaseGraph*(model: UsecaseModel): UsecaseGraph =
  ## Resolves a parsed use case diagram into what is drawn: every actor, use case, note, JSON
  ## table and boundary as a node with its class styles, and every relationship and note
  ## connector as an edge with its markers. Ports getData from Mermaid's use case DB.
  var nodes: seq[UsecaseGraphNode]
  var edges: seq[UsecaseGraphEdge]

  # A later class wins a property but keeps the place the property first took.
  proc compiled(classNames: seq[string]): seq[string] =
    var output = initOrderedTable[string, string]()
    for name in @["default"] & classNames:
      if name notin model.classDefs: continue
      for raw in model.classDefs[name].styles:
        let style = jsTrim(raw)
        let colon = style.find(':')
        let property = jsTrim(if colon == -1: style else: style[0 ..< colon])
        if property != "": output[property] = style
    for v in output.values: result.add v

  for actor in model.actors.values:
    var names = @["default", "usecase-actor", "usecase-actor-" & actor.kind,
                  if actor.business: "usecase-business" else: ""]
    names.add actor.classes
    nodes.add UsecaseGraphNode(
      id: actor.id, label: actor.label, markdown: actor.markdown, shape: ACTOR_SHAPES[actor.kind],
      padding: 10, cssClasses: classList(names), cssStyles: actor.styles,
      cssCompiledStyles: compiled(actor.classes), actorType: actor.kind, business: actor.business,
      icon: actor.icon, stereotype: actor.stereotype, parentId: actor.parentId)
  for useCase in model.useCases.values:
    let ellipse = useCase.shape == "ellipse"
    var names = @["default", "usecase-element", "usecase-" & useCase.shape,
                  if useCase.business: "usecase-business" else: ""]
    names.add useCase.classes
    nodes.add UsecaseGraphNode(
      id: useCase.id, label: useCase.label, markdown: useCase.markdown,
      shape: if not ellipse: "rect" elif useCase.business: "usecaseBusiness" else: "usecaseEllipse",
      padding: if ellipse: 20 else: 10, cssClasses: classList(names), cssStyles: useCase.styles,
      cssCompiledStyles: compiled(useCase.classes), business: useCase.business, stereotype: useCase.stereotype,
      parentId: useCase.parentId)
  for note in model.notes.values:
    nodes.add UsecaseGraphNode(
      id: note.id, label: note.label, markdown: note.markdown, shape: "note", padding: 10,
      cssClasses: "default usecase-note", cssCompiledStyles: compiled(@[]), noteTarget: note.target)
  for json in model.jsonNodes.values:
    nodes.add UsecaseGraphNode(
      id: json.id, label: json.id, shape: "usecaseJsonTable", padding: 10,
      cssClasses: classList(@["default", "usecase-json-table"] & json.classes), cssStyles: json.styles,
      cssCompiledStyles: compiled(json.classes), isJson: true,
      jsonRows: flattenJsonRows(json.value, json.propertyOrder))
  for boundary in model.systemBoundaries.values:
    nodes.add UsecaseGraphNode(
      id: boundary.id, label: boundary.label, markdown: boundary.markdown, shape: "usecaseSystemBoundary",
      isGroup: true, padding: 20,
      cssClasses: classList(@["default", "system-boundary", "system-boundary-" & boundary.kind] & boundary.classes),
      cssStyles: boundary.styles, cssCompiledStyles: compiled(boundary.classes), boundaryType: boundary.kind)

  for relationship in model.relationships:
    let semantic = relationship.kind == "include" or relationship.kind == "extend"
    let ends = markers(relationship)
    let animated = relationship.animate or relationship.animation != ""
    var names = @["default", "relationship", "relationship-" & relationship.kind]
    names.add relationship.classes
    names.add(if animated: "edge-animation-" & (if relationship.animation != "": relationship.animation
                                                 else: "fast") else: "")
    let edge = UsecaseGraphEdge(
      id: relationship.id, start: relationship.source, stop: relationship.target,
      relationshipType: relationship.kind, pattern: if semantic: "dotted" else: "solid",
      arrowTypeStart: ends[0], arrowTypeEnd: ends[1], classes: classList(names), style: relationship.styles,
      cssCompiledStyles: compiled(relationship.classes), animate: relationship.animate,
      animation: relationship.animation, minlen: relationship.minlen, explicitId: relationship.explicitId)
    # Include and extend are labelled with their kind, whatever label the relationship carries.
    if semantic:
      edge.label = relationship.kind
    elif relationship.kind == "association":
      edge.label = relationship.label
      edge.labelMarkdown = relationship.labelMarkdown
    edges.add edge
  for note in model.notes.values:
    edges.add UsecaseGraphEdge(
      id: note.id & "-edge", start: note.id, stop: note.target, relationshipType: "note", pattern: "dotted",
      arrowTypeStart: "none", arrowTypeEnd: "none", classes: "default relationship relationship-note",
      cssCompiledStyles: compiled(@[]), minlen: 1, internal: true)
  UsecaseGraph(nodes: nodes, edges: edges)
