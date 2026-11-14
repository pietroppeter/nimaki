## port-of: src/diagrams/architecture/db.ts
## port-status: conformant
import std/[tables, sets, options]
import ../../errors
import ../../js
import parser

type
  ArchNode* = object
    id*: string
    junction*: bool               ## Pele's type: 'junction' (else 'service')
    icon*, iconText*, title*, parent*: Option[string]   ## `parent` is Pele's `in`

  ArchGroup* = object
    id*: string
    icon*, title*, parent*: Option[string]

  ArchEdge* = object
    lhsId*: string
    lhsDir*: char
    lhsInto*, lhsGroup*: bool
    rhsId*: string
    rhsDir*: char
    rhsInto*, rhsGroup*: bool
    title*: Option[string]

  ArchLayoutHint* = object
    direction*: string
    members*: seq[string]

  ArchitectureDb* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    nodes*: OrderedTable[string, ArchNode]
    groups*: OrderedTable[string, ArchGroup]
    edges*: seq[ArchEdge]
    layoutHints*: seq[ArchLayoutHint]
    registered: Table[string, string]      ## "node" or "group"

proc fail(message: string) {.noreturn.} =
  raise newPeleError(message, "semantic", "architecture")

proc register(db: ArchitectureDb, kind, id: string, parent: Option[string]) =
  if id in db.registered:
    fail("The " & kind & " id [" & id & "] is already in use by another " & db.registered[id])
  if parent.isSome:
    let p = parent.get
    if id == p: fail("The " & kind & " [" & id & "] cannot be placed within itself")
    if p notin db.registered:
      fail("The " & kind & " [" & id & "]'s parent does not exist. Please make sure the parent is created before this " & kind)
    if db.registered[p] == "node": fail("The " & kind & " [" & id & "]'s parent is not a group")
  db.registered[id] = (if kind == "group": "group" else: "node")

proc addService*(db: ArchitectureDb, s: ServiceAst) =
  db.register("service", s.id, s.parent)
  db.nodes[s.id] = ArchNode(id: s.id, icon: s.icon, iconText: s.iconText, title: s.title, parent: s.parent)

proc addJunction*(db: ArchitectureDb, j: JunctionAst) =
  db.register("junction", j.id, j.parent)
  db.nodes[j.id] = ArchNode(id: j.id, junction: true, parent: j.parent)

proc addGroup*(db: ArchitectureDb, g: GroupAst) =
  db.register("group", g.id, g.parent)
  db.groups[g.id] = ArchGroup(id: g.id, icon: g.icon, title: g.title, parent: g.parent)

proc addEdge*(db: ArchitectureDb, e: EdgeAst) =
  let ends = [("left", e.lhsId, e.lhsGroup), ("right", e.rhsId, e.rhsGroup)]
  for (side, id, _) in ends:
    if id notin db.registered:
      fail("The " & side & "-hand id [" & id & "] does not yet exist. Please create the service/group before declaring an edge to it.")
  # Mermaid lets a group id through the check above and then fails with a TypeError.
  for (side, id, _) in ends:
    if id notin db.nodes: fail("The " & side & "-hand id [" & id & "] is a group. Add {group} to a service inside it instead.")
  let parent = db.nodes[e.lhsId].parent
  if parent.isSome and parent == db.nodes[e.rhsId].parent:
    for (side, id, crosses) in ends:
      if crosses:
        fail("The " & side & "-hand id [" & id & "] is modified to traverse the group boundary, but the edge does not pass through two groups.")
  db.edges.add ArchEdge(lhsId: e.lhsId, lhsDir: e.lhsDir, lhsInto: e.lhsInto, lhsGroup: e.lhsGroup,
                        rhsId: e.rhsId, rhsDir: e.rhsDir, rhsInto: e.rhsInto, rhsGroup: e.rhsGroup, title: e.title)

proc addLayoutHint*(db: ArchitectureDb, hint: ArchLayoutHint) =
  if hint.members.len < 2: fail("An align directive requires at least two members; got " & $hint.members.len)
  var seen = initHashSet[string]()
  for id in hint.members:
    if db.registered.getOrDefault(id, "") != "node":
      fail("align " & hint.direction & " references [" & id & "], which is not a service or junction")
    if id in seen: fail("align " & hint.direction & " lists [" & id & "] more than once")
    seen.incl id
  db.layoutHints.add hint

func dropBreakSpaces(text: string): string =
  ## text.replace(/\n\s+/g, '\n')
  var i = 0
  while i < text.len:
    if text[i] == '\n' and spaceLenAt(text, i + 1) > 0:
      result.add '\n'
      i += 1
      while true:
        let n = spaceLenAt(text, i)
        if n == 0: break
        i += n
    else:
      result.add text[i]
      inc i

proc populate*(ast: ArchitectureAst, db: ArchitectureDb) =
  ## Mermaid's populateDb: every group, then services, junctions, edges, and alignments.
  if ast.accDescr != "": db.accDescr = dropBreakSpaces(ast.accDescr)
  if ast.accTitle != "": db.accTitle = jsTrimStart(ast.accTitle)
  if ast.title != "": db.title = ast.title
  for group in ast.groups: db.addGroup(group)
  for service in ast.services: db.addService(service)
  for junction in ast.junctions: db.addJunction(junction)
  for edge in ast.edges: db.addEdge(edge)
  for alignment in ast.alignments:
    db.addLayoutHint(ArchLayoutHint(direction: alignment.direction, members: alignment.members))
