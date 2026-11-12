## port-of: src/diagrams/class/parser.ts
## port-status: draft
import ../../errors
import ../../js
import db, lexer, tokens

const COUNT = T_PUNCTUATION + 1

const ALPHANUM = block:
  var t: array[COUNT, bool]
  for k in [T_UNICODE_TEXT, T_ALPHA, T_MINUS]: t[k] = true
  t

const STYLE_PART = block:
  var t: array[COUNT, bool]
  for k in [T_ALPHA, T_COLON, T_BRKT, T_STYLE, T_PCT, T_LABEL]: t[k] = true
  t

const END_TYPE = block:
  ## Mermaid's relationType numbers, plus one so that zero means "not an end marker".
  var t: array[COUNT, int]
  t[T_AGGREGATION] = 1
  t[T_EXTENSION] = 2
  t[T_COMPOSITION] = 3
  t[T_DEPENDENCY] = 4
  t[T_LOLLIPOP] = 5
  t

const NAME_TOKENS = "'UNICODE_TEXT', 'NUM', 'ALPHA', 'MINUS', 'BQUOTE_STR'"

type Frame = object
  id: string
  classes, notes: seq[string]

proc parseClassDiagram*(src: string, db: ClassDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  var i = 0

  proc fail(expected: string) {.noreturn.} =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("class", src, starts[i], "", true)
    raise syntaxError("class", src, starts[i], "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")

  proc expect(kind: int): string =
    if types[i] != kind: fail("'" & TOKEN_NAMES[kind] & "'")
    result = texts[i]
    inc i

  proc take(): string =
    result = texts[i]
    inc i

  proc alphaNum(): string =
    if not ALPHANUM[types[i]]: fail("'UNICODE_TEXT', 'NUM', 'ALPHA', 'MINUS'")
    take()

  proc name(generic: bool): string =
    var output = ""
    while true:
      if types[i] == T_BQUOTE_STR:
        output.add take()
        break
      if not ALPHANUM[types[i]]: fail(NAME_TOKENS)
      output.add take()
      let t = types[i]
      if t == T_DOT:
        output.add '.'
        inc i
      elif not ALPHANUM[t] and t != T_BQUOTE_STR:
        break
    if generic and types[i] == T_GENERICTYPE: output.add "~" & take() & "~"
    output

  proc classLabel(): string =
    inc i
    result = expect(T_STR)
    discard expect(T_SQE)

  proc members(): seq[string] =
    if types[i] != T_MEMBER: fail("'STRUCT_STOP', 'MEMBER'")
    var list: seq[string]
    while types[i] == T_MEMBER: list.add take()
    discard expect(T_STRUCT_STOP)
    # The grammar collects members last to first, and addMembers turns them back.
    for k in countdown(list.len - 1, 0): result.add list[k]

  proc classStatement(): string =
    inc i
    let id = name(true)
    db.addClass(id)
    if types[i] == T_SQS: db.setClassLabel(id, classLabel())
    case types[i]
    of T_STYLE_SEPARATOR:
      inc i
      let css = alphaNum()
      db.setCssClass(id, css)
      if types[i] == T_STRUCT_START:
        inc i
        db.addMembers(id, members())
    of T_STRUCT_START:
      inc i
      if types[i] == T_STRUCT_STOP: inc i
      else: db.addMembers(id, members())
    of T_ANNOTATION_START:
      inc i
      let annotation = alphaNum()
      discard expect(T_ANNOTATION_END)
      db.addAnnotation(id, annotation)
      if types[i] == T_STRUCT_START:
        inc i
        if types[i] == T_STRUCT_STOP: inc i
        else: db.addMembers(id, members())
    else: discard
    id

  proc noteStatement(): string =
    let kind = types[i]
    inc i
    if kind == T_NOTE: return db.addNote(expect(T_STR))
    let id = name(true)
    db.addNote(expect(T_STR), id)

  # Namespaces nest, so they are parsed with a stack of open ones.
  proc namespaceStatement() =
    var open: seq[Frame]
    while true:
      inc i
      let ns = name(false)
      let id = if types[i] == T_SQS: db.addNamespace(ns, classLabel()) else: db.addNamespace(ns)
      discard expect(T_STRUCT_START)
      if types[i] == T_NEWLINE: inc i
      open.add Frame(id: id)
      var item = true
      while item:
        let t = types[i]
        if t == T_NAMESPACE: break
        if t == T_CLASS: open[^1].classes.add classStatement()
        elif t == T_NOTE or t == T_NOTE_FOR: open[^1].notes.add noteStatement()
        else: fail("'NAMESPACE', 'CLASS', 'NOTE_FOR', 'NOTE'")
        while true:
          if types[i] == T_NEWLINE:
            let next = types[i + 1]
            if next == T_NAMESPACE or next == T_CLASS or next == T_NOTE or next == T_NOTE_FOR:
              inc i
              break
            inc i
          discard expect(T_STRUCT_STOP)
          let done = open.pop()
          db.addClassesToNamespace(done.id, done.classes, done.notes)
          db.popNamespace()
          if open.len == 0:
            item = false
            break
      if open.len == 0: return

  proc relationEnd(): RelationEnd =
    let kind = END_TYPE[types[i]]
    if kind == 0: return NONE
    inc i
    kind - 1

  proc classOrRelation() =
    let id1 = name(true)
    var t = types[i]
    if t == T_LABEL:
      db.addMember(id1, cleanupLabel(take()))
      return
    var title1 = "none"
    if t == T_STR:
      title1 = take()
      t = types[i]
    elif END_TYPE[t] == 0 and t != T_LINE and t != T_DOTTED_LINE:
      return
    let type1 = relationEnd()
    t = types[i]
    if t != T_LINE and t != T_DOTTED_LINE:
      fail("'AGGREGATION', 'EXTENSION', 'COMPOSITION', 'DEPENDENCY', 'LOLLIPOP', 'LINE', 'DOTTED_LINE'")
    inc i
    let type2 = relationEnd()
    let title2 = if types[i] == T_STR: take() else: "none"
    let id2 = name(true)
    let relation = ClassRelation(id1: id1, id2: id2,
                                 relation: Relation(type1: type1, type2: type2, lineType: (if t == T_LINE: 0 else: 1)),
                                 relationTitle1: title1, relationTitle2: title2)
    if types[i] == T_LABEL: relation.title = cleanupLabel(take())
    db.addRelation(relation)

  proc styles(): seq[string] =
    while true:
      if not STYLE_PART[types[i]]: fail("'ALPHA', 'NUM', 'COLON', 'UNIT', 'SPACE', 'BRKT', 'STYLE', 'PCT', 'LABEL'")
      var s = take()
      while STYLE_PART[types[i]]: s.add take()
      result.add s
      if types[i] != T_COMMA: return
      inc i

  proc tooltip(id: string) =
    if types[i] == T_STR: db.setTooltip(id, take())

  proc linkStatement(id: string) =
    let href = expect(T_STR)
    let tip = if types[i] == T_STR: take() else: ""
    if types[i] == T_LINK_TARGET: db.setLink(id, href, take(), true)
    else: db.setLink(id, href)
    if tip != "": db.setTooltip(id, tip)

  proc statement() =
    let t = types[i]
    case t
    of T_UNICODE_TEXT, T_ALPHA, T_MINUS, T_BQUOTE_STR:
      classOrRelation()
      return
    of T_NAMESPACE:
      namespaceStatement()
      return
    of T_CLASS:
      discard classStatement()
      return
    of T_MEMBER:
      inc i
      return
    of T_ANNOTATION_START:
      inc i
      let annotation = alphaNum()
      discard expect(T_ANNOTATION_END)
      db.addAnnotation(name(true), annotation)
      return
    of T_CALLBACK:
      inc i
      let id = name(true)
      discard expect(T_STR)
      db.setClickEvent(id)
      tooltip(id)
      return
    of T_LINK:
      inc i
      linkStatement(name(true))
      return
    of T_CLICK:
      inc i
      let id = name(true)
      if types[i] == T_HREF:
        inc i
        linkStatement(id)
        return
      discard expect(T_CALLBACK_NAME)
      if types[i] == T_CALLBACK_ARGS: inc i
      db.setClickEvent(id)
      tooltip(id)
      return
    of T_STYLE:
      inc i
      let id = expect(T_ALPHA)
      db.setCssStyle(id, styles())
      return
    of T_CSSCLASS:
      inc i
      let ids = expect(T_STR)
      db.setCssClass(ids, expect(T_ALPHA))
      return
    of T_NOTE, T_NOTE_FOR:
      discard noteStatement()
      return
    of T_CLASSDEF:
      inc i
      var ids = @[expect(T_ALPHA)]
      while types[i] == T_COMMA:
        inc i
        ids.add expect(T_ALPHA)
      db.defineClass(ids, styles())
      return
    of T_direction_tb, T_direction_bt, T_direction_rl, T_direction_lr:
      inc i
      db.setDirection(if t == T_direction_tb: "TB" elif t == T_direction_bt: "BT" elif t == T_direction_rl: "RL" else: "LR")
      return
    of T_acc_title:
      inc i
      db.setAccTitle(jsTrim(expect(T_acc_title_value)))
      return
    of T_acc_descr:
      inc i
      db.setAccDescription(jsTrim(expect(T_acc_descr_value)))
      return
    of T_acc_descr_multiline_value:
      db.setAccDescription(jsTrim(take()))
      return
    else: discard
    fail("'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'NAMESPACE', 'ANNOTATION_START', 'CLASS', 'MEMBER', 'NOTE_FOR', 'NOTE', 'CLASSDEF', 'direction_tb', 'CALLBACK', 'LINK', 'CLICK', 'STYLE', 'CSSCLASS', 'ALPHA', 'MINUS', 'BQUOTE_STR'")

  # Mermaid's grammar also accepts statements with no `classDiagram` line before them.
  let header = types[i] == T_CLASS_DIAGRAM
  if header:
    inc i
    discard expect(T_NEWLINE)
  while true:
    statement()
    if types[i] != T_NEWLINE: break
    inc i
    if types[i] == T_EOF or types[i] == T_STOP: break
  if header: discard expect(T_EOF)
  discard expect(T_STOP)
