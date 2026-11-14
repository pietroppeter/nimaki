## port-of: src/diagrams/eventmodeling/parser.ts
## port-status: conformant
import std/[sets, strutils]
import ../common/[tokens, acc_descr]
import ../../js

func matchId(s: string, at: int): int =
  ## /[_a-zA-Z][\w_]*/y
  if at >= s.len or s[at] notin {'_', 'a'..'z', 'A'..'Z'}: return -1
  result = at + 1
  while result < s.len and isWordChar(s[result]): inc result

let EM_ID = TokenType(name: "EM_ID", pattern: matchId)

proc word(text: string): TokenType =
  ## Langium gives every keyword that is also an identifier the identifier as a longer alternative.
  TokenType(name: text, literal: text, longer: @[EM_ID])
proc sign(text: string): TokenType = TokenType(name: text, literal: text)

proc renamed(t: TokenType, name: string): TokenType =
  ## `{ ...t, name }`
  result = TokenType()
  result[] = t[]
  result.name = name

proc withLonger(t: TokenType, longer: seq[TokenType]): TokenType =
  result = TokenType()
  result[] = t[]
  result.longer = longer

const WORDS = [
  "resetframe", "readmodel", "processor", "timeframe", "command", "entity", "event", "jsobj", "figma", "given", "json", "salt", "html",
  "text", "data", "note", "when", "then", "rmo", "cmd", "evt", "pcr", "uri",
]

func matchFrameId(s: string, at: int): int =
  ## /\d{1,3}/y
  var i = at
  while i < s.len and i < at + 3 and s[i] in {'0'..'9'}: inc i
  if i > at: i else: -1

func lineStop(s: string, at: int): int =
  ## Where `.*` from `at` stops: before \n, \r, U+2028 or U+2029, or at the end.
  var i = at
  while i < s.len:
    let c = s[i]
    if c == '\n' or c == '\r': break
    if c == '\xE2' and i + 2 < s.len and s[i + 1] == '\x80' and s[i + 2] in {'\xA8', '\xA9'}: break
    inc i
  i

func matchInline(s: string, at: int): int =
  ## /\{(.*)\}|"(.*)"|'(.*)'/y: from the opener to the last closer on its line.
  if at >= s.len: return -1
  let closer = case s[at]
    of '{': '}'
    of '"': '"'
    of '\'': '\''
    else: return -1
  let stop = lineStop(s, at + 1)
  var i = stop - 1
  while i > at and s[i] != closer: dec i
  if i > at: i + 1 else: -1

func matchBlock(s: string, at: int): int =
  ## /\{[\t ]*\r?\n(?:[\S\s]*?\r?\n)?\}(?:\r?\n|(?!\S))/y: the first `}` that starts a line, after a
  ## line break that ends the opening line.
  if at >= s.len or s[at] != '{': return -1
  var i = at + 1
  while i < s.len and s[i] in {'\t', ' '}: inc i
  if i < s.len and s[i] == '\r': inc i
  if i >= s.len or s[i] != '\n': return -1
  var p = i + 1
  while p < s.len:
    if s[p] == '}' and s[p - 1] == '\n':
      let q = p + 1
      if q < s.len and s[q] == '\n': return q + 1
      if q + 1 < s.len and s[q] == '\r' and s[q + 1] == '\n': return q + 2
      if q >= s.len or isJsSpaceAt(s, q): return q
    inc p
  -1

func matchWs(s: string, at: int): int =
  ## /\s+/y
  var i = at
  while true:
    let n = spaceLenAt(s, i)
    if n == 0: break
    i += n
  if i > at: i else: -1

func matchMlComment(s: string, at: int): int =
  ## /\/\*[\s\S]*?\*\//y
  if not s.continuesWith("/*", at): return -1
  let close = s.find("*/", at + 2)
  if close == -1: -1 else: close + 2

func matchSlComment(s: string, at: int): int =
  ## /\/\/[^\n\r]*/y
  if not s.continuesWith("//", at): return -1
  result = at + 2
  while result < s.len and s[result] notin {'\n', '\r'}: inc result

proc buildTokens(): seq[TokenType] =
  result.add keyword("eventmodeling").withLonger(@[EM_ID])
  for w in WORDS: result.add word(w)
  result.add sign("->>")
  result.add word("gwt")
  result.add word("ui")
  result.add word("md")
  result.add word("tf")
  result.add sign("[[")
  result.add sign("]]")
  result.add word("rf")
  result.add sign("`")
  result.add sign(".")
  result.add EM_ID
  result.add TokenType(name: "EM_FID", pattern: matchFrameId)
  result.add TokenType(name: "EM_DATA_INLINE", pattern: matchInline)
  result.add TokenType(name: "EM_DATA_BLOCK", pattern: matchBlock)
  result.add accDescr("EM_ACC_DESCR")
  result.add ACC_TITLE.renamed("EM_ACC_TITLE")
  result.add titleBefore(proc (s: string, i: int): bool {.noSideEffect.} = i < s.len and isWordChar(s[i])).renamed("EM_TITLE")
  result.add TokenType(name: "EM_WS", pattern: matchWs, hidden: true)
  result.add YAML.renamed("EM_YAML")
  result.add DIRECTIVE.renamed("EM_DIRECTIVE")
  result.add SINGLE_LINE_COMMENT.renamed("EM_SINGLE_LINE_COMMENT")
  result.add TokenType(name: "EM_ML_COMMENT", pattern: matchMlComment, hidden: true)
  result.add TokenType(name: "EM_SL_COMMENT", pattern: matchSlComment, hidden: true)

let EVENTMODELING_TOKENS*: seq[TokenType] = buildTokens()

proc index(name: string): int =
  for k, t in EVENTMODELING_TOKENS:
    if t.name == name: return k
  -1

proc kinds(names: openArray[string]): HashSet[int] =
  for name in names: result.incl index(name)

let
  T_keyword = 0
  T_arrow = index("->>")
  T_open = index("[[")
  T_close = index("]]")
  T_tick = index("`")
  T_dot = index(".")
  T_id = index("EM_ID")
  T_frameId = index("EM_FID")
  T_inline = index("EM_DATA_INLINE")
  T_block = index("EM_DATA_BLOCK")
  T_accDescr = index("EM_ACC_DESCR")
  T_accTitle = index("EM_ACC_TITLE")
  T_title = index("EM_TITLE")
  T_entity = index("entity")
  T_data = index("data")
  T_note = index("note")
  T_gwt = index("gwt")
  T_given = index("given")
  T_when = index("when")
  T_then = index("then")
  TIME_FRAME = kinds(["tf", "timeframe"])
  RESET_FRAME = kinds(["rf", "resetframe"])
  ENTITY_TYPE = kinds(["rmo", "readmodel", "ui", "cmd", "command", "evt", "event", "pcr", "processor"])
  DATA_TYPE = kinds(["json", "jsobj", "figma", "salt", "uri", "md", "html", "text"])

type
  EmFrame* = object
    reset*: bool                     ## `$type` 'EmResetFrame' (else 'EmTimeFrame')
    name*: string
    modelEntityType*: string
    entityIdentifier*: string
    sourceFrames*: seq[string]       ## the `$refText` of each
    hasDataReference*: bool
    dataReference*: string
    dataType*: string                ## "" for undefined
    hasInline*: bool
    dataInlineValue*: string
    offset*: int
      ## Offset of the frame in the source, for error messages.

  EmDataEntity* = object
    name*: string
    dataType*: string
    dataBlockValue*: string

  EmNoteEntity* = object
    sourceFrame*: string
    dataType*: string
    dataBlockValue*: string

  EmGwt* = object
    sourceFrame*: string
    givenStatements*, whenStatements*, thenStatements*: seq[string]   ## entity identifiers

  EventModelAst* = object
    title*, accTitle*, accDescr*: string
      ## The whole token, keyword included: the grammar's own terminals get no value conversion.
      ## "" for undefined.
    modelEntities*: seq[string]
    frames*: seq[EmFrame]
    dataEntities*: seq[EmDataEntity]
    noteEntities*: seq[EmNoteEntity]
    gwtEntities*: seq[EmGwt]
    source*: string

proc parseEventModel*(src: string): EventModelAst =
  let r = newReader(tokenize(src, EVENTMODELING_TOKENS, "eventmodeling"), EVENTMODELING_TOKENS, "eventmodeling")
  var ast = EventModelAst(source: src)
  proc at(kind: int): bool = r.kinds[r.i] == kind
  proc one(kinds: HashSet[int], expected: string): string =
    if r.kinds[r.i] in kinds: r.take() else: r.fail(expected)
  proc qualifiedName(): string =
    result = r.expect(T_id)
    while r.accept(T_dot): result.add "." & r.expect(T_id)
  proc dataType(): string =
    if not r.accept(T_tick): return ""
    result = one(DATA_TYPE, "a data type")
    discard r.expect(T_tick)
  proc statements(): seq[string] =
    while true:
      discard one(ENTITY_TYPE, "an entity type")
      result.add r.expect(T_id)
      if r.kinds[r.i] notin ENTITY_TYPE: break

  discard r.expect(T_keyword)
  while not at(-1):
    let kind = r.kinds[r.i]
    if kind == T_accDescr:
      ast.accDescr = r.take()
    elif kind == T_accTitle:
      ast.accTitle = r.take()
    elif kind == T_title:
      ast.title = r.take()
    elif kind == T_entity:
      inc r.i
      ast.modelEntities.add qualifiedName()
    elif kind in TIME_FRAME or kind in RESET_FRAME:
      var frame = EmFrame(reset: kind notin TIME_FRAME, offset: r.tokens.starts[r.i])
      inc r.i
      frame.name = r.expect(T_frameId)
      frame.modelEntityType = one(ENTITY_TYPE, "an entity type")
      frame.entityIdentifier = qualifiedName()
      while r.accept(T_arrow): frame.sourceFrames.add r.expect(T_frameId)
      if r.accept(T_open):
        frame.hasDataReference = true
        frame.dataReference = r.expect(T_id)
        discard r.expect(T_close)
      if at(T_tick) or at(T_inline):
        frame.dataType = dataType()
        frame.hasInline = true
        frame.dataInlineValue = r.expect(T_inline)
      ast.frames.add frame
    elif kind == T_data:
      inc r.i
      var entity = EmDataEntity(name: r.expect(T_id))
      entity.dataType = dataType()
      entity.dataBlockValue = r.expect(T_block)
      ast.dataEntities.add entity
    elif kind == T_note:
      inc r.i
      var note = EmNoteEntity(sourceFrame: r.expect(T_frameId))
      note.dataType = dataType()
      note.dataBlockValue = r.expect(T_block)
      ast.noteEntities.add note
    elif kind == T_gwt:
      inc r.i
      var gwt = EmGwt(sourceFrame: r.expect(T_frameId))
      discard r.expect(T_given)
      gwt.givenStatements = statements()
      if r.accept(T_when): gwt.whenStatements = statements()
      discard r.expect(T_then)
      gwt.thenStatements = statements()
      ast.gwtEntities.add gwt
    else:
      r.fail("a frame, an entity, a data block, a note, or a specification")
  ast
