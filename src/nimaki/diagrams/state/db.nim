## port-of: src/diagrams/state/db.ts
## port-status: conformant
import std/[options, strutils, tables]
import ../../js
import graph, types

# Mermaid's StateDB in its version 2 form, which is what Mermaid uses for both `stateDiagram`
# and `stateDiagram-v2`. The legacy version, which numbers `[*]` states, is not ported.
type StateDb* = ref object of RootObj
  rootDoc*: seq[Stmt]
  states*: OrderedTable[string, Stmt]
  relations*: seq[StateRelation]
  classes*: OrderedTable[string, StateClassDef]
  links*: Table[string, StateLink]
  graph*: StateGraph
  title*: string        ## "" for undefined
  accTitle*: string
  accDescr*: string
  dividerCount: int

proc newStateDb*(): StateDb = StateDb()

# The direction the root document is laid out in: its last `direction` statement.
proc direction*(db: StateDb): string =
  result = "TB"
  for item in db.rootDoc:
    if item.stmt == skDir: result = item.value

proc getDividerId*(db: StateDb): string =
  inc db.dividerCount
  "divider-id-" & $db.dividerCount

proc addDescription*(db: StateDb, id, descr: string) =
  if db.states.hasKey(id):
    db.states[id].descriptions.add(if descr.startsWith(":"): descr.replaceFirst(":", "").jsTrim else: descr)

proc setCssClass*(db: StateDb, itemIds, cssClassName: string)

proc addState*(db: StateDb, id: string, kind = "", doc: seq[Stmt] = @[], hasDoc = false,
               descr = dkNone, description = "", descriptionList: seq[string] = @[],
               hasNote = false, note = StateNote(), hasClasses = false, classes: seq[string] = @[]) =
  ## `kind` "" is undefined, and takes the default 'default'.
  let kind = if kind == "": "default" else: kind
  let trimmedId = id.jsTrim
  var state = db.states.getOrDefault(trimmedId, nil)
  if state == nil:
    state = Stmt(stmt: skState, id: trimmedId, kind: kind, hasDoc: hasDoc, doc: doc,
                 hasNote: hasNote, note: note, hasClasses: true)
    db.states[trimmedId] = state
  else:
    if not state.hasDoc:
      state.hasDoc = hasDoc
      state.doc = doc
    if state.kind == "": state.kind = kind
  case descr
  of dkText:
    if description != "": db.addDescription(trimmedId, description.jsTrim)
  of dkList:
    for text in descriptionList: db.addDescription(trimmedId, text.jsTrim)
  of dkNone: discard
  if hasNote:
    state.hasNote = true
    state.note = note
  if hasClasses:
    for name in classes: db.setCssClass(trimmedId, name.jsTrim)

proc addStmtState(db: StateDb, item: Stmt, withClasses: bool) =
  db.addState(item.id, item.kind, item.doc, item.hasDoc, item.descr, item.description, item.descriptionList,
              item.hasNote, item.note, withClasses and item.hasClasses, item.classes)

# The states a comma-separated list of ids names, created where they do not exist yet. As in
# Mermaid, an id is looked up as written and trimmed only when it has to be created.
proc named(db: StateDb, ids: string): seq[Stmt] =
  for id in ids.split(','):
    var state = db.states.getOrDefault(id, nil)
    if state == nil:
      db.addState(id)
      state = db.states.getOrDefault(id.jsTrim, nil)
    if state != nil: result.add state

proc setCssClass*(db: StateDb, itemIds, cssClassName: string) =
  for state in db.named(itemIds): state.classes.add cssClassName

proc getState*(db: StateDb, id: string): Stmt = db.states.getOrDefault(id, nil)

proc addLink*(db: StateDb, stateId, url, tooltip: string) =
  db.links[stateId] = StateLink(url: url, tooltip: tooltip)

proc addRelation*(db: StateDb, item1, item2: Stmt, title = "") =
  for item in [item1, item2]: db.addStmtState(item, true)
  db.relations.add StateRelation(id1: item1.id.jsTrim, id2: item2.id.jsTrim, relationTitle: title)

proc addStyleClass*(db: StateDb, id: string, styleAttributes = "") =
  var found = db.classes.getOrDefault(id, nil)
  if found == nil:
    found = StateClassDef(id: id)
    db.classes[id] = found
  if styleAttributes == "": return
  for attrib in styleAttributes.split(','):
    let fixed = attrib.replaceFirst(";", "").jsTrim
    if "color" in attrib: found.textStyles.add fixed.replaceFirst("fill", "bgFill").replaceFirst("color", "fill")
    found.styles.add fixed

# Only the root document's statements become states, relations and classes here; the
# statements inside composites are read when the graph is built.
proc extract*(db: StateDb, doc: seq[Stmt]) =
  db.states = initOrderedTable[string, Stmt]()
  db.relations = @[]
  db.classes = initOrderedTable[string, StateClassDef]()
  for item in doc:
    case item.stmt
    of skState:
      db.addStmtState(Stmt(stmt: skState, id: item.id.jsTrim, kind: item.kind, doc: item.doc, hasDoc: item.hasDoc,
                           descr: item.descr, description: item.description, descriptionList: item.descriptionList,
                           hasNote: item.hasNote, note: item.note), false)
    of skRelation:
      db.addRelation(item.state1, item.state2, item.relDescription.get(""))
    of skClassDef:
      db.addStyleClass(item.id.jsTrim, item.classesText)
    of skStyle:
      var styles: seq[string]
      for s in item.styleClass.split(','): styles.add s.replace(";", "").jsTrim
      for state in db.named(item.id.jsTrim): state.styles = styles
    of skApplyClass:
      db.setCssClass(item.id.jsTrim, item.styleClass)
    of skClick:
      db.addLink(item.clickId.id, item.url, item.tooltip)
    else: discard
  db.graph = buildStateGraph(doc, db.states, db.classes)

# Mermaid's docTranslator: gives each `[*]` an id scoped to its parent, and turns a document
# split by `--` into one region per part.
proc translate*(db: StateDb) =
  let root = Stmt(stmt: skRoot, id: "root", doc: db.rootDoc, hasDoc: true)
  var pending: seq[(string, Stmt, bool)] = @[("root", root, true)]
  while pending.len > 0:
    let (parentId, node, first) = pending.pop()
    if node.stmt == skText: continue
    if node.stmt == skRelation:
      pending.add (parentId, node.state2, false)
      pending.add (parentId, node.state1, true)
      continue
    if node.stmt == skState:
      if node.id == "[*]":
        node.id = parentId & (if first: "_start" else: "_end")
        node.start = some(first)
      else:
        node.id = node.id.jsTrim
    elif node.stmt != skRoot:
      continue
    if not node.hasDoc: continue

    var regions: seq[Stmt]
    var current: seq[Stmt]
    for item in node.doc:
      if item.stmt == skState and item.kind == "divider" and not item.hasDoc:
        let region = copyStmt(item)
        region.doc = current
        region.hasDoc = true
        regions.add region
        current = @[]
      else:
        current.add item
    # Mermaid names the region after the last divider with a random id; here it continues the
    # divider numbering. Mermaid also leaves a document that ends with a divider ungrouped and
    # then fails to draw it; here the regions before that divider are kept.
    if regions.len > 0:
      if current.len > 0:
        regions.add Stmt(stmt: skState, id: db.getDividerId(), kind: "divider", doc: current, hasDoc: true)
      node.doc = regions
    for i in countdown(node.doc.high, 0): pending.add (node.id, node.doc[i], true)

proc setRootDoc*(db: StateDb, doc: seq[Stmt]) =
  db.rootDoc = doc
  db.translate()
  db.extract(doc)

proc getDirection*(db: StateDb): string =
  for item in db.rootDoc:
    if item.stmt == skDir: return item.value
  "TB"

# The grammar calls this while it is still building the document, so the statement lands in the
# previous root document and the direction is read from the parsed `dir` statements instead.
proc setDirection*(db: StateDb, dir: string) =
  for item in db.rootDoc:
    if item.stmt == skDir:
      item.value = dir
      return
  db.rootDoc.insert(Stmt(stmt: skDir, value: dir), 0)

proc trimColon*(db: StateDb, text: string): string =
  if text.startsWith(":"): text.substr(1).jsTrim else: text.jsTrim

proc setAccTitle*(db: StateDb, text: string) =
  db.accTitle = text.jsTrimStart  # text.replace(/^\s+/g, '')

proc setAccDescription*(db: StateDb, text: string) =
  # text.replace(/\n\s+/g, '\n')
  var s = ""
  var i = 0
  while i < text.len:
    if text[i] == '\n' and isJsSpaceAt(text, i + 1):
      s.add '\n'
      inc i
      while i < text.len and isJsSpaceAt(text, i): i += spaceLenAt(text, i)
    else:
      s.add text[i]
      inc i
  db.accDescr = s
