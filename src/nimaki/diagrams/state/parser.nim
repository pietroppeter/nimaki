## port-of: src/diagrams/state/parser.ts
## port-status: conformant
##
## Pele's `StateBuilder` (the calls Mermaid's grammar makes on its `yy` object) is the `StateDb`
## itself here.
import std/[options, strutils]
import ../../errors
import ../../js
import db, lexer, tokens, types

const DIRECTIONS = ["TB", "BT", "RL", "LR"]
const STATEMENT =
  "'NL', 'ID', 'HIDE_EMPTY', 'scale', 'COMPOSIT_STATE', 'STATE_DESCR', 'FORK', 'JOIN', 'CHOICE', 'CONCURRENT', 'note', " &
  "'acc_title', 'acc_descr', 'acc_descr_multiline_value', 'CLICK', 'classDef', 'style', 'class', 'direction_tb', " &
  "'direction_bt', 'direction_rl', 'direction_lr', 'EDGE_STATE'"

proc parseState*(src: string, db: StateDb): seq[Stmt] =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  let error = tokens.error
  var i = 0

  proc fail(expected: string) =
    let t = types[i]
    if t == T_ERROR:
      if error != "":
        let loc = locate(src, starts[i])
        raise newPeleError(error, "syntax", ErrorInfo(diagramType: "state", line: loc.line, column: loc.column,
                                                     snippet: loc.snippet))
      raise syntaxError("state", src, starts[i], "", true)
    raise syntaxError("state", src, starts[i], "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")
  proc expect(t: int): string =
    if types[i] != t: fail("'" & TOKEN_NAMES[t] & "'")
    result = texts[i]
    inc i
  proc idStatement(): Stmt =
    let t = types[i]
    if t != T_ID and t != T_EDGE_STATE: fail("'ID', 'EDGE_STATE'")
    let id = texts[i].jsTrim
    inc i
    if types[i] != T_STYLE_SEPARATOR:
      return Stmt(stmt: skState, id: id, kind: "default", descr: dkText, description: "")
    inc i
    Stmt(stmt: skState, id: id, hasClasses: true, classes: @[expect(T_ID).jsTrim], kind: "default", descr: dkText,
         description: "")

  while types[i] == T_NL: inc i
  if types[i] != T_SD: fail("'NL', 'SD'")
  inc i

  # The document being filled: the root, or the composite state last opened.
  let root = Stmt(stmt: skRoot)
  var doc = root
  var outer: seq[Stmt]
  # The grammar drops a statement whose value is the string it uses for a blank line.
  proc add(value: Stmt) =
    if not (value.stmt == skText and value.text == "nl"): doc.doc.add value
  proc opening(id, description: string) =
    inc i
    let inner = Stmt(stmt: skState, id: id, kind: "default", descr: dkText, description: description, hasDoc: true)
    doc.doc.add inner
    outer.add doc
    doc = inner

  while true:
    let t = types[i]
    case t
    of T_NL:
      inc i
    of T_ID, T_EDGE_STATE:
      let first = idStatement()
      if types[i] == T_DESCR:
        first.descr = dkText
        first.description = db.trimColon(texts[i])
        inc i
        add(first)
      elif types[i] == T_ARROW:
        inc i
        let second = idStatement()
        if types[i] == T_DESCR:
          let d = db.trimColon(texts[i])
          inc i
          add(Stmt(stmt: skRelation, state1: first, state2: second, relDescription: some(d)))
        else:
          add(Stmt(stmt: skRelation, state1: first, state2: second))
      else:
        add(first)
    of T_HIDE_EMPTY:
      add(textStmt(texts[i]))
      inc i
    of T_scale:
      inc i
      discard expect(T_WIDTH)
      add(textStmt(texts[i - 2]))
    of T_COMPOSIT_STATE:
      if types[i + 1] == T_STRUCT_START:
        let id = texts[i]
        inc i
        opening(id, "")
      else:
        add(textStmt(texts[i]))
        inc i
    of T_STATE_DESCR:
      let description = texts[i]
      inc i
      discard expect(T_AS)
      let id = expect(T_ID)
      if types[i] == T_STRUCT_START:
        opening(id, description)
      elif ':' in id:
        let parts = id.split(':')
        add(Stmt(stmt: skState, id: parts[0], kind: "default", descr: dkList,
                 descriptionList: @[description.jsTrim, parts[1]]))
      else:
        add(Stmt(stmt: skState, id: id, kind: "default", descr: dkText, description: description.jsTrim))
    of T_FORK:
      add(Stmt(stmt: skState, id: texts[i], kind: "fork"))
      inc i
    of T_JOIN:
      add(Stmt(stmt: skState, id: texts[i], kind: "join"))
      inc i
    of T_CHOICE:
      add(Stmt(stmt: skState, id: texts[i], kind: "choice"))
      inc i
    of T_CONCURRENT:
      inc i
      add(Stmt(stmt: skState, id: db.getDividerId(), kind: "divider"))
    of T_note:
      let keyword = texts[i]
      inc i
      if types[i] == T_left_of or types[i] == T_right_of:
        let position = texts[i].jsTrim
        inc i
        let id = expect(T_ID).jsTrim
        let text = expect(T_NOTE_TEXT).jsTrim
        add(Stmt(stmt: skState, id: id, hasNote: true, note: StateNote(position: position, text: text)))
      else:
        if types[i] != T_NOTE_TEXT: fail("'NOTE_TEXT', 'left_of', 'right_of'")
        inc i
        discard expect(T_AS)
        discard expect(T_ID)
        add(textStmt(keyword))
    of T_direction_tb, T_direction_bt, T_direction_rl, T_direction_lr:
      let value = DIRECTIONS[t - T_direction_tb]
      inc i
      db.setDirection(value)
      add(Stmt(stmt: skDir, value: value))
    of T_acc_title:
      inc i
      let value = expect(T_acc_title_value).jsTrim
      db.setAccTitle(value)
      add(textStmt(value))
    of T_acc_descr:
      inc i
      let value = expect(T_acc_descr_value).jsTrim
      db.setAccDescription(value)
      add(textStmt(value))
    of T_acc_descr_multiline_value:
      let value = texts[i].jsTrim
      inc i
      db.setAccDescription(value)
      add(textStmt(value))
    of T_CLICK:
      inc i
      let id = idStatement()
      var url: string
      var tooltip = ""
      if types[i] == T_HREF:
        inc i
        url = expect(T_STRING)
      else:
        if types[i] != T_STRING: fail("'STRING', 'HREF'")
        url = texts[i]
        inc i
        tooltip = expect(T_STRING)
      discard expect(T_NL)
      add(Stmt(stmt: skClick, clickId: id, url: url, tooltip: tooltip))
    of T_classDef:
      inc i
      let id = expect(T_CLASSDEF_ID).jsTrim
      add(Stmt(stmt: skClassDef, id: id, classesText: expect(T_CLASSDEF_STYLEOPTS).jsTrim))
    of T_style:
      inc i
      let id = expect(T_STYLE_IDS).jsTrim
      add(Stmt(stmt: skStyle, id: id, styleClass: expect(T_STYLEDEF_STYLEOPTS).jsTrim))
    of T_class:
      inc i
      let id = expect(T_CLASSENTITY_IDS).jsTrim
      add(Stmt(stmt: skApplyClass, id: id, styleClass: expect(T_STYLECLASS).jsTrim))
    of T_STRUCT_STOP:
      if outer.len == 0: fail("'$end', " & STATEMENT)
      inc i
      doc = outer.pop()
    of T_END:
      if outer.len > 0: fail("'STRUCT_STOP', " & STATEMENT)
      db.setRootDoc(root.doc)
      return root.doc
    else:
      fail(if outer.len > 0: "'STRUCT_STOP', " & STATEMENT else: "'$end', " & STATEMENT)
