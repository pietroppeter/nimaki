## port-of: src/diagrams/eventmodeling/parser.ts
## port-status: draft
import std/sets
import ../common/[tokens, acc_descr]
import ../../jsregex

let EM_ID = TokenType(name: "EM_ID", pattern: jsre"/[_a-zA-Z][\w_]*/y")

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
  result.add TokenType(name: "EM_FID", pattern: jsre"/\d{1,3}/y")
  result.add TokenType(name: "EM_DATA_INLINE", pattern: jsre"""/\{(.*)\}|"(.*)"|'(.*)'/y""")
  result.add TokenType(name: "EM_DATA_BLOCK", pattern: jsre"/\{[\t ]*\r?\n(?:[\S\s]*?\r?\n)?\}(?:\r?\n|(?!\S))/y")
  result.add accDescr("EM_ACC_DESCR")
  result.add ACC_TITLE.renamed("EM_ACC_TITLE")
  result.add titleBefore(r"\w").renamed("EM_TITLE")
  result.add TokenType(name: "EM_WS", pattern: jsre"/\s+/y", hidden: true)
  result.add YAML.renamed("EM_YAML")
  result.add DIRECTIVE.renamed("EM_DIRECTIVE")
  result.add SINGLE_LINE_COMMENT.renamed("EM_SINGLE_LINE_COMMENT")
  result.add TokenType(name: "EM_ML_COMMENT", pattern: jsre"/\/\*[\s\S]*?\*\//y", hidden: true)
  result.add TokenType(name: "EM_SL_COMMENT", pattern: jsre"/\/\/[^\n\r]*/y", hidden: true)

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
