## port-of: src/diagrams/radar/parser.ts
## port-status: draft
import std/strutils
import ../common/tokens
import ../../js

const
  # const enum T: the index of each token type in RADAR_TOKENS
  T_radarColon = 0
  T_radar = 1
  T_showLegend = 2
  T_graticule = 3
  T_curve = 4
  T_ticks = 5
  T_axis = 6
  T_max = 7
  T_min = 8
  T_colon = 9
  T_comma = 10
  T_open = 11
  T_close = 12
  T_openBrace = 13
  T_closeBrace = 14
  T_graticuleValue = 15
  T_boolean = 16
  T_accDescr = 17
  T_accTitle = 18
  T_title = 19
  T_number = 20
  T_string = 21
  T_id = 22
  T_newline = 23

func digits(src: string, at: int): int =
  var stop = at
  while stop < src.len and src[stop] in {'0'..'9'}: inc stop
  stop

func charCode(src: string, i: int): int = (if i < src.len: ord(src[i]) else: -1)

proc numberScanner(): Scanner =
  ## The NUMBER pattern without its backtracking. As a regular expression it reads to the end of
  ## a run of digits from every position in the run, which is quadratic for a long run of zeros.
  ## /(?:[0-9]+\.[0-9]+(?!\.))|(?:0|[1-9][0-9]*(?!\.))/y. Pele keeps the run in module
  ## variables reset by lexRadar; here they live in the scanner, made once per text.
  var runFrom = 0
  var runEnd = 0
  result = proc (src: string, at: int, previous: int): int =
    if at < runFrom or at >= runEnd:
      runFrom = at
      runEnd = digits(src, at)
    let whole = runEnd
    if whole == at: return -1
    let dot = charCode(src, whole) == 46
    if dot:
      let fraction = digits(src, whole + 1)
      let length = fraction - whole - 1
      if length > 0 and charCode(src, fraction) != 46: return fraction
      if length > 1: return fraction - 1
    if charCode(src, at) == 48: return at + 1
    if not dot: return whole
    if whole - 1 > at: whole - 1 else: -1

func blockEnd(src: string, at: int): int =
  ## RE_BLOCK: /[\t ]*accDescr\s*{/y, where it ends, or -1.
  var i = at
  while i < src.len and src[i] in {'\t', ' '}: inc i
  if not src.continuesWith("accDescr", i): return -1
  i += 8
  while true:
    let n = spaceLenAt(src, i)
    if n == 0: break
    i += n
  if i < src.len and src[i] == '{': i + 1 else: -1

proc accDescrScanner(): Scanner =
  ## In the other grammars an `accDescr {` that never closes ends the lexing. Here `accDescr` is
  ## also a name and `{` a token, so each unclosed one would read to the end of the text again.
  var lastBrace = -2
  result = proc (src: string, at: int, previous: int): int =
    let stop = blockEnd(src, at)
    if stop >= 0:
      if lastBrace == -2: lastBrace = src.rfind('}')
      if stop > lastBrace: return -1
    ACC_DESCR.pattern(src, at)

func nameRestEnd(s: string, at: int): int =
  ## RE_NAME_REST: /[-\w]*\w/y, where it ends, or -1.
  var e = at
  while e < s.len and (isWordChar(s[e]) or s[e] == '-'): inc e
  while e > at and s[e - 1] == '-': dec e
  if e > at: e else: -1

func matchId(s: string, at: int): int =
  ## /[\w]([-\w]*\w)?/y
  if at >= s.len or not isWordChar(s[at]): return -1
  let rest = nameRestEnd(s, at + 1)
  if rest > 0: rest else: at + 1

let ID = TokenType(name: "ID", pattern: matchId)

proc optionValue(words: seq[string], option: int): Scanner =
  ## Gives way to a longer name, except right after its option, as in `graticule polygonaxis`.
  result = proc (src: string, at: int, previous: int): int =
    var stop = -1
    for w in words:
      if src.continuesWith(w, at):
        stop = at + w.len
        break
    if stop < 0: return -1
    if previous == option: return stop
    if nameRestEnd(src, stop) >= 0: -1 else: stop

proc word(text: string): TokenType = TokenType(name: text, literal: text, longer: @[ID])
proc mark(text: string): TokenType = TokenType(name: text, literal: text)

proc withLonger(t: TokenType, longer: seq[TokenType]): TokenType =
  ## `{ ...t, longer }`
  result = TokenType()
  result[] = t[]
  result.longer = longer

proc withScanner(t: TokenType, scanner: proc (): Scanner): TokenType =
  ## `{ ...t, match }`, with a matcher made once per text.
  result = TokenType()
  result[] = t[]
  result.scanner = scanner

let RADAR_TOKENS*: seq[TokenType] = @[
  mark("radar-beta:"),
  keyword("radar-beta").withLonger(@[ID]),
  word("showLegend"),
  word("graticule"),
  word("curve"),
  word("ticks"),
  word("axis"),
  word("max"),
  word("min"),
  mark(":"),
  mark(","),
  mark("["),
  mark("]"),
  mark("{"),
  mark("}"),
  TokenType(name: "GRATICULE", match: optionValue(@["circle", "polygon"], T_graticule)),
  TokenType(name: "BOOLEAN", match: optionValue(@["true", "false"], T_showLegend)),
  ACC_DESCR.withScanner(accDescrScanner),
  ACC_TITLE,
  titleBefore(proc (s: string, i: int): bool {.noSideEffect.} = nameRestEnd(s, i) >= 0),   # [-\w]*\w
  TokenType(name: "NUMBER", scanner: numberScanner, first: "0123456789", hasFirst: true),
  STRING,
  ID,
  NEWLINE,
  WHITESPACE,
  YAML,
  DIRECTIVE,
  SINGLE_LINE_COMMENT,
]

type
  AxisAst* = object
    name*: string
    label*: string
    hasLabel*: bool

  EntryAst* = object
    axis*: string        ## Langium leaves the reference unresolved; Mermaid reads only its text.
    hasAxis*: bool
    value*: float

  CurveAst* = object
    name*: string
    label*: string
    hasLabel*: bool
    entries*: seq[EntryAst]

  OptionAst* = object
    name*: string        ## showLegend, ticks, max, min or graticule
    flag*: bool          ## the value of showLegend
    number*: float       ## the value of ticks, max and min
    text*: string        ## the value of graticule

  RadarAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    axes*: seq[AxisAst]
    curves*: seq[CurveAst]
    options*: seq[OptionAst]

proc lexRadar*(src: string): tokens.Tokens =
  tokenize(src, RADAR_TOKENS, "radar")

proc parseRadar*(src: string): RadarAst =
  let r = newReader(lexRadar(src), RADAR_TOKENS, "radar")
  var ast = RadarAst()

  proc newlines() =
    while r.kind == T_newline: inc r.i

  proc endOfLine() =
    if r.kind == -1: return
    if r.kind != T_newline: r.fail("a line break or the end of input")
    newlines()

  proc label(): (bool, string) =
    if not r.accept(T_open): return (false, "")
    let text = stringValue(r.expect(T_string))
    discard r.expect(T_close)
    (true, text)

  proc entry(detailed: bool): EntryAst =
    if not detailed: return EntryAst(value: jsNumber(r.expect(T_number)))
    let axis = r.expect(T_id)
    discard r.accept(T_colon)
    EntryAst(axis: axis, hasAxis: true, value: jsNumber(r.expect(T_number)))

  proc curve(): CurveAst =
    let name = r.expect(T_id)
    let (has, text) = label()
    var node = CurveAst(name: name)
    if has:
      node.label = text
      node.hasLabel = true
    discard r.expect(T_openBrace)
    newlines()
    if r.kind != T_number and r.kind != T_id: r.fail("a number or an axis name")
    let detailed = r.kind == T_id
    node.entries.add entry(detailed)
    while r.accept(T_comma):
      newlines()
      node.entries.add entry(detailed)
    newlines()
    discard r.expect(T_closeBrace)
    node

  proc axis(): AxisAst =
    var node = AxisAst(name: r.expect(T_id))
    let (has, text) = label()
    if has:
      node.label = text
      node.hasLabel = true
    node

  proc option(): OptionAst =
    let kind = r.kind
    result.name = r.take()
    if kind == T_showLegend: result.flag = r.expect(T_boolean) == "true"
    elif kind == T_graticule: result.text = r.expect(T_graticuleValue)
    else: result.number = jsNumber(r.expect(T_number))

  proc isOption(): bool =
    r.kind == T_showLegend or r.kind == T_ticks or r.kind == T_max or r.kind == T_min or r.kind == T_graticule

  newlines()
  if not r.accept(T_radarColon):
    discard r.expect(T_radar)
    discard r.accept(T_colon)
  newlines()
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
    of T_axis:
      inc r.i
      ast.axes.add axis()
      while r.accept(T_comma): ast.axes.add axis()
    of T_curve:
      inc r.i
      ast.curves.add curve()
      while r.accept(T_comma): ast.curves.add curve()
    else:
      if not isOption(): r.fail("an axis, a curve, an option, a title, or a line break")
      ast.options.add option()
      while r.accept(T_comma):
        if not isOption(): r.fail("an option")
        ast.options.add option()
  ast
