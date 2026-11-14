## port-of: src/diagrams/treeview/parser.ts
## port-status: conformant
import std/strutils
import ../common/[tokens, acc_descr]
import ../../js
import ../../util/chars

const
  # const enum T: the index of each token type in TREEVIEW_TOKENS
  T_keyword = 0
  T_accDescr = 1
  T_accTitle = 2
  T_title = 3
  T_classAnnotation = 4
  T_iconAnnotation = 5
  T_descAnnotation = 6
  T_indentation = 7
  T_quotedName = 8
  T_ws {.used.} = 9
  T_comment {.used.} = 10
  T_newline {.used.} = 11
  T_bareName = 12

func code(src: string, i: int): int = (if i < src.len: ord(src[i]) else: -1)

func annotationAt(src: string, at: int): bool =
  if src.continuesWith("##", at) or src.continuesWith("icon(", at): return true
  if not src.continuesWith(":::", at): return false
  var i = at + 3
  while isBlank(code(src, i)): inc i
  let c = code(src, i)
  (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

func matchBareName(src: string, at: int): int =
  ## /(?!:::|icon\(|##)[^ \t\n\r"'](?:(?![ \t]+:::[ \t]*[A-Za-z_]|[ \t]+icon\(|[ \t]+##)[^\n\r])*/y
  ## The pattern looks ahead from every blank for an annotation, which rescans long runs of
  ## blanks. This looks once per run.
  let first = code(src, at)
  if isBlank(first) or first == 10 or first == 13 or first == 34 or first == 39: return -1
  if src.continuesWith(":::", at) or src.continuesWith("icon(", at) or src.continuesWith("##", at):
    return -1
  let n = src.len
  var i = at + 1          # a character outside ASCII continues the name, byte by byte
  while i < n:
    let c = ord(src[i])
    if c == 10 or c == 13: break
    if isBlank(c):
      var j = i + 1
      while isBlank(code(src, j)): inc j
      if annotationAt(src, j): break
      i = j
    else:
      inc i
  i

let BARE_NAME = TokenType(name: "BARE_NAME", pattern: matchBareName)

func blanksEnd(src: string, at: int): int =
  ## [ \t]* from at
  result = at
  while result < src.len and src[result] in {' ', '\t'}: inc result

func wordsEnd(src: string, at: int): int =
  ## [\w-]* from at
  result = at
  while result < src.len and (isWordChar(src[result]) or src[result] == '-'): inc result

func matchClass(src: string, at: int): int =
  ## /[ \t]+:::[ \t]*[A-Za-z_][\w-]*/y
  let i = blanksEnd(src, at)
  if i == at or not src.continuesWith(":::", i): return -1
  let j = blanksEnd(src, i + 3)
  if j >= src.len or src[j] notin {'A'..'Z', 'a'..'z', '_'}: return -1
  wordsEnd(src, j + 1)

func matchIcon(src: string, at: int): int =
  ## /[ \t]+icon\([\w-]*(?::[\w-]+)?\)/y
  let i = blanksEnd(src, at)
  if i == at or not src.continuesWith("icon(", i): return -1
  var j = wordsEnd(src, i + 5)
  if j < src.len and src[j] == ':':
    let k = wordsEnd(src, j + 1)
    if k > j + 1: j = k
  if j < src.len and src[j] == ')': j + 1 else: -1

func matchDesc(src: string, at: int): int =
  ## /[ \t]+##[^\n\r]*/y
  let i = blanksEnd(src, at)
  if i == at or not src.continuesWith("##", i): return -1
  result = i + 2
  while result < src.len and src[result] notin {'\n', '\r'}: inc result

func matchBlanks(src: string, at: int): int =
  ## /[ \t]{1,}/y and /[ \t]+/y
  let i = blanksEnd(src, at)
  if i == at: -1 else: i

func matchQuoted(src: string, at: int): int =
  ## /"[^"]*"|'[^']*'/y
  if at >= src.len or src[at] notin {'"', '\''}: return -1
  let close = src.find(src[at], at + 1)
  if close == -1: -1 else: close + 1

func matchComment(src: string, at: int): int =
  ## /\%\%[^\n]*/y
  if not src.continuesWith("%%", at): return -1
  let stop = src.find('\n', at + 2)
  if stop == -1: src.len else: stop

func matchNewline(src: string, at: int): int =
  ## /\r?\n/y
  if code(src, at) == 10: at + 1
  elif code(src, at) == 13 and code(src, at + 1) == 10: at + 2
  else: -1

proc withLonger(t: TokenType, longer: seq[TokenType]): TokenType =
  ## `{ ...t, longer }`
  result = TokenType()
  result[] = t[]
  result.longer = longer

func titleRest(s: string, i: int): bool =
  ## (?!%%)[^\n\r]
  i < s.len and s[i] notin {'\n', '\r'} and not s.continuesWith("%%", i)

let TREEVIEW_TOKENS*: seq[TokenType] = @[
  keyword("treeView-beta").withLonger(@[BARE_NAME]),
  accDescr(),
  ACC_TITLE,
  titleBefore(titleRest),
  TokenType(name: "CLASS_ANNOTATION", pattern: matchClass, first: " \t", hasFirst: true),
  TokenType(name: "ICON_ANNOTATION", pattern: matchIcon, first: " \t", hasFirst: true),
  TokenType(name: "DESC_ANNOTATION", pattern: matchDesc, first: " \t", hasFirst: true),
  TokenType(name: "INDENTATION", pattern: matchBlanks, first: " \t", hasFirst: true),
  TokenType(name: "QUOTED_NAME", pattern: matchQuoted, first: "\"'", hasFirst: true),
  TokenType(name: "WS", pattern: matchBlanks, hidden: true, first: " \t", hasFirst: true),
  TokenType(name: "ML_COMMENT", pattern: matchComment, hidden: true, first: "%", hasFirst: true),
  TokenType(name: "NL", pattern: matchNewline, hidden: true, first: "\r\n", hasFirst: true),
  BARE_NAME,
]

type
  TreeNodeAst* = object
    indent*: int                  ## 0 for undefined (an indentation is never empty)
    name*: string
    classAnnotation*: string      ## "" for undefined
    hasIconAnnotation*: bool      ## `icon()` is an empty annotation, not none
    iconAnnotation*: string
    descAnnotation*: string

  TreeViewAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    nodes*: seq[TreeNodeAst]

func trimBlanksEnd(text: string): string =
  var stop = text.len
  while stop > 0 and isBlank(ord(text[stop - 1])): dec stop
  text[0 ..< stop]

func convertValue*(rule: string, input: string): string =
  ## Mermaid's TreeViewValueConverter, by terminal name, for the terminals whose value is a
  ## string ("" for undefined). INDENTATION's value is its length, read where it is taken.
  case rule
  of "QUOTED_NAME": input[1 ..< input.len - 1]
  of "BARE_NAME": trimBlanksEnd(input)
  of "CLASS_ANNOTATION": strip(input)[3 .. ^1].strip   # the pattern holds only ASCII
  of "ICON_ANNOTATION":
    let trimmed = strip(input)
    trimmed[5 ..< trimmed.len - 1]
  of "DESC_ANNOTATION": jsTrim(jsTrim(input)[2 .. ^1])
  else: ""

proc parseTreeView*(src: string): TreeViewAst =
  let r = newReader(tokenize(src, TREEVIEW_TOKENS, "treeView"), TREEVIEW_TOKENS, "treeView")
  discard r.expect(T_keyword)
  while true:
    if r.kind == T_accDescr: result.accDescr = accDescrValue(r.take())
    elif r.kind == T_accTitle: result.accTitle = accTitleValue(r.take())
    elif r.kind == T_title: result.title = titleValue(r.take())
    else: break
  while r.kind != -1:
    var node = TreeNodeAst()
    if r.kind == T_indentation: node.indent = r.take().len
    if r.kind == T_quotedName:
      node.name = convertValue("QUOTED_NAME", r.take())
    elif r.kind == T_bareName:
      node.name = trimBlanksEnd(r.take())
    else:
      r.fail("a name")
    while true:
      if r.kind == T_classAnnotation: node.classAnnotation = convertValue("CLASS_ANNOTATION", r.take())
      elif r.kind == T_iconAnnotation:
        node.iconAnnotation = convertValue("ICON_ANNOTATION", r.take())
        node.hasIconAnnotation = true
      elif r.kind == T_descAnnotation: node.descAnnotation = convertValue("DESC_ANNOTATION", r.take())
      else: break
    result.nodes.add node
