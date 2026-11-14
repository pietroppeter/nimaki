## port-of: src/diagrams/usecase/db.ts
## port-status: conformant
import std/[algorithm, sets, tables]
import ../../errors
import ../../js
import json, lexer, types

type
  DraftLabel* = object
    text*: string
    markdown*: bool
    span*: Span

  DraftProperty* = object
    ## keySpan is also where an error about the property points.
    key*: string
    isBool*: bool
    b*: bool
    s*: string
    span*, keySpan*, valueSpan*: Span

  DraftBoundary* = ref object
    id*: string
    label*: DraftLabel
    span*: Span
    generated*: bool
    classes*: seq[string]

  DraftElement* = object
    id*: string
    label*: DraftLabel
    span*: Span
    generated*: bool
    kind*: string            ## actor or usecase
    parent*: DraftBoundary   ## nil for undefined
    shape*: string           ## "" for undefined
    metadata*: seq[DraftProperty]
    stereotype*: string      ## "" for undefined
    classes*: seq[string]

  DraftJson* = ref object
    id*: string
    value*: JsonValue
    propertyOrder*: Table[string, seq[string]]
    span*: Span
    classes*: seq[string]

  DraftEndpoint* = object
    id*: string
    label*: DraftLabel
    span*: Span
    generated*: bool
    # Whether this mention declares the element, and whether it carries a `:::` suffix.
    declares*, classed*: bool

  DraftRelationship* = object
    source*, target*: DraftEndpoint
    span*: Span
    id*: string              ## "" for undefined
    idSpan*: Span
    kind*: string            ## type
    arrowType*: int
    hasLabel*: bool
    label*: DraftLabel
    minlen*: int

  DraftNote* = object
    target*: string
    span*: Span
    label*: DraftLabel

  DraftMetadata* = object
    target*: string
    span*: Span
    properties*: seq[DraftProperty]

  DraftClass* = object
    targets*: seq[(string, Span)]
    classes*: seq[string]

  DraftStyle* = object
    target*: string
    span*: Span
    styles*: seq[string]

  DraftClassDef* = object
    ids*, styles*: seq[string]

  Drafts* = ref object
    ## Everything the parser read, in source order, before any of it is resolved.
    elements*: seq[DraftElement]
    boundaries*: seq[DraftBoundary]
    jsons*: seq[DraftJson]
    relationships*: seq[DraftRelationship]
    notes*: seq[DraftNote]
    metadata*: seq[DraftMetadata]
    classes*: seq[DraftClass]
    styles*: seq[DraftStyle]
    classDefs*: seq[DraftClassDef]
    direction*: string       ## "" for undefined
    accTitle*, accDescription*: string

proc emptyDrafts*(): Drafts = Drafts()

type
  Origin = object
    kind: string             ## actor, usecase, boundary, json or edge
    span: Span
    generated: bool
    label: string            ## the label a generated id was derived from

  ElementState = ref object
    id: string
    label: DraftLabel
    span: Span
    generated: bool
    kind: string
    parent: DraftBoundary
    shape: string
    stereotype: string
    hasStereotypeSpan: bool
    stereotypeSpan: Span
    classes: seq[string]
    actorType: string        ## "" for undefined
    hasIcon: bool
    icon: string
    business: int            ## -1 undefined, 0 false, 1 true

  BoundaryState = ref object
    draft: DraftBoundary
    classes: seq[string]
    kind: string             ## "" for undefined
    members: seq[string]

proc pushUnique(target: var seq[string], values: openArray[string]) =
  if values.len == 0: return
  var seen = toHashSet(target)
  for value in values:
    if value in seen: continue
    seen.incl value
    target.add value

proc inferKind(properties: seq[DraftProperty]): string =
  ## Which kind of element the keys of a metadata block could only belong to, for the error
  ## message ("" for undefined).
  var possible = @["actor", "usecase", "boundary", "edge"]
  proc only(kind: string) =
    possible = @[kind]
  for property in properties:
    let key = property.key
    if key == "icon": only("actor")
    elif key == "animate" or key == "animation": only("edge")
    elif key == "type":
      possible = @[]
      let s = if property.isBool: "" else: property.s
      if not property.isBool and (s == "rect" or s == "package"): possible.add "boundary"
      elif not property.isBool and (s == "normal" or s == "hollow" or s == "awesome"): possible.add "actor"
    elif key == "business":
      var kept: seq[string]
      for p in possible:
        if p != "boundary" and p != "edge": kept.add p
      possible = kept
    else: return ""
  if possible.len == 1: possible[0] else: ""

proc dropIndentation(s: string): string =
  ## s.replace(/\n\s+/g, '\n')
  var i = 0
  while i < s.len:
    if s[i] == '\n':
      var j = i + 1
      while isJsSpaceAt(s, j): j += spaceLenAt(s, j)
      result.add '\n'
      i = j
    else:
      result.add s[i]
      inc i

proc resolveUsecase*(src: string, drafts: Drafts, headerSpan: Span, title: string): UsecaseModel =
  ## Resolves what the parser read into a model, once the whole diagram is read: which ids are
  ## actors, use cases, boundaries, JSON nodes or edges, in what order they appear, and whether
  ## the statements about them agree. Ports Mermaid's UsecaseModelBuilder, with its messages.
  let model = emptyModel()
  var symbols = initTable[string, Origin]()
  var elements = initOrderedTable[string, ElementState]()
  var boundaries = initOrderedTable[string, BoundaryState]()
  var edges = initTable[string, Relationship]()
  # The offset at which each id is first mentioned, which decides the order of the model.
  var first = initTable[string, int]()

  proc at(span: Span): string = locationText(src, span[0], span[1])

  proc error(message: string, span: Span): ref PeleError =
    let (line, column) = lineColumn(src, span[0])
    newPeleError(message, "semantic", ErrorInfo(diagramType: "usecase", line: line, column: column))

  proc fail(message: string, span: Span) =
    raise error(message & " at " & at(span), span)

  proc suffix(hasLabel: bool, label: string): string =
    if hasLabel: " (label \"" & label & "\")" else: ""

  proc conflict(message: string, current, previous: Span, currentLabel = "", previousLabel = "") =
    raise error(message & " at " & at(current) & currentLabel & "; previous declaration at " & at(previous) &
                previousLabel, current)

  proc invalid(id, kind: string, property: DraftProperty) =
    fail("Metadata property '" & property.key & "' is invalid for " & kind & " '" & id & "'", property.keySpan)

  proc mention(id: string, offset: int) =
    if id notin first or offset < first[id]: first[id] = offset

  proc order(id: string): int = first.getOrDefault(id, 0)

  proc register(id: string, label: DraftLabel, span: Span, generated: bool, kind: string) =
    symbols[id] = Origin(kind: kind, span: span, generated: generated, label: label.text)

  # An id means one thing in the whole diagram, and an id made from a label may be declared once.
  proc claim(id: string, label: DraftLabel, span: Span, generated: bool, kind: string) =
    if id notin symbols: return
    let origin = symbols[id]
    let current = suffix(generated, label.text)
    let previous = suffix(origin.generated, origin.label)
    if origin.kind != kind:
      conflict("ID '" & id & "' is declared as both " & origin.kind & " and " & kind, span, origin.span, current,
               previous)
    if origin.generated or generated:
      conflict("Generated ID '" & id & "' collides with another declaration", span, origin.span, current, previous)

  proc unique(id, kind: string, span: Span) =
    if id in symbols:
      let previous = symbols[id]
      conflict("ID '" & id & "' is declared more than once (" & previous.kind & " and " & kind & ")", span,
               previous.span, "", suffix(previous.generated, previous.label))
    symbols[id] = Origin(kind: kind, span: span, generated: false)

  # A metadata statement replaces what a declaration said; two declarations have to agree.
  proc actorProperty(state: ElementState, property: DraftProperty, replace: bool) =
    let key = property.key
    proc clashes() =
      conflict("Actor '" & state.id & "' has conflicting " & key & " metadata", property.keySpan, state.span)
    if key == "type" and not property.isBool and property.s in ["normal", "hollow", "awesome"]:
      if not replace and state.actorType != "" and state.actorType != property.s: clashes()
      state.actorType = property.s
    elif key == "icon" and not property.isBool:
      if not replace and state.hasIcon and state.icon != property.s: clashes()
      state.hasIcon = true
      state.icon = property.s
    elif key == "business" and property.isBool:
      if not replace and state.business != -1 and (state.business == 1) != property.b: clashes()
      state.business = ord(property.b)
    else: invalid(state.id, "actor", property)

  proc elementMetadata(state: ElementState, properties: seq[DraftProperty], replace: bool) =
    for property in properties:
      if state.kind == "actor": actorProperty(state, property, replace)
      elif property.key == "business" and property.isBool:
        if not replace and state.business != -1 and (state.business == 1) != property.b:
          conflict("Use case '" & state.id & "' has conflicting business metadata", property.keySpan, state.span)
        state.business = ord(property.b)
      else: invalid(state.id, "usecase", property)

  proc publish(state: ElementState) =
    let parentId = if state.parent != nil: state.parent.id else: ""
    if state.kind == "actor":
      model.useCases.del state.id
      let actor = Actor(
        id: state.id,
        label: state.label.text,
        markdown: state.label.markdown,
        business: state.business == 1,
        classes: state.classes,
        kind: if state.hasIcon and state.icon != "": "icon"
              elif state.actorType != "": state.actorType
              else: "normal",
        styles: if state.id in model.actors: model.actors[state.id].styles else: @[],
        stereotype: state.stereotype,
        parentId: parentId,
      )
      if state.hasIcon and state.icon != "": actor.icon = state.icon
      model.actors[state.id] = actor
    else:
      model.actors.del state.id
      model.useCases[state.id] = UseCase(
        id: state.id,
        label: state.label.text,
        markdown: state.label.markdown,
        business: state.business == 1,
        classes: state.classes,
        shape: if state.shape != "": state.shape else: "ellipse",
        styles: if state.id in model.useCases: model.useCases[state.id].styles else: @[],
        stereotype: state.stereotype,
        parentId: parentId,
      )

  proc declareElement(draft: DraftElement) =
    claim(draft.id, draft.label, draft.span, draft.generated, draft.kind)
    let parent = if draft.parent != nil and draft.parent.id != "": draft.parent else: nil
    if draft.id notin elements:
      let state = ElementState(
        kind: draft.kind,
        id: draft.id,
        label: draft.label,
        span: draft.span,
        generated: draft.generated,
        classes: draft.classes,
        parent: parent,
        shape: draft.shape,
        stereotype: draft.stereotype,
        hasStereotypeSpan: draft.stereotype != "",
        stereotypeSpan: draft.span,
        business: -1,
      )
      elementMetadata(state, draft.metadata, false)
      elements[draft.id] = state
      register(draft.id, draft.label, draft.span, draft.generated, draft.kind)
      return
    let existing = elements[draft.id]
    if existing.label.text != draft.label.text or existing.label.markdown != draft.label.markdown:
      conflict("ID '" & draft.id & "' has conflicting labels", draft.span, existing.span)
    if draft.shape != "" and existing.shape != "" and draft.shape != existing.shape:
      conflict("Use case '" & draft.id & "' has conflicting shapes", draft.span, existing.span)
    # A boundary whose title makes an empty id is no parent, but it still takes the place of one.
    if parent != nil and existing.parent != nil and existing.parent.id != "" and parent.id != existing.parent.id:
      conflict("Element '" & draft.id & "' belongs to more than one system boundary", parent.span,
               existing.parent.span)
    if draft.stereotype != "" and existing.stereotype != "" and draft.stereotype != existing.stereotype:
      conflict("Element '" & draft.id & "' has conflicting stereotypes", draft.span,
               if existing.hasStereotypeSpan: existing.stereotypeSpan else: existing.span)
    if existing.shape == "": existing.shape = draft.shape
    if existing.parent == nil: existing.parent = draft.parent
    if existing.stereotype == "": existing.stereotype = draft.stereotype
    if not existing.hasStereotypeSpan and draft.stereotype != "":
      existing.hasStereotypeSpan = true
      existing.stereotypeSpan = draft.span
    pushUnique(existing.classes, draft.classes)
    elementMetadata(existing, draft.metadata, false)

  proc declareBoundary(draft: DraftBoundary) =
    claim(draft.id, draft.label, draft.span, draft.generated, "boundary")
    if draft.id in boundaries:
      let existing = boundaries[draft.id]
      if existing.draft.label.text != draft.label.text or existing.draft.label.markdown != draft.label.markdown:
        conflict("Boundary '" & draft.id & "' has conflicting titles", draft.span, existing.draft.span)
      pushUnique(existing.classes, draft.classes)
      return
    boundaries[draft.id] = BoundaryState(draft: draft, classes: draft.classes)
    register(draft.id, draft.label, draft.span, draft.generated, "boundary")

  # An end of a relationship that nothing declares becomes a use case.
  proc endpoint(stop: DraftEndpoint): string =
    if stop.classed and not stop.declares:
      fail("Relationship endpoint '" & stop.id & "' uses ::: without declaring the node", stop.span)
    if stop.id in symbols: return symbols[stop.id].kind
    elements[stop.id] = ElementState(id: stop.id, label: stop.label, span: stop.span, generated: stop.generated,
                                     kind: "usecase", shape: "ellipse", business: -1)
    register(stop.id, stop.label, stop.span, stop.generated, "usecase")
    mention(stop.id, stop.span[0])
    "usecase"

  proc stylable(id: string, span: Span): Stylable =
    let kind = if id in symbols: symbols[id].kind else: ""
    result =
      if kind == "actor": model.actors.getOrDefault(id)
      elif kind == "usecase": model.useCases.getOrDefault(id)
      elif kind == "boundary": model.systemBoundaries.getOrDefault(id)
      elif kind == "json": model.jsonNodes.getOrDefault(id)
      else: edges.getOrDefault(id)
    if result == nil: fail("Class/style target '" & id & "' is unresolved or anonymous", span)

  # What each declaration is: 0 an element, 1 a boundary, 2 a JSON node, 3 an edge id; and which.
  type Declaration = object
    offset, kind, index: int

  var declarations: seq[Declaration]
  for r in drafts.relationships:
    mention(r.source.id, r.source.span[0])
    mention(r.target.id, r.target.span[0])
  for i, draft in drafts.elements:
    mention(draft.id, draft.span[0])
    declarations.add Declaration(offset: draft.span[0], kind: 0, index: i)
  for i, draft in drafts.boundaries:
    mention(draft.id, draft.span[0])
    declarations.add Declaration(offset: draft.span[0], kind: 1, index: i)
  for i, draft in drafts.jsons:
    mention(draft.id, draft.span[0])
    declarations.add Declaration(offset: draft.span[0], kind: 2, index: i)
  for i, r in drafts.relationships:
    if r.id != "": declarations.add Declaration(offset: r.idSpan[0], kind: 3, index: i)
  declarations.sort(proc (a, b: Declaration): int = cmp(a.offset, b.offset))
  for declaration in declarations:
    let i = declaration.index
    case declaration.kind
    of 0: declareElement(drafts.elements[i])
    of 1: declareBoundary(drafts.boundaries[i])
    of 2: unique(drafts.jsons[i].id, "json", drafts.jsons[i].span)
    else: unique(drafts.relationships[i].id, "edge", drafts.relationships[i].idSpan)

  proc elementsInOrder(): seq[ElementState] =
    for state in elements.values: result.add state
    result.sort(proc (a, b: ElementState): int = cmp(order(a.id), order(b.id)))

  for state in elementsInOrder(): publish(state)
  var boundaryOrder: seq[BoundaryState]
  for state in boundaries.values: boundaryOrder.add state
  boundaryOrder.sort(proc (a, b: BoundaryState): int = cmp(order(a.draft.id), order(b.draft.id)))
  for state in boundaryOrder:
    model.systemBoundaries[state.draft.id] = SystemBoundary(id: state.draft.id, label: state.draft.label.text,
                                                            markdown: state.draft.label.markdown, kind: "rect")
  var jsons = drafts.jsons
  jsons.sort(proc (a, b: DraftJson): int = cmp(order(a.id), order(b.id)))
  for draft in jsons:
    model.jsonNodes[draft.id] = UsecaseJsonNode(id: draft.id, value: draft.value,
                                                propertyOrder: draft.propertyOrder, classes: draft.classes)

  var anonymous = 0
  for draft in drafts.relationships:
    let source = draft.source
    let target = draft.target
    let kind = draft.kind
    let sourceKind = endpoint(source)
    let targetKind = endpoint(target)
    proc related(k: string): bool = k == "actor" or k == "usecase" or k == "json"
    if not related(sourceKind):
      conflict("Relationship source '" & source.id & "' cannot be " & sourceKind, source.span,
               symbols[source.id].span)
    if not related(targetKind):
      conflict("Relationship target '" & target.id & "' cannot be " & targetKind, target.span,
               symbols[target.id].span)
    if (kind == "include" or kind == "extend") and (sourceKind != "usecase" or targetKind != "usecase"):
      fail(kind & " relationship requires use-case endpoints", draft.span)
    if kind == "generalization" and (sourceKind == "json" or sourceKind != targetKind):
      fail("Generalization requires actor-to-actor or use-case-to-use-case endpoints", draft.span)
    if kind == "association" and (sourceKind == "json" or targetKind == "json") and draft.arrowType > 2:
      fail("JSON relationship '" & source.id & "' to '" & target.id &
           "' permits only point, reversed-point, or markerless solid association", draft.span)
    var id = draft.id
    if id == "":
      id = "edge-" & $anonymous
      inc anonymous
    let relationship = Relationship(
      id: id,
      explicitId: draft.id != "",
      source: source.id,
      target: target.id,
      kind: kind,
      arrowType: draft.arrowType,
      minlen: draft.minlen,
    )
    if draft.hasLabel:
      relationship.label = draft.label.text
      relationship.labelMarkdown = draft.label.markdown
    model.relationships.add relationship
    edges[id] = relationship

  # The relationships may have added use cases; put all elements back in the order of first mention.
  let declaredActors = model.actors
  let declaredUseCases = model.useCases
  model.actors.clear()
  model.useCases.clear()
  for state in elementsInOrder():
    if state.id in declaredActors: model.actors[state.id] = declaredActors[state.id]
    elif state.id in declaredUseCases: model.useCases[state.id] = declaredUseCases[state.id]
    else: publish(state)

  for metadata in drafts.metadata:
    let target = metadata.target
    let properties = metadata.properties
    if target notin symbols:
      let inferred = inferKind(properties)
      fail("Metadata target '" & target & "' is unresolved" &
           (if inferred != "": " (metadata implies " & inferred & ")" else: ""), metadata.span)
    let kind = symbols[target].kind
    if kind == "actor" or kind == "usecase":
      elementMetadata(elements[target], properties, true)
      continue
    let boundary = boundaries.getOrDefault(target)
    let edge = edges.getOrDefault(target)
    for property in properties:
      let key = property.key
      if kind == "boundary" and boundary != nil and key == "type" and not property.isBool and
          (property.s == "rect" or property.s == "package"):
        boundary.kind = property.s
      elif kind == "edge" and edge != nil and key == "animate" and property.isBool: edge.animate = property.b
      elif kind == "edge" and edge != nil and key == "animation" and not property.isBool and
          (property.s == "fast" or property.s == "slow"):
        edge.animation = property.s
        edge.animate = true
      else: invalid(target, kind, property)
  for relationship in model.relationships:
    if relationship.animation != "": relationship.animate = true

  for state in elements.values:
    if state.kind == "actor":
      if state.hasIcon and state.icon != "" and state.actorType != "" and state.actorType != "normal":
        fail("Actor '" & state.id & "' cannot combine icon with type '" & state.actorType & "'", state.span)
      if state.business == 1 and ((state.hasIcon and state.icon != "") or state.actorType == "awesome"):
        fail("Business actor '" & state.id & "' must use normal or hollow geometry", state.span)
    elif state.shape == "rect" and state.business == 1:
      fail("Rectangular use case '" & state.id & "' cannot be a business use case", state.span)
    publish(state)

  var byOffset = drafts.elements
  byOffset.sort(proc (a, b: DraftElement): int = cmp(a.span[0], b.span[0]))
  for draft in byOffset:
    if draft.parent == nil or draft.parent.id == "": continue
    let state = boundaries[draft.parent.id]
    if draft.id notin state.members: state.members.add draft.id
  for state in boundaries.values:
    let boundary = model.systemBoundaries[state.draft.id]
    boundary.kind = if state.kind != "": state.kind else: "rect"
    boundary.members = state.members
    boundary.classes = state.classes

  var notes = 0
  for draft in drafts.notes:
    if draft.target notin symbols: fail("Note target '" & draft.target & "' is unresolved", draft.span)
    let origin = symbols[draft.target]
    if origin.kind != "actor" and origin.kind != "usecase":
      conflict("Note target '" & draft.target & "' must be an actor or use case, not " & origin.kind, draft.span,
               origin.span)
    let id = "note-" & $notes
    inc notes
    model.notes[id] = UsecaseNote(id: id, target: draft.target, label: draft.label.text,
                                  markdown: draft.label.markdown)

  for definition in drafts.classDefs:
    let styles = SharedStyles(items: definition.styles)
    for id in definition.ids: model.classDefs[id] = ClassDef(id: id, styles: styles)
  for assignment in drafts.classes:
    for (id, span) in assignment.targets:
      let target = stylable(id, span)
      pushUnique(target.classes, assignment.classes)
  for assignment in drafts.styles:
    let target = stylable(assignment.target, assignment.span)
    target.styles.add assignment.styles

  if drafts.direction != "": model.direction = drafts.direction
  model.title = title
  model.accTitle = drafts.accTitle
  model.accDescription = drafts.accDescription
  model.accDescr = dropIndentation(drafts.accDescription)
  model.source = src
  model.headerSpan = headerSpan
  model
