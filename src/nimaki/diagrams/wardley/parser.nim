## port-of: src/diagrams/wardley/parser.ts
## port-status: draft
import std/[strutils, options]
import ../../js
import ../common/[tokens, acc_descr]

const
  # const enum T: the index of each token type in WARDLEY_TOKENS
  T_lbracket = 0
  T_comma = 1
  T_rbracket = 2
  T_at = 3
  T_slash = 4
  T_lparen = 5
  T_rparen = 6
  T_minus = 7
  T_lbrace = 8
  T_rbrace = 9
  T_number = 10
  T_arrow = 11
  T_linkPort = 12
  T_linkArrow = 13
  T_linkLabel = 14
  T_strategy = 15
  T_wardley = 16
  T_size = 17
  T_evolution = 18
  T_anchor = 19
  T_component = 20
  T_label = 21
  T_inertia = 22
  T_evolve = 23
  T_pipeline = 24
  T_note = 25
  T_annotations = 26
  T_annotation = 27
  T_accelerator = 28
  T_deaccelerator = 29
  T_name = 30
  T_ws = 31
  T_accDescr = 32
  T_accTitle = 33
  T_title = 34
  T_int = 35
  T_string = 36
  T_id = 37
  T_newline = 38

func isDigit(s: string, i: int): bool = i < s.len and s[i] in {'0' .. '9'}
func isWord(s: string, i: int): bool = i < s.len and s[i] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}
func isLetter(s: string, i: int): bool = i < s.len and s[i] in {'A' .. 'Z', 'a' .. 'z'}

func digits(src: string, start: int): int =
  result = start
  while isDigit(src, result): inc result

proc numberScanner(): Scanner =
  ## Answers as WARDLEY_NUMBER's pattern does. The pattern reads a whole run of digits before it
  ## finds there is no fraction, and would do so again from every digit of a long run.
  var start = 0
  var stop = 0
  result = proc (src: string, p: int, previous: int): int =
    if p < start or p >= stop:
      start = p
      stop = digits(src, p)
    if stop == p or stop >= src.len or src[stop] != '.': return -1
    let after = digits(src, stop + 1)
    if after > stop + 1: after else: -1

func matchArrow(s: string, p: int): int =
  ## /->/y
  if s.continuesWith("->", p): p + 2 else: -1

func quoted(s: string, p: int): int =
  ## \+'[^']*' from p: where it ends, or -1
  if not s.continuesWith("+'", p): return -1
  let close = s.find('\'', p + 2)
  if close == -1: -1 else: close + 1

func matchLinkArrow(s: string, p: int): int =
  ## /-->|-\.->|>|\+'[^']*'<>|\+'[^']*'<|\+'[^']*'>/y
  if s.continuesWith("-->", p): return p + 3
  if s.continuesWith("-.->", p): return p + 4
  if s.continuesWith(">", p): return p + 1
  let q = quoted(s, p)
  if q == -1: return -1
  if s.continuesWith("<>", q): return q + 2
  if s.continuesWith("<", q) or s.continuesWith(">", q): return q + 1
  -1

func matchLinkPort(s: string, p: int): int =
  ## /\+<>|\+>|\+</y
  if s.continuesWith("+<>", p): p + 3
  elif s.continuesWith("+>", p) or s.continuesWith("+<", p): p + 2
  else: -1

func matchLinkLabel(s: string, p: int): int =
  ## /;[^\n\r]+/y
  if p >= s.len or s[p] != ';': return -1
  var i = p + 1
  while i < s.len and s[i] notin {'\n', '\r'}: inc i
  if i > p + 1: i else: -1

func matchStrategy(s: string, p: int): int =
  ## /build|buy|outsource|market/y
  for w in ["build", "buy", "outsource", "market"]:
    if s.continuesWith(w, p): return p + w.len
  -1

proc word(name, text: string): TokenType =
  ## A sticky pattern of the text alone: it does not need a word boundary after it.
  let m = proc (s: string, p: int): int {.noSideEffect.} =
    if s.continuesWith(text, p): p + text.len else: -1
  TokenType(name: name, matcher: m, first: text[0 .. 0], hasFirst: true)

func namePart(s: string, i: int): int =
  ## (?:[A-Za-z0-9_()&]|-(?!>))* from i
  result = i
  while result < s.len:
    let c = s[result]
    if c in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '(', ')', '&'}: inc result
    elif c == '-' and not s.continuesWith("->", result): inc result
    else: break

func matchNameWithSpaces(s: string, p: int): int =
  ## /(?!title\s|accTitle|accDescr)[A-Za-z](?:[A-Za-z0-9_()&]|-(?!>))*(?:[ \t]+[A-Za-z(](?:[A-Za-z0-9_()&]|-(?!>))*)*/y
  if s.continuesWith("title", p) and spaceLenAt(s, p + 5) > 0: return -1
  if s.continuesWith("accTitle", p) or s.continuesWith("accDescr", p): return -1
  if not isLetter(s, p): return -1
  result = namePart(s, p + 1)
  while true:
    var i = result
    while i < s.len and s[i] in {' ', '\t'}: inc i
    if i == result or i >= s.len or s[i] notin {'A' .. 'Z', 'a' .. 'z', '('}: break
    result = namePart(s, i + 1)

func matchWs(s: string, p: int): int =
  ## /[ \t]+/y
  var i = p
  while i < s.len and s[i] in {' ', '\t'}: inc i
  if i > p: i else: -1

func matchInt(s: string, p: int): int =
  ## /0|[1-9][0-9]*(?!\.)/y; the run of digits gives back one digit at a time until no `.` follows.
  if p >= s.len: return -1
  if s[p] == '0': return p + 1
  if s[p] notin {'1' .. '9'}: return -1
  var stop = digits(s, p + 1)
  while stop > p and stop < s.len and s[stop] == '.': dec stop
  if stop > p: stop else: -1

func matchId(s: string, p: int): int =
  ## /[\w]([-\w]*\w)?/y
  if not isWord(s, p): return -1
  var i = p + 1
  var last = p + 1
  while i < s.len and (isWord(s, i) or s[i] == '-'):
    inc i
    if isWord(s, i - 1): last = i
  last

let ARROW = TokenType(name: "ARROW", matcher: matchArrow, first: "-", hasFirst: true)
let LINK_ARROW = TokenType(name: "LINK_ARROW", matcher: matchLinkArrow, first: "->+", hasFirst: true)

let WARDLEY_TOKENS*: seq[TokenType] = @[
  TokenType(name: "[", literal: "["),
  TokenType(name: ",", literal: ","),
  TokenType(name: "]", literal: "]"),
  TokenType(name: "@", literal: "@"),
  TokenType(name: "/", literal: "/"),
  TokenType(name: "(", literal: "("),
  TokenType(name: ")", literal: ")"),
  TokenType(name: "-", literal: "-", longer: @[ARROW, LINK_ARROW, YAML]),
  TokenType(name: "{", literal: "{"),
  TokenType(name: "}", literal: "}"),
  TokenType(name: "WARDLEY_NUMBER", first: "0123456789", hasFirst: true, scanner: numberScanner),
  ARROW,
  TokenType(name: "LINK_PORT", matcher: matchLinkPort, first: "+", hasFirst: true),
  LINK_ARROW,
  TokenType(name: "LINK_LABEL", matcher: matchLinkLabel, first: ";", hasFirst: true),
  TokenType(name: "STRATEGY", matcher: matchStrategy, first: "bom", hasFirst: true),
  word("KW_WARDLEY", "wardley-beta"),
  word("KW_SIZE", "size"),
  word("KW_EVOLUTION", "evolution"),
  word("KW_ANCHOR", "anchor"),
  word("KW_COMPONENT", "component"),
  word("KW_LABEL", "label"),
  word("KW_INERTIA", "inertia"),
  word("KW_EVOLVE", "evolve"),
  word("KW_PIPELINE", "pipeline"),
  word("KW_NOTE", "note"),
  word("KW_ANNOTATIONS", "annotations"),
  word("KW_ANNOTATION", "annotation"),
  word("KW_ACCELERATOR", "accelerator"),
  word("KW_DEACCELERATOR", "deaccelerator"),
  TokenType(name: "NAME_WITH_SPACES", matcher: matchNameWithSpaces,
            first: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", hasFirst: true),
  TokenType(name: "WS", matcher: matchWs, hidden: true, first: "\t ", hasFirst: true),
  accDescr(),
  ACC_TITLE,
  TITLE,
  TokenType(name: "INT", matcher: matchInt, first: "0123456789", hasFirst: true),
  STRING,
  TokenType(name: "ID", matcher: matchId, first: "_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
            hasFirst: true),
  NEWLINE,
  WHITESPACE,
  YAML,
  DIRECTIVE,
  SINGLE_LINE_COMMENT,
]

type
  LabelAst* = object
    negX*: bool
    offsetX*: float
    negY*: bool
    offsetY*: float

  StageAst* = object
    name*: string
    boundary*: Option[float]
    secondName*: Option[string]

  ComponentAst* = object
    name*: string
    visibility*, evolution*: float
    label*: Option[LabelAst]
    decorator*: string            ## the strategy; "" for no decorator
    inertia*: bool

  PipelineComponentAst* = object
    name*: string
    evolution*: float
    label*: Option[LabelAst]

  LinkAst* = object
    start*: string                ## Pele's `from`
    fromPort*, arrow*, toPort*: string  ## "" for undefined
    to*: string
    linkLabel*: Option[string]

  AnchorAst* = object
    name*: string
    visibility*, evolution*: float

  EvolveAst* = object
    component*: string
    target*: float

  PipelineAst* = object
    parent*: string
    components*: seq[PipelineComponentAst]

  NoteAst* = object
    text*: string
    visibility*, evolution*: float

  AnnotationAst* = object
    number*: float
    x*, y*: float
    text*: string

  PlacedAst* = object
    name*: string
    x*, y*: float

  WardleyAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    size*: Option[tuple[width, height: float]]
    evolution*: Option[seq[StageAst]]
    anchors*: seq[AnchorAst]
    components*: seq[ComponentAst]
    links*: seq[LinkAst]
    evolves*: seq[EvolveAst]
    pipelines*: seq[PipelineAst]
    notes*: seq[NoteAst]
    annotations*: seq[tuple[x, y: float]]
    annotation*: seq[AnnotationAst]
    accelerators*: seq[PlacedAst]
    deaccelerators*: seq[PlacedAst]

proc parseWardley*(src: string): WardleyAst =
  let r = newReader(tokenize(src, WARDLEY_TOKENS, "wardley"), WARDLEY_TOKENS, "wardley")
  var ast: WardleyAst

  proc at(kind: int): bool = r.kinds[r.i] == kind
  proc isName(): bool = at(T_string) or at(T_id) or at(T_name)
  proc name(): string =
    if at(T_string): return stringValue(r.take())
    if at(T_id) or at(T_name): return r.take()
    r.fail("a name")
  proc number(): float = jsToNumber(r.expect(T_number))
  proc integer(): float = jsToNumber(r.expect(T_int))
    ## parseInt of a run of digits reads the same number as Number.
  proc coordinate(): float = (if at(T_number): jsToNumber(r.take()) else: jsToNumber(r.expect(T_int)))
  proc endOfLine() =
    if at(-1): return
    if not at(T_newline): r.fail("a line break or the end of input")
    while at(T_newline): inc r.i
  proc pair(read: proc (): float): (float, float) =
    discard r.expect(T_lbracket)
    let first = read()
    discard r.expect(T_comma)
    let second = read()
    discard r.expect(T_rbracket)
    (first, second)
  proc label(): LabelAst =
    discard r.expect(T_label)
    discard r.expect(T_lbracket)
    result.negX = r.accept(T_minus)
    result.offsetX = integer()
    discard r.expect(T_comma)
    result.negY = r.accept(T_minus)
    result.offsetY = integer()
    discard r.expect(T_rbracket)
  proc stage(): StageAst =
    result.name = name()
    if r.accept(T_at): result.boundary = some(number())
    if r.accept(T_slash): result.secondName = some(name())

  while at(T_newline): inc r.i
  discard r.expect(T_wardley)
  while not at(-1):
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
    of T_size:
      inc r.i
      let (width, height) = pair(integer)
      endOfLine()
      ast.size = some((width, height))
    of T_evolution:
      inc r.i
      var stages = @[stage()]
      discard r.expect(T_arrow)
      stages.add stage()
      while r.accept(T_arrow): stages.add stage()
      endOfLine()
      ast.evolution = some(stages)
    of T_anchor:
      inc r.i
      let anchor = name()
      let (visibility, evolution) = pair(number)
      endOfLine()
      ast.anchors.add AnchorAst(name: anchor, visibility: visibility, evolution: evolution)
    of T_component:
      inc r.i
      var component = ComponentAst(name: name())
      (component.visibility, component.evolution) = pair(number)
      if at(T_label): component.label = some(label())
      if at(T_lparen) and r.kinds[r.i + 1] == T_strategy:
        inc r.i
        component.decorator = r.take()
        discard r.expect(T_rparen)
      if r.accept(T_inertia):
        component.inertia = true
      elif r.accept(T_lparen):
        discard r.expect(T_inertia)
        discard r.expect(T_rparen)
        component.inertia = true
      endOfLine()
      ast.components.add component
    of T_evolve:
      inc r.i
      let component = name()
      let target = number()
      endOfLine()
      ast.evolves.add EvolveAst(component: component, target: target)
    of T_pipeline:
      inc r.i
      let parent = name()
      discard r.expect(T_lbrace)
      discard r.expect(T_newline)
      while at(T_newline): inc r.i
      var components: seq[PipelineComponentAst]
      while true:
        discard r.expect(T_component)
        var component = PipelineComponentAst(name: name())
        discard r.expect(T_lbracket)
        component.evolution = number()
        discard r.expect(T_rbracket)
        if at(T_label): component.label = some(label())
        endOfLine()
        components.add component
        if not at(T_component): break
      discard r.expect(T_rbrace)
      endOfLine()
      ast.pipelines.add PipelineAst(parent: parent, components: components)
    of T_note:
      inc r.i
      let text = stringValue(r.expect(T_string))
      let (visibility, evolution) = pair(number)
      endOfLine()
      ast.notes.add NoteAst(text: text, visibility: visibility, evolution: evolution)
    of T_annotations:
      inc r.i
      let (x, y) = pair(coordinate)
      endOfLine()
      ast.annotations.add (x, y)
    of T_annotation:
      inc r.i
      let n = integer()
      discard r.expect(T_comma)
      let (x, y) = pair(coordinate)
      let text = stringValue(r.expect(T_string))
      endOfLine()
      ast.annotation.add AnnotationAst(number: n, x: x, y: y, text: text)
    of T_accelerator, T_deaccelerator:
      let slow = r.kind == T_deaccelerator
      inc r.i
      let force = name()
      let (x, y) = pair(number)
      endOfLine()
      if slow: ast.deaccelerators.add PlacedAst(name: force, x: x, y: y)
      else: ast.accelerators.add PlacedAst(name: force, x: x, y: y)
    else:
      if not isName(): r.fail("a statement")
      var link = LinkAst(start: name())
      if at(T_linkPort): link.fromPort = r.take()
      if at(T_linkArrow) or at(T_arrow): link.arrow = r.take()
      link.to = name()
      if at(T_linkPort): link.toPort = r.take()
      if at(T_linkLabel): link.linkLabel = some(jsTrim(r.take()[1 .. ^1]))
      endOfLine()
      ast.links.add link
  ast
