## port-of: src/diagrams/cynefin/parser.ts
## port-status: draft
import ../common/tokens
import ../../jsregex

const
  # const enum T: the index of each token type in CYNEFIN_TOKENS
  T_keywordColon = 0
  T_keyword = 1
  T_arrow = 2
  T_colon = 3
  T_domain = 4
  T_accDescr = 5
  T_accTitle = 6
  T_title = 7
  T_string = 8
  T_newline = 9

let CYNEFIN_TOKENS*: seq[TokenType] = @[
  TokenType(name: "cynefin-beta:", literal: "cynefin-beta:"),
  keyword("cynefin-beta"),
  TokenType(name: "-->", literal: "-->"),
  TokenType(name: ":", literal: ":"),
  TokenType(name: "DOMAIN_NAME", pattern: jsre"/complex|complicated|clear|chaotic|confusion/y", first: "c", hasFirst: true),
  ACC_DESCR,
  ACC_TITLE,
  TITLE,
  STRING,
  NEWLINE,
  WHITESPACE,
  YAML,
  DIRECTIVE,
  SINGLE_LINE_COMMENT,
]

type
  DomainBlockAst* = object
    domain*: string
    items*: seq[string]          ## the labels of its items

  TransitionAst* = object
    start*: string               ## Pele's `from`
    to*: string
    label*: string               ## "" for undefined

  CynefinAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    domains*: seq[DomainBlockAst]
    transitions*: seq[TransitionAst]

proc parseCynefin*(src: string): CynefinAst =
  let r = newReader(tokenize(src, CYNEFIN_TOKENS, "cynefin"), CYNEFIN_TOKENS, "cynefin")
  var ast: CynefinAst

  proc skipLines() =
    while r.kinds[r.i] == T_newline: inc r.i
  proc endOfLine() =
    if r.kind == -1: return
    if r.kind != T_newline: r.fail("a line break or the end of input")
    skipLines()

  skipLines()
  if r.kind != T_keyword and r.kind != T_keywordColon: r.fail("'cynefin-beta'")
  inc r.i
  while r.kind != -1:
    case r.kind
    of T_newline:
      inc r.i
    of T_accDescr:
      ast.accDescr = accDescrValue(r.take())
      endOfLine()
    of T_accTitle:
      ast.accTitle = accTitleValue(r.take())
      endOfLine()
    of T_title:
      ast.title = titleValue(r.take())
      endOfLine()
    of T_domain:
      let name = r.take()
      if r.accept(T_arrow):
        var transition = TransitionAst(start: name, to: r.expect(T_domain))
        if r.accept(T_colon): transition.label = stringValue(r.expect(T_string))
        endOfLine()
        ast.transitions.add transition
        continue
      var blk = DomainBlockAst(domain: name)
      skipLines()
      while r.kinds[r.i] == T_string:
        blk.items.add stringValue(r.take())
        skipLines()
      ast.domains.add blk
    else:
      r.fail("a domain, a transition, a title, or a line break")
  ast
