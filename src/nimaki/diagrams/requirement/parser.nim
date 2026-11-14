## port-of: src/diagrams/requirement/parser.ts
## port-status: conformant
import std/strutils
import ../../errors
import ../../js
import db, lexer, tokens

# What the keyword tokens stand for, from REQUIREMENT to TRACES in token order.
const VALUES = [
  RT_REQUIREMENT, FUNCTIONAL_REQUIREMENT, INTERFACE_REQUIREMENT, PERFORMANCE_REQUIREMENT, PHYSICAL_REQUIREMENT,
  DESIGN_CONSTRAINT, LOW_RISK, MED_RISK, HIGH_RISK, VERIFY_ANALYSIS, VERIFY_DEMONSTRATION, VERIFY_INSPECTION,
  VERIFY_TEST, "", CONTAINS, COPIES, DERIVES, SATISFIES, VERIFIES, REFINES, TRACES,
]

func isStylePart(t: int): bool =
  t == T_ALPHA or t == T_COLON or t == T_BRKT or t == T_MINUS or t == T_SEMICOLON

proc parseRequirement*(src: string, db: RequirementDb) =
  let tokens = tokenize(src)
  let types = tokens.types
  let texts = tokens.texts
  let starts = tokens.starts
  var i = 0
  var fields: seq[int]
  var values: seq[string]

  proc typeAt(k: int): int = (if k < types.len: types[k] else: -1)

  # Fails with Jison's wording, naming the token types `from` to `to` and any others as expected.
  proc fail(lo: int, hi = -1, others: varargs[int]) =
    let hi = if hi == -1: lo else: hi
    let t = types[i]
    if t == T_ERROR: raise syntaxError("requirement", src, starts[i], "", true)
    var all: seq[int]
    for k in lo .. hi: all.add k
    for k in others: all.add k
    var names: seq[string]
    for k in all: names.add "'" & TOKEN_NAMES[k] & "'"
    raise syntaxError("requirement", src, starts[i], "Expecting " & names.join(", ") & ", got '" &
                      TOKEN_NAMES[t] & "'")

  proc expect(t: int): string =
    if typeAt(i) != t: fail(t)
    result = texts[i]
    inc i

  # The value of the next token if it is a keyword in the given range of token types.
  proc keyword(lo, hi: int): string =
    let t = typeAt(i)
    if t < lo or t > hi: fail(lo, hi)
    inc i
    VALUES[t - T_REQUIREMENT]

  proc str(): string =
    let t = typeAt(i)
    if t != T_unqString and t != T_qString: fail(T_qString, T_unqString)
    result = texts[i]
    inc i

  proc directive(): bool =
    let t = typeAt(i)
    if t == T_acc_title:
      inc i
      db.setAccTitle(expect(T_acc_title_value).jsTrim)
    elif t == T_acc_descr:
      inc i
      db.setAccDescription(expect(T_acc_descr_value).jsTrim)
    elif t == T_acc_descr_multiline_value:
      db.setAccDescription(texts[i].jsTrim)
      inc i
    else:
      return false
    true

  proc idList(): seq[string] =
    while true:
      let t = typeAt(i)
      if t != T_ALPHA and t != T_unqString and t != T_qString: fail(T_qString, T_unqString, T_ALPHA)
      result.add texts[i]
      inc i
      if typeAt(i) != T_COMMA: return
      inc i

  proc stylesOpt(): seq[string] =
    while true:
      if not isStylePart(typeAt(i)): fail(T_ALPHA, T_SEMICOLON, T_MINUS, T_BRKT)
      var style = texts[i]
      inc i
      while isStylePart(typeAt(i)):
        style.add texts[i]
        inc i
      result.add style
      if typeAt(i) != T_COMMA: return
      inc i

  proc classList(): (bool, seq[string]) =
    if typeAt(i) == T_STYLE_SEPARATOR:
      inc i
      result = (true, idList())
      discard expect(T_STRUCT_START)
    elif typeAt(i) == T_STRUCT_START:
      inc i
    else:
      fail(T_STRUCT_START, T_STRUCT_START, T_STYLE_SEPARATOR)
    discard expect(T_NEWLINE)

  # Reads a body up to its closing brace. The grammar is right recursive, so Mermaid applies
  # the fields last to first and the first of two repeated fields wins.
  proc body(requirement: bool) =
    fields.setLen 0
    values.setLen 0
    while true:
      let t = typeAt(i)
      if t == T_STRUCT_STOP:
        inc i
        break
      if t == T_NEWLINE:
        inc i
        continue
      if (if requirement: t < T_ID or t > T_VERIFYMTHD else: t != T_TYPE and t != T_DOCREF):
        if requirement: fail(T_ID, T_VERIFYMTHD, T_NEWLINE, T_STRUCT_STOP)
        fail(T_TYPE, T_DOCREF, T_NEWLINE, T_STRUCT_STOP)
      inc i
      discard expect(T_COLONSEP)
      values.add(
        if t == T_RISK: keyword(T_LOW_RISK, T_HIGH_RISK)
        elif t == T_VERIFYMTHD: keyword(T_VERIFY_ANALYSIS, T_VERIFY_TEST)
        else: str())
      fields.add t
      discard expect(T_NEWLINE)
    for k in countdown(fields.high, 0):
      let value = values[k]
      case fields[k]
      of T_ID: db.setNewReqId(value)
      of T_TEXT: db.setNewReqText(value)
      of T_RISK: db.setNewReqRisk(value)
      of T_VERIFYMTHD: db.setNewReqVerifyMethod(value)
      of T_TYPE: db.setNewElementType(value)
      else: db.setNewElementDocRef(value)

  while directive():
    if typeAt(i) == T_NEWLINE: inc i
  if typeAt(i) != T_RD: fail(T_RD, T_RD, T_acc_title, T_acc_descr, T_acc_descr_multiline_value)
  inc i
  discard expect(T_NEWLINE)

  while true:
    let t = typeAt(i)
    if t == T_EOF: return
    if t == T_NEWLINE:
      inc i
    elif directive():
      continue
    elif t >= T_direction_tb and t <= T_direction_lr:
      inc i
      db.setDirection(if t == T_direction_tb: "TB" elif t == T_direction_bt: "BT" elif t == T_direction_rl: "RL"
                      else: "LR")
    elif t >= T_REQUIREMENT and t <= T_DESIGN_CONSTRAINT:
      let kind = keyword(T_REQUIREMENT, T_DESIGN_CONSTRAINT)
      let name = str()
      let (hasClasses, classes) = classList()
      body(true)
      discard db.addRequirement(name, kind)
      if hasClasses: db.setClass(@[name], classes)
    elif t == T_ELEMENT:
      inc i
      let name = str()
      let (hasClasses, classes) = classList()
      body(false)
      discard db.addElement(name)
      if hasClasses: db.setClass(@[name], classes)
    elif t == T_STYLE:
      inc i
      let ids = idList()
      db.setCssStyle(ids, stylesOpt())
    elif t == T_CLASSDEF:
      inc i
      let ids = idList()
      db.defineClass(ids, stylesOpt())
    elif t == T_CLASS:
      inc i
      let ids = idList()
      db.setClass(ids, idList())
    elif t == T_unqString or t == T_qString:
      let id = texts[i]
      inc i
      let next = typeAt(i)
      if next == T_STYLE_SEPARATOR:
        inc i
        db.setClass(@[id], idList())
      elif next == T_END_ARROW_L or next == T_LINE:
        inc i
        let relationship = keyword(T_CONTAINS, T_TRACES)
        discard expect(if next == T_LINE: T_END_ARROW_R else: T_LINE)
        let other = str()
        if next == T_LINE: db.addRelationship(relationship, id, other)
        else: db.addRelationship(relationship, other, id)
      else:
        fail(T_STYLE_SEPARATOR, T_STYLE_SEPARATOR, T_END_ARROW_L, T_LINE)
    else:
      fail(T_NEWLINE, T_NEWLINE, T_EOF, T_acc_title, T_acc_descr, T_acc_descr_multiline_value, T_direction_tb,
           T_direction_bt, T_direction_rl, T_direction_lr, T_REQUIREMENT, T_FUNCTIONAL_REQUIREMENT,
           T_INTERFACE_REQUIREMENT, T_PERFORMANCE_REQUIREMENT, T_PHYSICAL_REQUIREMENT, T_DESIGN_CONSTRAINT,
           T_ELEMENT, T_CLASSDEF, T_CLASS, T_STYLE, T_unqString, T_qString)
