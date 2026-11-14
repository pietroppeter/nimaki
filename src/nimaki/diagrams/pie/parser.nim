## port-of: src/diagrams/pie/parser.ts
## port-status: conformant
import ../common/tokens
import ../../js
import ../../jsregex

const
  # const enum T: the index of each token type in PIE_TOKENS
  T_showData = 0
  T_pie = 1
  T_colon = 2
  T_number = 3
  T_accDescr = 4
  T_accTitle = 5
  T_title = 6
  T_string = 7
  T_newline = 8

func charCode(src: string, i: int): int = (if i < src.len: ord(src[i]) else: -1)

func digits(src: string, start: int): int =
  var i = start
  var c = charCode(src, i)
  while c >= 48 and c <= 57:
    inc i
    c = charCode(src, i)
  i

proc numberScanner(): Scanner =
  ## Answers as NUMBER_PIE's pattern does. The pattern reads a whole run of digits before it
  ## finds there is no fraction, and would do so again from every digit of a long run of zeros.
  var start = 0
  var stop = 0
  var fraction = -1
  result = proc (src: string, p: int, previous: int): int =
    let at = if charCode(src, p) == 45: p + 1 else: p
    if at < start or at >= stop:
      start = at
      stop = digits(src, at)
      fraction = -1
      if stop > at and charCode(src, stop) == 46:
        let after = digits(src, stop + 1)
        let length = after - stop - 1
        if length > 0 and charCode(src, after) != 46: fraction = after
        elif length > 1: fraction = after - 1
    if stop == at: return -1
    if fraction >= 0: return fraction
    if charCode(src, at) == 48: return (if charCode(src, at + 1) == 46: -1 else: at + 1)
    if charCode(src, stop) != 46: return stop
    if stop - 1 > at: stop - 1 else: -1

let PIE_TOKENS*: seq[TokenType] = @[
  keyword("showData"),
  keyword("pie"),
  TokenType(name: ":", literal: ":"),
  TokenType(name: "NUMBER_PIE", pattern: jsre"/(?:-?[0-9]+\.[0-9]+(?!\.))|(?:-?(0|[1-9][0-9]*)(?!\.))/y",
            scanner: numberScanner, first: "-0123456789", hasFirst: true),
    # /(?:-?[0-9]+\.[0-9]+(?!\.))|(?:-?(0|[1-9][0-9]*)(?!\.))/y
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
  PieSection* = object
    label*: string
    value*: float

  PieAst* = object
    showData*: bool
    title*, accTitle*, accDescr*: string   ## "" for undefined
    sections*: seq[PieSection]

proc parsePie*(src: string): PieAst =
  let r = newReader(tokenize(src, PIE_TOKENS, "pie"), PIE_TOKENS, "pie")
  var ast = PieAst(showData: false)

  proc endOfLine() =
    if r.kind == -1: return
    if r.kind != T_newline: r.fail("a line break or the end of input")
    while r.kind == T_newline: inc r.i

  while r.kind == T_newline: inc r.i
  discard r.expect(T_pie)
  ast.showData = r.accept(T_showData)
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
    of T_string:
      let label = stringValue(r.take())
      discard r.expect(T_colon)
      let value = jsNumber(r.expect(T_number))
      ast.sections.add PieSection(label: label, value: value)
      endOfLine()
    else:
      r.fail("a section, a title, or a line break")
  ast
