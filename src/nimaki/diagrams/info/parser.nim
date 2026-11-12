## port-of: src/diagrams/info/parser.ts
## port-status: draft
import ../common/tokens

const
  # const enum T: the index of each token type in INFO_TOKENS
  T_showInfo = 0
  T_info = 1
  T_accDescr = 2
  T_accTitle = 3
  T_title = 4
  T_newline = 5

let INFO_TOKENS*: seq[TokenType] = @[
  keyword("showInfo"),
  keyword("info"),
  ACC_DESCR,
  ACC_TITLE,
  TITLE,
  NEWLINE,
  WHITESPACE,
  YAML,
  DIRECTIVE,
  SINGLE_LINE_COMMENT,
]

type InfoAst* = object
  title*, accTitle*, accDescr*: string   ## "" for undefined

proc parseInfo*(src: string): InfoAst =
  let r = newReader(tokenize(src, INFO_TOKENS, "info"), INFO_TOKENS, "info")
  var ast = InfoAst()

  while r.kind == T_newline: inc r.i
  discard r.expect(T_info)
  while r.kind == T_newline: inc r.i
  if r.accept(T_showInfo):
    while r.kind == T_newline: inc r.i
  while r.kind != -1:
    let kind = r.kind
    if kind == T_accDescr: ast.accDescr = accDescrValue(r.take())
    elif kind == T_accTitle: ast.accTitle = accTitleValue(r.take())
    elif kind == T_title: ast.title = titleValue(r.take())
    else: r.fail("a title or the end of input")
    if r.kind == -1: break
    if r.kind != T_newline: r.fail("a line break or the end of input")
    while r.kind == T_newline: inc r.i
  ast
