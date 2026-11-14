## port-of: src/diagrams/state/graph.ts
## port-status: conformant
import std/[options, strutils, tables]
import ../../errors
import ../../js
import types

type
  StateNode* = ref object
    id*: string
    shape*: string
      ## rect, rectWithTitle, stateStart, stateEnd, choice, fork, join, divider, roundedWithTitle,
      ## note or noteGroup ("" for undefined).
    label*: string               ## "" for undefined
    description*: seq[string]
    cssClasses*: string
    cssCompiledStyles*: seq[string]
    cssStyles*: seq[string]
    kind*: string                ## Pele's `type` ("" for undefined)
    isGroup*: bool
    parentId*: Option[string]
    dir*: string
      ## The direction inside a composite: its last `direction` statement, or TB ("" for undefined).
    position*: Option[string]
    noteFor*: Option[string]
    hasColorIndex*: bool         ## whether the object has a `colorIndex` key (for Object.assign)
    colorIndex*: Option[int]

  # Labels are markdown throughout, as in Mermaid.
  StateEdge* = object
    id*: string
    start*: string
    stop*: string                ## Pele's `end`
    label*: string
    classes*: string
    dashed*: bool                ## `pattern: 'dashed'`

  StateGraph* = object
    nodes*: seq[StateNode]
    edges*: seq[StateEdge]

  Draft = ref object
    shape: string
    isList: bool                 ## `description` is a string[]
    text: string
    list: seq[string]
    cssClasses: string
    cssStyles: seq[string]
    kind: string
    dir: string
    colorIndex: Option[int]

  Frame = object
    item: Stmt                   ## nil for undefined
    doc: seq[Stmt]
    at: int
    alt: bool

proc direction(doc: seq[Stmt]): string =
  result = "TB"
  for item in doc:
    if item.stmt == skDir: result = item.value

func hasDescription(item: Stmt): bool =
  ## `if (item.description)`: a non-empty string, or any array.
  item.descr == dkList or (item.descr == dkText and item.description != "")

func descriptionItems(item: Stmt): seq[string] =
  ## `[item.description].flat()`
  if item.descr == dkList: item.descriptionList else: @[item.description]

# Mermaid's dataFetcher: walks the documents and resolves them into the nodes and edges that are drawn.
proc buildStateGraph*(rootDoc: seq[Stmt], states: OrderedTable[string, Stmt],
                      classes: OrderedTable[string, StateClassDef]): StateGraph =
  var nodes: seq[StateNode]
  var edges: seq[StateEdge]
  var byId = initTable[string, StateNode]()
  var drafts = initTable[string, Draft]()
  var slots = initTable[string, Option[int]]()
  var counter = 0
  var nextSlot = 0

  # The description of a state is the list of its draft but its first line, and a state named
  # again is drawn from its draft again. Pele slices the list at each visit; nim js would copy
  # every string of it each time, so the slice waits for the end: `described` holds the draft
  # whose list the node last took.
  var described = initTable[string, Draft]()
  proc insert(node: StateNode, draft: Draft = nil) =
    # The two literal ids are what DOMPurify leaves of `<<fork>>` and `<<choice>>` in Mermaid; kept for parity.
    if node.id == "" or node.id == "</join></fork>" or node.id == "</choice>": return
    if node.cssClasses != "":
      # One copy, however many classes: a state named in a class statement many times has a long list.
      var compiled: seq[string]
      var any = false
      for name in node.cssClasses.split(' '):
        let def = classes.getOrDefault(name, nil)
        if def == nil: continue
        if not any:
          compiled = node.cssCompiledStyles
          any = true
        for style in def.styles: compiled.add style
      if any: node.cssCompiledStyles = compiled
    if draft != nil: described[node.id] = draft
    else: described.del node.id
    let existing = byId.getOrDefault(node.id, nil)
    if existing != nil:
      let parentId = if node.parentId.isSome: node.parentId else: existing.parentId
      # Object.assign(existing, node): the keys the node has.
      existing.shape = node.shape
      # The node is dropped after this, so its fields move: nim js would copy each string.
      existing.label = move node.label
      existing.description = move node.description
      existing.cssClasses = move node.cssClasses
      existing.cssCompiledStyles = move node.cssCompiledStyles
      existing.cssStyles = move node.cssStyles
      existing.kind = node.kind
      existing.isGroup = node.isGroup
      existing.dir = node.dir
      if node.parentId.isSome: existing.parentId = node.parentId
      if node.position.isSome: existing.position = node.position
      if node.noteFor.isSome: existing.noteFor = node.noteFor
      if node.hasColorIndex:
        existing.hasColorIndex = true
        existing.colorIndex = node.colorIndex
      if parentId.isSome: existing.parentId = parentId
    else:
      byId[node.id] = node
      nodes.add node

  proc visit(parent: Stmt, item: Stmt, alt: bool) =
    let id = item.id
    if id == "root": return
    let known = states.getOrDefault(id, nil)
    let classStr = if known != nil: known.classes.join(" ") else: ""
    let styles = if known != nil: known.styles else: @[]

    var draft = drafts.getOrDefault(id, nil)
    if draft == nil:
      var shape = "rect"
      if item.start == some(true): shape = "stateStart"
      elif item.start == some(false): shape = "stateEnd"
      if item.kind != "default": shape = item.kind
      draft = Draft(shape: shape, text: id, cssClasses: classStr & " statediagram-state", cssStyles: styles)
      drafts[id] = draft

    if item.hasDescription:
      if draft.isList:
        draft.shape = "rectWithTitle"
        draft.list.add item.descriptionItems
      elif draft.text.len > 0:
        draft.shape = "rectWithTitle"
        draft.list = if draft.text == id: item.descriptionItems else: @[draft.text] & item.descriptionItems
        draft.isList = true
      else:
        draft.shape = "rect"
        if item.descr == dkList:
          draft.isList = true
          draft.list = item.descriptionList
        else:
          draft.text = item.description
    let length = if draft.isList: draft.list.len else: utf16Len(draft.text)
    if length == 1 and draft.shape == "rectWithTitle":
      draft.shape = if draft.kind == "group": "roundedWithTitle" else: "rect"

    if draft.kind == "" and item.hasDoc:
      draft.kind = "group"
      draft.dir = direction(item.doc)
      draft.shape = if item.kind == "divider": "divider" else: "roundedWithTitle"
      # A container takes the next palette slot unless it is a region, which shares its composite's.
      if draft.shape == "divider" and parent != nil and slots.hasKey(parent.id):
        draft.colorIndex = slots[parent.id]
      else:
        let slot = nextSlot
        inc nextSlot
        draft.colorIndex = if classStr.jsTrim != "" or styles.len > 0: none(int) else: some(slot)
      slots[id] = draft.colorIndex
      draft.cssClasses = draft.cssClasses & " statediagram-cluster " & (if alt: "statediagram-cluster-alt" else: "")

    let node = StateNode(
      id: id,
      shape: draft.shape,
      label: if draft.isList: (if draft.list.len > 0: draft.list[0] else: "") else: draft.text,
      cssClasses: draft.cssClasses,
      cssStyles: draft.cssStyles,
      kind: draft.kind,
      isGroup: draft.kind == "group",
      dir: draft.dir,
      hasColorIndex: true,
      colorIndex: draft.colorIndex,
    )
    if node.shape == "divider": node.label = ""
    if parent != nil and parent.id != "root": node.parentId = some(parent.id)

    if not item.hasNote:
      insert(node, draft)
      return
    let note = item.note
    # Mermaid puts each note in a group of its own, named after the state. Pele keeps that
    # group in the model and lays the note out beside its state instead.
    proc aside(asideId, shape, cssClasses: string, isGroup: bool): StateNode =
      StateNode(id: asideId, shape: shape, label: note.text, cssClasses: cssClasses,
                kind: if isGroup: "group" else: "node", isGroup: isGroup, position: some(note.position))
    let noteNode = aside(id & "----note-" & $counter, "note", "statediagram-note", false)
    inc counter
    noteNode.parentId = some(id & "----parent")
    noteNode.noteFor = some(id)
    insert(aside(noteNode.parentId.get, "noteGroup", draft.cssClasses, true))
    insert(noteNode)
    insert(node, draft)
    let left = note.position == "left of"
    let start = if left: noteNode.id else: id
    let to = if left: id else: noteNode.id
    edges.add StateEdge(id: start & "-" & to, start: start, stop: to, label: "", classes: "transition note-edge",
                        dashed: true)

  var stack = @[Frame(item: nil, doc: rootDoc, at: 0, alt: true)]
  while stack.len > 0:
    if stack[^1].at >= stack[^1].doc.len:
      discard stack.pop()
      continue
    let item = stack[^1].doc[stack[^1].at]
    inc stack[^1].at
    let frameItem = stack[^1].item
    let frameAlt = stack[^1].alt
    if item.stmt == skState:
      visit(frameItem, item, frameAlt)
      if item.hasDoc: stack.add Frame(item: item, doc: item.doc, at: 0, alt: not frameAlt)
    elif item.stmt == skRelation:
      visit(frameItem, item.state1, frameAlt)
      visit(frameItem, item.state2, frameAlt)
      edges.add StateEdge(id: "edge" & $counter, start: item.state1.id, stop: item.state2.id,
                          label: item.relDescription.get(""), classes: "transition")
      inc counter

  for id, draft in described:
    if draft.isList and draft.list.len > 1: byId[id].description = draft.list[1 .. ^1]
  for node in nodes:
    if node.isGroup and node.description.len > 0:
      raise newPeleError("Group nodes can only have label. Remove the additional description for node [" &
                         node.id & "]", "semantic", "state")
  StateGraph(nodes: nodes, edges: edges)
