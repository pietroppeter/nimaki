## port-of: src/diagrams/kanban/db.ts
## port-status: conformant
import std/strutils
from std/unicode import nil
import ../../errors
import ../../util/yaml
import ../common/outline

type
  KanbanNode* = ref object
    ## A card, or (with `items`) a section: Pele's KanbanNode and KanbanSection.
    id*: string
    level*: int
    label*: string
    icon*, assigned*, ticket*, priority*, cssClasses*: string   ## "" for undefined
    items*: seq[KanbanNode]

  KanbanSection* = KanbanNode

  KanbanDb* = ref object of RootObj
    ## Pele's KanbanDb, which is also the KanbanModel.
    title*: string          ## "" for undefined
    sections*: seq[KanbanSection]
    last: KanbanNode
    sectionLevel: int
    misplaced: KanbanNode

  KanbanModel* = KanbanDb

proc addNode*(db: KanbanDb, level: int, id, descr: string, kind: int, hasShapeData: bool, shapeData: string) =
  let node = KanbanNode(id: id, level: level, label: descr)

  if hasShapeData:
    let yaml = if '\n' in shapeData: shapeData & "\n" else: "{\n" & shapeData & "\n}"
    var doc: YamlValue
    try:
      doc = parseYaml(yaml)
    except CatchableError as error:
      raise newPeleError("Metadata of \"" & node.id & "\" is not valid YAML. " & error.msg, "syntax",
                         ErrorInfo(diagramType: "kanban"))
    # Mermaid throws a TypeError on metadata that is empty or not a mapping. Here it is ignored.
    if doc.isRecord:
      let shape = if truthy(doc["shape"]): jsStr(doc["shape"]) else: ""
      if shape != unicode.toLower(shape) or '_' in shape:
        raise newPeleError("No such shape: " & shape & ". Shape names should be lowercase.", "semantic",
                           ErrorInfo(diagramType: "kanban"))
      if truthy(doc["label"]): node.label = jsStr(doc["label"])
      if truthy(doc["icon"]): node.icon = jsStr(doc["icon"])
      if truthy(doc["assigned"]): node.assigned = jsStr(doc["assigned"])
      if truthy(doc["ticket"]): node.ticket = jsStr(doc["ticket"])
      if truthy(doc["priority"]): node.priority = jsStr(doc["priority"])

  # A node indented less than the first column becomes a card, and Mermaid rejects whatever follows it.
  if db.misplaced != nil:
    raise newPeleError("Items without section detected, found section (\"" & db.misplaced.label & "\")",
                       "semantic", ErrorInfo(diagramType: "kanban"))
  if db.sections.len == 0: db.sectionLevel = level
  db.last = node
  if level == db.sectionLevel:
    db.sections.add node
  else:
    db.sections[^1].items.add node
    if level < db.sectionLevel: db.misplaced = node

proc decorateNode*(db: KanbanDb, decoration: Decoration) =
  ## Mermaid throws a TypeError when a decoration comes before any node. Here it is ignored.
  let node = db.last
  if node == nil: return
  if decoration.icon != "": node.icon = decoration.icon
  if decoration.class != "": node.cssClasses = decoration.class
