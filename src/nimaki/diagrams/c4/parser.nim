## port-of: src/diagrams/c4/parser.ts
## port-status: draft
import ../../errors
import ../../js
import db, lexer, tokens

const
  KINDS = ["person", "external_person", "system", "system_db", "system_queue", "external_system",
    "external_system_db", "external_system_queue", "container", "container_db", "container_queue",
    "external_container", "external_container_db", "external_container_queue", "component",
    "component_db", "component_queue", "external_component", "external_component_db",
    "external_component_queue"]
  REL_TYPES = ["rel", "birel", "rel_u", "rel_d", "rel_l", "rel_r", "rel_b", "rel"]
  NODE_TYPES = ["node", "nodeL", "nodeR"]
  HEADERS = "'direction_tb', 'direction_bt', 'direction_rl', 'direction_lr', 'C4_CONTEXT', 'C4_CONTAINER', 'C4_COMPONENT', 'C4_DYNAMIC', 'C4_DEPLOYMENT'"
  ATTRIBUTES = "'STR', 'STR_KEY', 'ATTRIBUTE', 'ATTRIBUTE_EMPTY'"

  # const enum P
  P_Item = 0         ## A statement is required.
  P_Diagram = 1      ## Only a diagram statement may come next.
  P_ItemOrEnd = 2
  P_AfterOther = 3
  P_AfterDiagram = 4

func isOther(t: int): bool =
  t == T_title or t == T_accDescription or t == T_acc_title or t == T_acc_descr or
    t == T_acc_descr_multiline_value

func isDiagram(t: int): bool = t >= T_PERSON and t <= T_UPDATE_LAYOUT_CONFIG

proc parseC4*(src: string, db: C4Db) =
  ## Accepts what the parser Jison generates from c4Diagram.jison accepts, and calls the model
  ## builder in the order its semantic actions do. Boundaries nest through a counter.
  let toks = tokenize(src)
  let types = toks.types
  var i = 0

  proc text(at: int): string = src[toks.starts[at] ..< toks.ends[at]]
  proc fail(expected: string) {.noreturn.} =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("c4", src, toks.starts[i], "", true)
    raise syntaxError("c4", src, toks.starts[i],
      "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")
  proc expect(typ: int) =
    if types[i] != typ: fail("'" & TOKEN_NAMES[typ] & "'")
    inc i

  proc attributes(): seq[C4Attr] =
    while true:
      let t = types[i]
      if t == T_STR:
        result.add C4Attr(s: jsTrim(text(i)))
        inc i
      elif t == T_ATTRIBUTE_EMPTY:
        result.add C4Attr(s: "")
        inc i
      elif t == T_STR_KEY:
        inc i
        if types[i] != T_STR_VALUE: fail("'STR_VALUE'")
        result.add C4Attr(isNamed: true, key: jsTrim(text(i - 1)), value: jsTrim(text(i)))
        inc i
      else:
        break
    if result.len == 0: fail(ATTRIBUTES)

  proc other(t: int) =
    if t == T_title:
      db.setTitle(substringFrom(text(i), 6))
      inc i
    elif t == T_accDescription:
      db.setAccDescription(substringFrom(text(i), 15))
      inc i
    elif t == T_acc_descr_multiline_value:
      db.setAccDescription(jsTrim(text(i)))
      inc i
    else:
      inc i
      if t == T_acc_title:
        if types[i] != T_acc_title_value: fail("'acc_title_value'")
        # The grammar hands `accTitle:` to setTitle, so it becomes the visible title.
        db.setTitle(jsTrim(text(i)))
      else:
        if types[i] != T_acc_descr_value: fail("'acc_descr_value'")
        db.setAccDescription(jsTrim(text(i)))
      inc i

  proc diagram(t: int): bool =
    ## True when the statement opens a boundary.
    inc i
    var attrs = attributes()
    if t <= T_SYSTEM_EXT_QUEUE:
      db.addPersonOrSystem(KINDS[t - T_PERSON], attrs)
    elif t <= T_CONTAINER_EXT_QUEUE:
      db.addContainer(KINDS[t - T_PERSON], attrs)
    elif t <= T_COMPONENT_EXT_QUEUE:
      db.addComponent(KINDS[t - T_PERSON], attrs)
    elif t <= T_NODE_R:
      let at = min(2, attrs.len)
      if t == T_ENTERPRISE_BOUNDARY: attrs.insert(C4Attr(s: "ENTERPRISE"), at)
      elif t == T_SYSTEM_BOUNDARY: attrs.insert(C4Attr(s: "SYSTEM"), at)
      elif t == T_CONTAINER_BOUNDARY: attrs.insert(C4Attr(s: "CONTAINER"), at)
      if t >= T_NODE: db.addDeploymentNode(NODE_TYPES[t - T_NODE], attrs)
      elif t == T_CONTAINER_BOUNDARY: db.addContainerBoundary(attrs)
      else: db.addPersonOrSystemBoundary(attrs)
      if types[i] == T_LBRACE:
        inc i
        expect(T_NEWLINE)
      elif types[i] == T_NEWLINE:
        inc i
        expect(T_LBRACE)
        if types[i] == T_NEWLINE: inc i
      else:
        fail("'NEWLINE', 'LBRACE'")
      return true
    elif t <= T_REL_INDEX:
      # RelIndex takes a sequence number first, which Mermaid ignores.
      if t == T_REL_INDEX: attrs.delete(0)
      db.addRel(REL_TYPES[t - T_REL], attrs)
    elif t == T_UPDATE_EL_STYLE:
      db.updateElStyle(attrs)
    elif t == T_UPDATE_REL_STYLE:
      db.updateRelStyle(attrs)
    else:
      db.updateLayoutConfig(attrs)
    false

  let header = types[i]
  if header < T_C4_CONTEXT or header > T_C4_DEPLOYMENT: fail(HEADERS)
  inc i
  expect(T_NEWLINE)

  var depth = 0
  var state = P_Item
  while true:
    let t = types[i]
    if state == P_AfterOther or state == P_AfterDiagram:
      if t == T_NEWLINE:
        inc i
        state = P_ItemOrEnd
        continue
      if state == P_AfterOther and isDiagram(t):
        state = P_Diagram
        continue
    elif isDiagram(t):
      if diagram(t):
        inc depth
        state = P_Diagram
      else:
        state = P_AfterDiagram
      continue
    elif isOther(t) and state != P_Diagram:
      other(t)
      state = P_AfterOther
      continue
    elif state != P_ItemOrEnd:
      fail("'title', 'accDescription', 'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'PERSON', 'REL'")

    if depth > 0:
      if t != T_RBRACE: fail("'NEWLINE', 'RBRACE'")
      inc i
      db.popBoundaryParseStack()
      dec depth
      state = P_AfterDiagram
    else:
      if t != T_EOF: fail("'NEWLINE', 'EOF'")
      inc i
      expect(T_STOP)
      db.setC4Type(text(0))
      return
