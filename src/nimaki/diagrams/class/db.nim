## port-of: src/diagrams/class/db.ts
## port-status: draft
import std/[strutils, tables]
import ../../js
import ../../text/entities
import ../../util/url
import members, types
import ../../jsregex
export types

const
  LINE* = 0
  DOTTED_LINE* = 1
  AGGREGATION* = 0
  EXTENSION* = 1
  COMPOSITION* = 2
  DEPENDENCY* = 3
  LOLLIPOP* = 4

const DOM_ID_PREFIX = "classId-"
  ## Mermaid looks up ids that start with a digit under this prefix, so they never match a class.

type ClassDb* = ref object of RootObj
  direction*: string
  classes*: OrderedTable[string, ClassNode]
  relations*: seq[ClassRelation]
  notes*: OrderedTable[string, ClassNote]
  namespaces*: OrderedTable[string, NamespaceNode]
  interfaces*: seq[ClassInterface]
  styleClasses*: OrderedTable[string, StyleClass]
  title*: string      ## "" for undefined
  accTitle*: string   ## "" for undefined
  accDescr*: string   ## "" for undefined
  namespaceStack: seq[string]
  withCssClass: OrderedTable[string, seq[ClassNode]]
    ## Pele's Map<string, Set<ClassNode>>: each seq holds a class once, in the order added.

proc newClassDb*(): ClassDb = ClassDb(direction: "TB")

func splitName(id: string): tuple[className, kind: string] =
  let at = id.find('~')
  if at <= 0: return (id, "")
  let stop = id.find('~', at + 1)
  (id[0 ..< at], id[at + 1 ..< (if stop == -1: id.len else: stop)])

func lookupId(id: string): string =
  let c = if id.len > 0: ord(id[0]) else: -1
  splitName(if c >= 48 and c <= 57: DOM_ID_PREFIX & id else: id).className

proc tag(db: ClassDb, node: ClassNode, cssClass: string) =
  if cssClass in db.withCssClass:
    if node notin db.withCssClass[cssClass]: db.withCssClass[cssClass].add node
  else: db.withCssClass[cssClass] = @[node]

proc addClass*(db: ClassDb, id: string) =
  let (className, kind) = splitName(id)
  if className in db.classes: return
  let node = ClassNode(id: className, kind: kind, label: className, cssClasses: "default")
  db.classes[className] = node
  db.tag(node, "default")

proc ensure(db: ClassDb, id: string): ClassNode =
  ## Returns the class for a name that may carry a generic type, creating it if needed.
  ## Mermaid throws a TypeError where this creates, as for an annotation on a class not yet declared.
  db.addClass(id)
  db.classes[splitName(id).className]

proc setClassLabel*(db: ClassDb, id, label: string) = db.ensure(id).label = label

proc addInterface(db: ClassDb, label, classId: string): string =
  result = "interface" & $db.interfaces.len
  db.interfaces.add ClassInterface(id: result, label: label, classId: classId)

proc addRelation*(db: ClassDb, relation: ClassRelation) =
  let type1 = relation.relation.type1
  let type2 = relation.relation.type2
  if type1 == LOLLIPOP and type2 == NONE:
    db.addClass(relation.id2)
    relation.id1 = db.addInterface(relation.id1, relation.id2)
  elif type2 == LOLLIPOP and type1 == NONE:
    db.addClass(relation.id1)
    relation.id2 = db.addInterface(relation.id2, relation.id1)
  else:
    db.addClass(relation.id1)
    db.addClass(relation.id2)
  relation.id1 = splitName(relation.id1).className
  relation.id2 = splitName(relation.id2).className
  relation.relationTitle1 = jsTrim(relation.relationTitle1)
  relation.relationTitle2 = jsTrim(relation.relationTitle2)
  db.relations.add relation

proc addAnnotation*(db: ClassDb, className, annotation: string) =
  db.ensure(className).annotations.add annotation

proc addMember*(db: ClassDb, className, member: string) =
  let node = db.ensure(className)
  let text = jsTrim(member)
  if text.startsWith("<<") and text.endsWith(">>"):
    node.annotations.add text[2 ..< text.len - 2]
  elif text.find(')') > 0:
    let parsed = newClassMember(text, "method")
    if parsed.memberType == "method": node.methods.add parsed else: node.members.add parsed
  elif text != "":
    node.members.add newClassMember(text, "attribute")

proc addMembers*(db: ClassDb, className: string, members: seq[string]) =
  for k in countdown(members.len - 1, 0): db.addMember(className, members[k])

proc addNote*(db: ClassDb, text: string, className = ""): string =
  let index = db.notes.len
  result = "note" & $index
  db.notes[result] = ClassNote(id: result, class: className, text: text, index: index)

func cleanupLabel*(label: string): string =
  jsTrim(if label.startsWith(':'): label.substr(1) else: label)

proc setCssClass*(db: ClassDb, ids, className: string) =
  for id in ids.split(','):
    let key = lookupId(id)
    if key notin db.classes: continue
    let node = db.classes[key]
    node.cssClasses.add " " & className
    for word in className.split(' '): db.tag(node, word)

proc defineClass*(db: ClassDb, ids: seq[string], style: seq[string]) =
  for id in ids:
    var styleClass = db.styleClasses.getOrDefault(id, nil)
    if styleClass == nil:
      styleClass = StyleClass(id: id)
      db.styleClasses[id] = styleClass
    for s in style:
      if "color" in s: styleClass.textStyles.add s.replaceFirst("fill", "bgFill")
      styleClass.styles.add s
    # Mermaid tests `cssClasses.includes(id)`, which also matches part of a longer name
    # (a classDef named `def` styles every class, through `default`). Whole names are compared here.
    if id notin db.withCssClass: continue
    var parts: seq[string]
    for s in style: parts.add s.split(',')
    for node in db.withCssClass[id]:
      for part in parts: node.styles.add part

proc setTooltip*(db: ClassDb, ids, tooltip: string) =
  ## `tooltip` "" for undefined (a tooltip is never empty).
  if tooltip == "": return
  for id in ids.split(','):
    let key = splitName(id).className
    if key in db.classes: db.classes[key].tooltip = tooltip

proc setLink*(db: ClassDb, ids, link: string, target = "", hasTarget = false) =
  # Entity codes are resolved first, so that what is checked is what a browser would follow.
  let url = jsTrim(decodeEntities(link))
  for id in ids.split(','):
    let key = lookupId(id)
    if key in db.classes:
      let node = db.classes[key]
      node.link = if url != "": sanitizeUrl(url) else: ""
      node.linkTarget = if hasTarget: target else: "_blank"
  db.setCssClass(ids, "clickable")

proc setClickEvent*(db: ClassDb, ids: string) =
  ## Callbacks are never executed; the class is only marked clickable, as in Mermaid's strict mode.
  for id in ids.split(','):
    let key = splitName(id).className
    if key in db.classes: db.classes[key].haveCallback = true
  db.setCssClass(ids, "clickable")

proc setDirection*(db: ClassDb, dir: string) = db.direction = dir

proc setAccTitle*(db: ClassDb, text: string) = db.accTitle = text.replace(jsre"/^\s+/g", "")

proc setAccDescription*(db: ClassDb, text: string) =
  db.accDescr = text.replace(jsre"/\n\s+/g", "\n")

proc addNamespace*(db: ClassDb, id: string, label = ""): string =
  ## `label` "" for undefined.
  let prefix = if db.namespaceStack.len > 0: db.namespaceStack[^1] else: ""
  let qualified = if prefix != "": prefix & "." & id else: id
  db.namespaceStack.add qualified

  let existing = db.namespaces.getOrDefault(qualified, nil)
  if existing != nil:
    existing.explicit = true
    if label != "": existing.label = label
    return qualified

  # The enclosing namespace and its ancestors exist already, so only the parts of `id` are walked.
  var parentId = prefix
  var start = if prefix != "": prefix.len + 1 else: 0
  while true:
    let dot = qualified.find('.', start)
    let leaf = dot == -1
    let current = if leaf: qualified else: qualified[0 ..< dot]
    var node = db.namespaces.getOrDefault(current, nil)
    if node == nil:
      let part = qualified[start ..< (if leaf: qualified.len else: dot)]
      node = NamespaceNode(id: current, label: (if leaf and label != "": label else: part),
                           parent: parentId, explicit: leaf)
      db.namespaces[current] = node
    elif leaf:
      node.explicit = true
    let parent = if parentId != "": db.namespaces.getOrDefault(parentId, nil) else: nil
    if parent != nil:
      if current notin parent.children: parent.children[current] = node
      if node.parent == "": node.parent = parentId
    if leaf: return qualified
    parentId = current
    start = dot + 1

proc popNamespace*(db: ClassDb) =
  if db.namespaceStack.len > 0: discard db.namespaceStack.pop()

proc addClassesToNamespace*(db: ClassDb, id: string, classNames, noteNames: seq[string]) =
  let namespace = db.namespaces.getOrDefault(id, nil)
  if namespace == nil: return
  for name in classNames:
    let className = splitName(name).className
    let node = db.classes.getOrDefault(className, nil)
    if node == nil: continue
    node.parent = id
    namespace.classes[className] = node
  for name in noteNames:
    let note = db.notes.getOrDefault(name, nil)
    if note == nil: continue
    note.parent = id
    namespace.notes[name] = note

proc setCssStyle*(db: ClassDb, id: string, styles: seq[string]) =
  let node = db.classes.getOrDefault(id, nil)
  if node == nil: return
  for s in styles:
    for part in s.split(','): node.styles.add part
