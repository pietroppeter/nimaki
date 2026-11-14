## port-of: src/diagrams/architecture/parser.ts
## port-status: conformant
import std/[strutils, options]
import ../../js
import ../common/tokens

const
  # const enum T: the index of each token type in ARCHITECTURE_TOKENS
  T_header = 0
  T_junction = 1
  T_service = 2
  T_column = 3
  T_group = 4
  T_align = 5
  T_row = 6
  T_dashes = 7
  T_in = 8
  T_colon = 9
  T_dash = 10
  T_direction = 11
  T_arrowGroup = 12
  T_into = 13
  T_accDescr = 14
  T_accTitle = 15
  T_title = 16
  T_string = 17
  T_id = 18
  T_newline = 19
  T_icon = 24
  T_label = 25

func isWord(s: string, i: int): bool = i < s.len and s[i] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}

func matchId(s: string, p: int): int =
  ## /[\w]([-\w]*\w)?/y
  if not isWord(s, p): return -1
  var i = p + 1
  var last = p + 1
  while i < s.len and (isWord(s, i) or s[i] == '-'):
    inc i
    if isWord(s, i - 1): last = i
  last

func titleRest(s: string, i: int): bool {.noSideEffect.} =
  ## [-\w]*\w at i
  var j = i
  while j < s.len and (isWord(s, j) or s[j] == '-'):
    if isWord(s, j): return true
    inc j
  false

func matchDirection(s: string, p: int): int =
  ## /L|R|T|B/y
  if p < s.len and s[p] in {'L', 'R', 'T', 'B'}: p + 1 else: -1

func matchArrowGroup(s: string, p: int): int =
  ## /\{group\}/y
  if s.continuesWith("{group}", p): p + 7 else: -1

func matchInto(s: string, p: int): int =
  ## /<|>/y
  if p < s.len and s[p] in {'<', '>'}: p + 1 else: -1

func matchIcon(s: string, p: int): int =
  ## /\([\w-:]+\)/y
  if p >= s.len or s[p] != '(': return -1
  var i = p + 1
  while isWord(s, i) or (i < s.len and s[i] in {'-', ':'}): inc i
  if i > p + 1 and i < s.len and s[i] == ')': i + 1 else: -1

func lineTerminatorLen(s: string, i: int): int =
  ## The bytes of a line terminator (\n, \r, U+2028, U+2029) at i, or 0.
  if i >= s.len: return 0
  if s[i] in {'\n', '\r'}: return 1
  if s.continuesWith(" ", i) or s.continuesWith(" ", i): return 3
  0

func quotedEnd(s: string, p: int, q: char): int =
  ## q([^q\\]|\\.)*q from p: where it ends, or -1.
  if p >= s.len or s[p] != q: return -1
  var i = p + 1
  while i < s.len:
    let c = s[i]
    if c == q: return i + 1
    if c == '\\':
      if i + 1 >= s.len or lineTerminatorLen(s, i + 1) > 0: return -1
      i += 1 + codePointAt(s, i + 1).size
    else:
      i += codePointAt(s, i).size
  -1

func matchLabel(s: string, p: int): int =
  ## /\[(?:"([^"\\]|\\.)*"|'([^'\\]|\\.)*'|[^\[\]\r\n]+)\]/y
  if p >= s.len or s[p] != '[': return -1
  for q in ['"', '\'']:
    let stop = quotedEnd(s, p + 1, q)
    if stop >= 0 and stop < s.len and s[stop] == ']': return stop + 1
  var i = p + 1
  while i < s.len and s[i] notin {'[', ']', '\r', '\n'}: inc i
  if i > p + 1 and i < s.len and s[i] == ']': i + 1 else: -1

let ID = TokenType(name: "ID", pattern: matchId)

proc word(text: string): TokenType =
  TokenType(name: text, literal: text, longer: @[ID])

let ARCHITECTURE_TOKENS*: seq[TokenType] = @[
  ## The direction letters come before identifiers and have no longer alternative, so Mermaid
  ## reads an id that starts with L, R, T or B as a direction followed by the rest.
  word("architecture-beta"),
  word("junction"),
  word("service"),
  word("column"),
  word("group"),
  word("align"),
  word("row"),
  TokenType(name: "--", literal: "--", longer: @[YAML]),
  word("in"),
  TokenType(name: ":", literal: ":"),
  TokenType(name: "-", literal: "-", longer: @[YAML]),
  TokenType(name: "ARROW_DIRECTION", pattern: matchDirection),
  TokenType(name: "ARROW_GROUP", pattern: matchArrowGroup),
  TokenType(name: "ARROW_INTO", pattern: matchInto),
  ACC_DESCR,
  ACC_TITLE,
  titleBefore(titleRest),
  STRING,
  ID,
  NEWLINE,
  WHITESPACE,
  YAML,
  DIRECTIVE,
  SINGLE_LINE_COMMENT,
  TokenType(name: "ARCH_ICON", pattern: matchIcon),
  TokenType(name: "ARCH_TITLE", pattern: matchLabel),
]

type
  GroupAst* = object
    id*: string
    icon*, title*, parent*: Option[string]   ## `parent` is Pele's `in`

  ServiceAst* = object
    id*: string
    icon*, iconText*, title*, parent*: Option[string]

  JunctionAst* = object
    id*: string
    parent*: Option[string]

  EdgeAst* = object
    lhsId*: string
    lhsGroup*: bool
    lhsDir*: char
    lhsInto*: bool
    title*: Option[string]
    rhsInto*: bool
    rhsDir*: char
    rhsId*: string
    rhsGroup*: bool

  AlignmentAst* = object
    direction*: string            ## "row" or "column"
    members*: seq[string]

  ArchitectureAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    groups*: seq[GroupAst]
    services*: seq[ServiceAst]
    junctions*: seq[JunctionAst]
    edges*: seq[EdgeAst]
    alignments*: seq[AlignmentAst]

func unescapeQuotes(s: string): string =
  ## .replace(/\\"/g, '"').replace(/\\'/g, "'")
  s.replace("\\\"", "\"").replace("\\'", "'")

func labelValue(text: string): string =
  ## Mermaid's ArchitectureValueConverter for ARCH_TITLE.
  var result0 = jsTrim(text[1 .. ^2])
  if result0.len >= 1 and ((result0.startsWith("\"") and result0.endsWith("\"")) or
                           (result0.startsWith("'") and result0.endsWith("'"))):
    result0 = unescapeQuotes(if result0.len >= 2: result0[1 .. ^2] else: "")
  jsTrim(result0)

proc parseArchitecture*(src: string): ArchitectureAst =
  let r = newReader(tokenize(src, ARCHITECTURE_TOKENS, "architecture"), ARCHITECTURE_TOKENS, "architecture")
  var ast: ArchitectureAst

  proc isK(kind: int): bool = r.kinds[r.i] == kind
  proc endOfLine() =
    if r.kind == -1: return
    if r.kind != T_newline: r.fail("a line break or the end of input")
    while r.kind == T_newline: inc r.i

  while r.kind == T_newline: inc r.i
  discard r.expect(T_header)
  while r.kind != -1:
    case r.kind
    of T_newline:
      inc r.i
      continue
    of T_accDescr:
      ast.accDescr = accDescrValue(r.take())
    of T_accTitle:
      ast.accTitle = accTitleValue(r.take())
    of T_title:
      ast.title = titleValue(r.take())
    of T_group:
      inc r.i
      var group = GroupAst(id: r.expect(T_id))
      if isK(T_icon): group.icon = some(r.take()[1 .. ^2])
      if isK(T_label): group.title = some(labelValue(r.take()))
      if r.accept(T_in): group.parent = some(r.expect(T_id))
      ast.groups.add group
    of T_service:
      inc r.i
      var service = ServiceAst(id: r.expect(T_id))
      if isK(T_string): service.iconText = some(stringValue(r.take()))
      elif isK(T_icon): service.icon = some(r.take()[1 .. ^2])
      if isK(T_label): service.title = some(labelValue(r.take()))
      if r.accept(T_in): service.parent = some(r.expect(T_id))
      ast.services.add service
    of T_junction:
      inc r.i
      var junction = JunctionAst(id: r.expect(T_id))
      if r.accept(T_in): junction.parent = some(r.expect(T_id))
      ast.junctions.add junction
    of T_id:
      var edge = EdgeAst(lhsId: r.take())
      edge.lhsGroup = r.accept(T_arrowGroup)
      discard r.expect(T_colon)
      edge.lhsDir = r.expect(T_direction)[0]
      edge.lhsInto = r.accept(T_into)
      if not r.accept(T_dashes):
        if not isK(T_dash): r.fail("'--' or '-'")
        inc r.i
        edge.title = some(labelValue(r.expect(T_label)))
        discard r.expect(T_dash)
      edge.rhsInto = r.accept(T_into)
      edge.rhsDir = r.expect(T_direction)[0]
      discard r.expect(T_colon)
      edge.rhsId = r.expect(T_id)
      edge.rhsGroup = r.accept(T_arrowGroup)
      ast.edges.add edge
    of T_align:
      inc r.i
      if not isK(T_row) and not isK(T_column): r.fail("'row' or 'column'")
      let direction = r.take()
      var members = @[r.expect(T_id), r.expect(T_id)]
      while isK(T_id): members.add r.take()
      ast.alignments.add AlignmentAst(direction: direction, members: members)
    else:
      r.fail("a group, a service, a junction, an edge, an alignment, a title, or a line break")
    endOfLine()
  ast
