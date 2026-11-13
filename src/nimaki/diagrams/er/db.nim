## port-of: src/diagrams/er/db.ts
## port-status: draft
import std/[sets, strutils, tables]
import ../../js
import types

func labelType(kind: string): string =
  if kind == "markdown" or kind == "string" or kind == "text": kind else: "markdown"

type ErDb* = ref object of RootObj
  direction*: string
  entities*: OrderedTable[string, ErEntity]
  relationships*: seq[ErRelationship]
  classes*: OrderedTable[string, ErClassDef]
  subgraphs*: seq[ErSubgraph]
  title*: string        ## "" for undefined
  accTitle*: string
  accDescr*: string
  subgraphLookup: Table[string, ErSubgraph]
  claimed: HashSet[string]

proc newErDb*(): ErDb = ErDb(direction: "TB")

proc addEntity*(db: ErDb, name: string, alias = ""): ErEntity =
  result = db.entities.getOrDefault(name, nil)
  if result == nil:
    result = ErEntity(id: "entity-" & name & "-" & $db.entities.len, label: name, alias: alias,
                      cssClasses: "default")
    db.entities[name] = result
  elif result.alias == "" and alias != "":
    result.alias = alias

# The grammar builds the list back to front, so the last attribute written comes first.
proc addAttributes*(db: ErDb, name: string, attributes: seq[ParsedAttribute]) =
  let entity = db.addEntity(name)
  for i in countdown(attributes.high, 0):
    let a = attributes[i]
    entity.attributes.add ErAttribute(kind: a.kind, name: a.name, keys: a.keys, comment: a.comment)

proc addRelationship*(db: ErDb, entA, roleA, entB: string, relSpec: RelSpec) =
  let entityA = if db.subgraphLookup.hasKey(entA): entA else: db.addEntity(entA).id
  let entityB = if db.subgraphLookup.hasKey(entB): entB else: db.addEntity(entB).id
  db.relationships.add ErRelationship(entityA: entityA, roleA: roleA, entityB: entityB, relSpec: relSpec)

proc setDirection*(db: ErDb, dir: string) = db.direction = dir

proc addCssStyles*(db: ErDb, ids, styles: seq[string]) =
  for id in ids:
    let entity = db.entities.getOrDefault(id, nil)
    if entity != nil:
      for style in styles: entity.cssStyles.add style
    let subgraph = db.subgraphLookup.getOrDefault(id, nil)
    if subgraph != nil:
      for style in styles: subgraph.cssStyles.add style

proc addClass*(db: ErDb, ids, styles: seq[string]) =
  for id in ids:
    var def = db.classes.getOrDefault(id, nil)
    if def == nil:
      def = ErClassDef(id: id)
      db.classes[id] = def
    for style in styles:
      if "color" in style: def.textStyles.add style.replaceFirst("fill", "bgFill")
      def.styles.add style

proc setClass*(db: ErDb, ids, classNames: seq[string]) =
  for id in ids:
    let entity = db.entities.getOrDefault(id, nil)
    if entity != nil:
      for name in classNames: entity.cssClasses.add " " & name
    let subgraph = db.subgraphLookup.getOrDefault(id, nil)
    if subgraph != nil:
      for name in classNames: subgraph.classes.add name

proc addSubGraph*(db: ErDb, idText: string, list: seq[DocItem], titleText: string, titleType = ""): string =
  let id = idText.jsTrim
  var seen = initHashSet[string]()
  var nodes: seq[string]
  var dir = ""
  for item in list:
    if item.isDir:
      dir = item.text
      continue
    let trimmed = item.text.jsTrim
    if trimmed == "" or trimmed in seen: continue
    seen.incl trimmed
    # A node belongs to the first subgraph that lists it.
    if item.text notin db.claimed: nodes.add item.text
  for node in nodes: db.claimed.incl node
  let subgraph = ErSubgraph(id: id, nodes: nodes, title: titleText.jsTrim, dir: dir, labelType: labelType(titleType))
  db.subgraphs.add subgraph
  db.subgraphLookup[id] = subgraph
  id

proc setAccTitle*(db: ErDb, text: string) =
  db.accTitle = text.jsTrimStart  # text.replace(/^\s+/g, '')

proc setAccDescription*(db: ErDb, text: string) =
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
