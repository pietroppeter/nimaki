## port-of: src/diagrams/c4/db.ts
## port-status: conformant
##
## Also holds the types of src/diagrams/c4/types.ts. An element's optional text fields (type,
## descr, techn, sprite, tags, link, the colours...) are kept in `fields`, where a missing key is
## undefined; every reader treats undefined and "" alike. Named arguments that set no known field
## (`extra` in Pele) are not kept, as nothing reads them.
import std/[options, tables, strutils]
import ../../jsregex

type
  C4Attr* = object
    ## A positional argument (`s`), or a `$key="value"` one.
    isNamed*: bool
    s*, key*, value*: string

  C4Element* = ref object
    ## A shape (`kind` set) or a boundary (`nodeType` set on deployment nodes). `uid` numbers
    ## elements in the order they were made, so tables can key them by identity in any backend.
    uid*: int
    alias*, label*: string
    aliasAttr*, labelAttr*: Option[C4Attr]
    parent*: C4Element
    fields*: Table[string, string]
    kind*: string
    nodeType*: string

  C4Rel* = ref object
    typ*, start*, to*, label*: string
    fromAttr*, toAttr*, labelAttr*: Option[C4Attr]
    fields*: Table[string, string]
    offsetX*, offsetY*: float   ## NaN for undefined

  C4Db* = ref object of RootObj
    c4Type*: string
    title*, accTitle*, accDescr*: string
    shapes*: seq[C4Element]
    boundaries*: seq[C4Element]
    rels*: seq[C4Rel]
    shapeInRow*, boundaryInRow*: float
    shapeIndex: Table[string, C4Element]
    boundaryIndex: Table[string, C4Element]
    relIndex: Table[string, Table[string, C4Rel]]
    current: C4Element
    stack: seq[C4Element]
    uids: int

const
  ELEMENT_FIELDS = ["label", "type", "descr", "techn", "sprite", "tags", "link", "bgColor",
    "fontColor", "borderColor", "shadowing", "shape", "legendText", "legendSprite"]
  REL_FIELDS = ["label", "descr", "techn", "sprite", "tags", "link", "textColor", "lineColor"]

func `[]`*(e: C4Element, field: string): string = e.fields.getOrDefault(field)
func `[]`*(r: C4Rel, field: string): string = r.fields.getOrDefault(field)

func jsParseInt*(s: string): float =
  ## parseInt(s) with no radix.
  var i = 0
  while i < s.len and s[i] in Whitespace: inc i
  var sign = 1.0
  if i < s.len and s[i] in {'+', '-'}:
    if s[i] == '-': sign = -1.0
    inc i
  var radix = 10
  if i + 1 < s.len and s[i] == '0' and s[i + 1] in {'x', 'X'}:
    radix = 16
    i += 2
  var value = 0.0
  var any = false
  while i < s.len:
    let d = case s[i]
      of '0'..'9': ord(s[i]) - ord('0')
      of 'a'..'z': ord(s[i]) - ord('a') + 10
      of 'A'..'Z': ord(s[i]) - ord('A') + 10
      else: 99
    if d >= radix: break
    value = value * float(radix) + float(d)
    any = true
    inc i
  if any: sign * value else: NaN

proc named(target: C4Element, attr: C4Attr) =
  ## Mermaid assigns a named argument to whatever property it names. Here it reaches only the
  ## fields above.
  if attr.key in ELEMENT_FIELDS:
    if attr.key == "label": target.label = attr.value
    else: target.fields[attr.key] = attr.value

proc named(target: C4Rel, attr: C4Attr) =
  if attr.key == "offsetX": target.offsetX = jsParseInt(attr.value)
  elif attr.key == "offsetY": target.offsetY = jsParseInt(attr.value)
  elif attr.key in REL_FIELDS:
    if attr.key == "label": target.label = attr.value
    else: target.fields[attr.key] = attr.value

proc put(target: C4Element | C4Rel, field: string, attr: Option[C4Attr]) =
  ## A positional argument fills the field of its slot; a named one, the field it names.
  if attr.isNone: return
  if not attr.get.isNamed: target.fields[field] = attr.get.s
  else: named(target, attr.get)

proc text(target: C4Element | C4Rel, field: string, attr: Option[C4Attr]) =
  if attr.isNone:
    if field notin target.fields: target.fields[field] = ""
  else: put(target, field, attr)

proc label(target: C4Element | C4Rel, attr: Option[C4Attr]) =
  target.labelAttr = none(C4Attr)
  if attr.isSome and attr.get.isNamed:
    target.label = ""
    target.labelAttr = attr
    named(target, attr.get)
  else:
    target.label = if attr.isSome: attr.get.s else: ""

func at(attrs: seq[C4Attr], i: int): Option[C4Attr] =
  if i < attrs.len: some(attrs[i]) else: none(C4Attr)

proc newC4Db*(): C4Db =
  let global = C4Element(alias: "global", label: "global", fields: {"type": "global"}.toTable)
  C4Db(boundaries: @[global], current: global, shapeInRow: 4, boundaryInRow: 2)

proc setC4Type*(db: C4Db, typ: string) = db.c4Type = typ
proc setTitle*(db: C4Db, title: string) = db.title = title

proc setAccDescription*(db: C4Db, descr: string) =
  db.accDescr = descr.replace(jsre"/\n\s+/g", "\n")

proc element(list: var seq[C4Element], index: var Table[string, C4Element], alias: C4Attr,
             title: Option[C4Attr], uids: var int): C4Element =
  var el = if not alias.isNamed: index.getOrDefault(alias.s) else: nil
  if el == nil:
    inc uids
    el = C4Element(uid: uids)
    list.add el
    if not alias.isNamed:
      el.alias = alias.s
      index[alias.s] = el
    else:
      el.aliasAttr = some(alias)
      named(el, alias)
  label(el, title)
  el

proc finishShape(db: C4Db, shape: C4Element, kind: string, attrs: seq[C4Attr], at: int) =
  put(shape, "sprite", attrs.at(at))
  put(shape, "tags", attrs.at(at + 1))
  put(shape, "link", attrs.at(at + 2))
  shape.kind = kind
  shape.parent = db.current

proc addPersonOrSystem*(db: C4Db, kind: string, attrs: seq[C4Attr]) =
  ## alias, label, ?descr, ?sprite, ?tags, $link
  let shape = element(db.shapes, db.shapeIndex, attrs[0], attrs.at(1), db.uids)
  text(shape, "descr", attrs.at(2))
  db.finishShape(shape, kind, attrs, 3)

proc addContainer*(db: C4Db, kind: string, attrs: seq[C4Attr]) =
  ## alias, label, ?techn, ?descr, ?sprite, ?tags, $link
  let shape = element(db.shapes, db.shapeIndex, attrs[0], attrs.at(1), db.uids)
  text(shape, "techn", attrs.at(2))
  text(shape, "descr", attrs.at(3))
  db.finishShape(shape, kind, attrs, 4)

proc addComponent*(db: C4Db, kind: string, attrs: seq[C4Attr]) = db.addContainer(kind, attrs)

proc boundary(db: C4Db, attrs: seq[C4Attr], fallback: string): C4Element =
  let boundary = element(db.boundaries, db.boundaryIndex, attrs[0], attrs.at(1), db.uids)
  if attrs.len <= 2: boundary.fields["type"] = fallback
  else: put(boundary, "type", attrs.at(2))
  boundary

proc open(db: C4Db, boundary: C4Element) =
  boundary.parent = db.current
  db.stack.add db.current
  db.current = boundary

proc addPersonOrSystemBoundary*(db: C4Db, attrs: seq[C4Attr], fallback = "system") =
  ## alias, label, ?type, ?tags, $link
  let boundary = db.boundary(attrs, fallback)
  put(boundary, "tags", attrs.at(3))
  put(boundary, "link", attrs.at(4))
  db.open(boundary)

proc addContainerBoundary*(db: C4Db, attrs: seq[C4Attr]) =
  db.addPersonOrSystemBoundary(attrs, "container")

proc addDeploymentNode*(db: C4Db, nodeType: string, attrs: seq[C4Attr]) =
  ## alias, label, ?type, ?descr, ?sprite, ?tags, $link
  let boundary = db.boundary(attrs, "node")
  text(boundary, "descr", attrs.at(3))
  put(boundary, "sprite", attrs.at(4))
  put(boundary, "tags", attrs.at(5))
  put(boundary, "link", attrs.at(6))
  boundary.nodeType = nodeType
  db.open(boundary)

proc popBoundaryParseStack*(db: C4Db) =
  if db.stack.len > 0: db.current = db.stack.pop()
  else: db.current = db.boundaries[0]

proc addRel*(db: C4Db, typ: string, attrs: seq[C4Attr]) =
  ## from, to, label, ?techn, ?descr, ?sprite, ?tags, $link
  if attrs.len < 3: return
  let start = attrs[0]
  let to = attrs[1]
  let known = not start.isNamed and not to.isNamed
  var rel: C4Rel = nil
  if known and start.s in db.relIndex: rel = db.relIndex[start.s].getOrDefault(to.s)
  if rel == nil:
    rel = C4Rel(typ: typ, offsetX: NaN, offsetY: NaN)
    db.rels.add rel
    if known: db.relIndex.mgetOrPut(start.s, initTable[string, C4Rel]())[to.s] = rel
    if not start.isNamed: rel.start = start.s
    else: rel.fromAttr = some(start)
    if not to.isNamed: rel.to = to.s
    else: rel.toAttr = some(to)
  rel.typ = typ
  label(rel, attrs.at(2))
  text(rel, "techn", attrs.at(3))
  text(rel, "descr", attrs.at(4))
  put(rel, "sprite", attrs.at(5))
  put(rel, "tags", attrs.at(6))
  put(rel, "link", attrs.at(7))

proc getC4Shape*(db: C4Db, alias: string): C4Element =
  result = db.shapeIndex.getOrDefault(alias)
  if result == nil: result = db.boundaryIndex.getOrDefault(alias)

proc updateElStyle*(db: C4Db, attrs: seq[C4Attr]) =
  ## elementName, ?bgColor, ?fontColor, ?borderColor, ?shadowing, ?shape, ?sprite, ?techn,
  ## ?legendText, ?legendSprite
  let el = if not attrs[0].isNamed: db.getC4Shape(attrs[0].s) else: nil
  if el == nil: return
  for i, field in ["bgColor", "fontColor", "borderColor", "shadowing", "shape", "sprite", "techn",
                   "legendText", "legendSprite"]:
    put(el, field, attrs.at(i + 1))

proc updateRelStyle*(db: C4Db, attrs: seq[C4Attr]) =
  ## from, to, ?textColor, ?lineColor, ?offsetX, ?offsetY
  if attrs.len < 2 or attrs[0].isNamed or attrs[1].isNamed: return
  if attrs[0].s notin db.relIndex: return
  let rel = db.relIndex[attrs[0].s].getOrDefault(attrs[1].s)
  if rel == nil: return
  put(rel, "textColor", attrs.at(2))
  put(rel, "lineColor", attrs.at(3))
  let x = attrs.at(4)
  let y = attrs.at(5)
  if x.isSome:
    if not x.get.isNamed: rel.offsetX = jsParseInt(x.get.s)
    else: named(rel, x.get)
  if y.isSome:
    if not y.get.isNamed: rel.offsetY = jsParseInt(y.get.s)
    else: named(rel, y.get)

proc updateLayoutConfig*(db: C4Db, attrs: seq[C4Attr]) =
  ## ?c4ShapeInRow, ?c4BoundaryInRow. The slot decides which one a value sets, not its name.
  proc count(attr: Option[C4Attr]): float =
    if attr.isNone: NaN
    else: jsParseInt(if attr.get.isNamed: attr.get.value else: attr.get.s)
  let shapes = count(attrs.at(0))
  let boundaries = count(attrs.at(1))
  if shapes >= 1: db.shapeInRow = shapes
  if boundaries >= 1: db.boundaryInRow = boundaries
