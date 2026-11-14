## port-of: src/diagrams/packet/parser.ts
## port-status: draft
import std/options
import ../common/tokens
import ../../js

const
  # const enum T: the index of each token type in PACKET_TOKENS
  T_packetBeta = 0
  T_packet = 1
  T_dash = 2
  T_plus = 3
  T_colon = 4
  T_accDescr = 5
  T_accTitle = 6
  T_title = 7
  T_int = 8
  T_string = 9
  T_newline = 10

func matchInt(s: string, p: int): int =
  ## /0|[1-9][0-9]*(?!\.)/y: a 0 alone, or a run of digits not followed by a dot (the run
  ## gives back its last digit when a dot follows).
  if p >= s.len: return -1
  if s[p] == '0': return p + 1
  if s[p] notin {'1'..'9'}: return -1
  var e = p + 1
  while e < s.len and s[e] in {'0'..'9'}: inc e
  if e < s.len and s[e] == '.':
    if e - 1 > p: e - 1 else: -1
  else: e

let PACKET_TOKENS*: seq[TokenType] = @[
  TokenType(name: "packet-beta", literal: "packet-beta"),
  keyword("packet"),
  # A front matter block also starts with dashes, so Langium lets it win over a dash.
  TokenType(name: "-", literal: "-", longer: @[YAML]),
  TokenType(name: "+", literal: "+"),
  TokenType(name: ":", literal: ":"),
  ACC_DESCR,
  ACC_TITLE,
  TITLE,
  TokenType(name: "INT", matcher: matchInt, first: "0123456789", hasFirst: true),
  STRING,
  NEWLINE,
  WHITESPACE,
  YAML,
  DIRECTIVE,
  SINGLE_LINE_COMMENT,
]

type
  PacketBlockAst* = object
    start*, stop*, bits*: Option[float]
    label*: string

  PacketAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    blocks*: seq[PacketBlockAst]

proc parsePacket*(src: string): PacketAst =
  let r = newReader(tokenize(src, PACKET_TOKENS, "packet"), PACKET_TOKENS, "packet")
  var ast = PacketAst()

  proc endOfLine() =
    if r.kind == -1: return
    if r.kind != T_newline: r.fail("a line break or the end of input")
    while r.kind == T_newline: inc r.i

  while r.kind == T_newline: inc r.i
  if not r.accept(T_packetBeta): discard r.expect(T_packet)
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
    of T_int, T_plus:
      var blk = PacketBlockAst(label: "")
      if r.accept(T_plus):
        blk.bits = some(jsNumber(r.expect(T_int)))
      else:
        blk.start = some(jsNumber(r.take()))
        if r.accept(T_dash): blk.stop = some(jsNumber(r.expect(T_int)))
      discard r.expect(T_colon)
      blk.label = stringValue(r.expect(T_string))
      ast.blocks.add blk
      endOfLine()
    else:
      r.fail("a field, a title, or a line break")
  ast
