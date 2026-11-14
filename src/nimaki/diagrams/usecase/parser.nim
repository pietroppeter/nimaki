## port-of: src/diagrams/usecase/parser.ts
## port-status: conformant
##
## Mermaid parses use case diagrams with a Chevrotain parser, which decides each choice by
## looking at most three tokens ahead and reports the first token that fits nowhere. This parser
## makes the same decisions from the same lookahead, so it accepts the same text and names the
## same token in its errors. It builds the model directly, where Mermaid builds a syntax tree and
## then visits it. The statements Pele also records, with the positions of their parts, are left
## out (see types.nim).
import std/[strutils, sequtils]
import ../../errors
import ../../js
import db, json, lexer, tokens, types

const
  LINE = 1
  RELATION = 2
  STYLE_PART = 4
  FOLLOWS_NAME = 8
  BOUNDARY_LINE = 16
  CLOSES_LABEL = 32
  METADATA_FIRST = 64

  ARROWS = "DEPENDENCY_ARROW|GENERALIZATION|FORWARD_SOLID|BACKWARD_SOLID|MARKERLESS_SOLID|FORWARD_CIRCLE|" &
    "BACKWARD_CIRCLE|FORWARD_CROSS|BACKWARD_CROSS"
  NAMES = "IDENTIFIER|PLAIN_STRING|MARKDOWN_STRING"
  LABELS = "PLAIN_STRING|MARKDOWN_STRING|LABEL_TEXT"
  STATEMENTS = "ACC_TITLE_LINE|ACC_DESCR_LINE|ACC_DESCR_BLOCK|DIRECTION|ACTOR|SYSTEM_BOUNDARY|NOTE|" &
    "JSON_DECLARATION_START|CLASS_DEF|CLASS|STYLE"
  STYLE_PARTS = "WORD|PLAIN_STRING|NUMBER|HASH_COLOR|CSS_IDENTIFIER|CSS_ESCAPED_COMMA|DASH|DOT|PERCENT|" &
    "CSS_PUNCTUATION|COLON|LPAREN|RPAREN|LBRACKET|RBRACKET|LBRACE|RBRACE|AT|MARKERLESS_SOLID"

proc flags(): array[T_RPAREN + 1, int] =
  proc flag(output: var array[T_RPAREN + 1, int], names: string, bits: int) =
    for name in names.split('|'):
      # WORD is a category: every keyword and IDENTIFIER.
      if name == "WORD":
        for t in T_USECASE .. T_IDENTIFIER: output[t] = output[t] or bits
      else:
        let t = TOKEN_NAMES.find(name)
        output[t] = output[t] or bits
  flag(result, "NEWLINE|COMMENT|" & STATEMENTS & "|" & NAMES, LINE)
  flag(result, "IDENTIFIER|" & ARROWS, RELATION)
  flag(result, STYLE_PARTS, STYLE_PART)
  flag(result, "STEREOTYPE_START|CLASS_SEPARATOR|IDENTIFIER|" & ARROWS & "|NEWLINE|EOF", FOLLOWS_NAME)
  flag(result, "NEWLINE|COMMENT|ACTOR|" & NAMES, BOUNDARY_LINE)
  flag(result, "FORWARD_SOLID|MARKERLESS_SOLID|FORWARD_CIRCLE|FORWARD_CROSS", CLOSES_LABEL)
  flag(result, "NEWLINE|IDENTIFIER|PLAIN_STRING|RBRACE", METADATA_FIRST)

let FLAGS = flags()

const FORBIDDEN = ["allowmixing", "newpage", "package", "rectangle", "skinparam"]

type
  Item = object
    id: string
    label: DraftLabel
    span: Span
    generated: bool
    shape: string
    metadata: seq[DraftProperty]
    hasMetadata: bool
    stereotype: string
    classes: seq[string]
    # Whether this mention says something about the element, and so declares it.
    explicit: bool

  Tail = object
    explicitId: string
    explicitIdSpan: Span
    kind: string
    arrowType: int
    hasLabel: bool
    label: DraftLabel
    minlen: int
    target: Item
    span: Span

  Parser = ref object
    src: string
    types, starts, ends: seq[int]
    p: int
    drafts: Drafts
    parent: DraftBoundary
    pendingJson: seq[(DraftJson, int)]

proc image(q: Parser, k: int): string = q.src[q.starts[k] ..< q.ends[k]]

proc span(q: Parser, k: int): Span = (q.starts[k], q.ends[k])

proc fail(q: Parser, detail: string) =
  let (line, column) = lineColumn(q.src, q.starts[q.p])
  raise newPeleError("Error parsing usecase diagram: " & detail & " at " &
                     locationText(q.src, q.starts[q.p], q.ends[q.p]), "syntax",
                     ErrorInfo(diagramType: "usecase", line: line, column: column))

proc mismatch(q: Parser, name: string) =
  q.fail("Expecting token of type --> " & name & " <-- but found --> '" & q.image(q.p) & "' <--")

proc expect(q: Parser, kind: int): int =
  if q.types[q.p] != kind: q.mismatch(TOKEN_NAMES[kind])
  result = q.p
  inc q.p

# Chevrotain lists every token sequence that would have been accepted.
proc noAlternative(q: Parser, expected: string) =
  var list: seq[string]
  let sequences = expected.split('|')
  for i, sequence in sequences: list.add "  " & $(i + 1) & ". [" & sequence & "]"
  q.fail("Expecting: one of these possible Token sequences:\n" & list.join("\n") & "\nbut found: '" &
         q.image(q.p) & "'")

proc statementSequences(): string =
  let names = NAMES.split('|')
  var metadata: seq[string]
  for name in names:
    for next in ["NEWLINE", "IDENTIFIER", "PLAIN_STRING", "RBRACE"]:
      metadata.add name & ", METADATA_START, " & next
  let follows = ("STEREOTYPE_START|CLASS_SEPARATOR|IDENTIFIER|" & ARROWS & "|NEWLINE|EOF").split('|')
  var entities: seq[string]
  for i, name in names:
    let nexts = if i == 0: @["LPAREN", "LBRACKET"] & follows else: follows
    for next in nexts: entities.add name & ", " & next
  (@[STATEMENTS] & metadata & entities & metadata).join("|")

func isWord(kind: int): bool = kind >= T_USECASE and kind <= T_IDENTIFIER

func isLabelText(kind: int): bool = kind >= T_USECASE and kind <= T_LABEL_SYMBOL

proc lineEnd(q: Parser) =
  if q.types[q.p] == T_NEWLINE: inc q.p
  elif q.types[q.p] != T_EOF: q.noAlternative("NEWLINE|EOF")

# The text of a name or string token, without its quotes.
proc content(q: Parser, k: int): Span =
  let trim = if q.types[k] == T_MARKDOWN_STRING: 2 elif q.types[k] == T_PLAIN_STRING: 1 else: 0
  (q.starts[k] + trim, q.ends[k] - trim)

proc tokenLabel(q: Parser, k: int): DraftLabel =
  let at = q.content(k)
  DraftLabel(text: q.src[at[0] ..< at[1]], markdown: q.types[k] == T_MARKDOWN_STRING, span: at)

proc generatedId(label: string): string =
  ## label.replace(/\W/g, '_'): one `_` for each UTF-16 code unit that is not a word character.
  var i = 0
  while i < label.len:
    if isWordChar(label[i]):
      result.add label[i]
      inc i
    else:
      let (cp, size) = codePointAt(label, i)
      result.add(if cp >= 0x10000: "__" else: "_")
      i += size

# An unquoted label runs to the next delimiter and is taken from the source as written.
proc label(q: Parser): DraftLabel =
  let kind = q.types[q.p]
  if kind == T_PLAIN_STRING or kind == T_MARKDOWN_STRING:
    result = q.tokenLabel(q.p)
    inc q.p
    return
  if not isLabelText(kind): q.noAlternative(LABELS)
  let first = q.p
  while isLabelText(q.types[q.p]): inc q.p
  let at = (q.starts[first], q.ends[q.p - 1])
  DraftLabel(text: q.src[at[0] ..< at[1]], span: at)

func isKey(kind: int): bool = kind == T_IDENTIFIER or kind == T_PLAIN_STRING

proc property(q: Parser): DraftProperty =
  let key = q.p
  if not isKey(q.types[q.p]): q.noAlternative("IDENTIFIER|PLAIN_STRING")
  inc q.p
  discard q.expect(T_COLON)
  let value = q.p
  let kind = q.types[q.p]
  if not isKey(kind) and kind != T_TRUE and kind != T_FALSE: q.noAlternative("IDENTIFIER|PLAIN_STRING|TRUE|FALSE")
  inc q.p
  let keySpan = q.content(key)
  let valueSpan = q.content(value)
  result = DraftProperty(key: q.src[keySpan[0] ..< keySpan[1]], span: (q.starts[key], q.ends[value]),
                         keySpan: keySpan, valueSpan: valueSpan)
  if kind == T_TRUE or kind == T_FALSE:
    result.isBool = true
    result.b = kind == T_TRUE
  else: result.s = q.src[valueSpan[0] ..< valueSpan[1]]

# Whether another property follows. A comma or line breaks before the closing brace do not count,
# but Chevrotain looks only three tokens ahead, so a comma and two line breaks, or three line
# breaks, are taken for a separator and the brace after them is then an error.
proc separatorAhead(q: Parser): bool =
  let a = q.types[q.p]
  let b = q.types[q.p + 1]
  let c = q.types[q.p + 2]
  if a == T_COMMA: return isKey(b) or (b == T_NEWLINE and (c == T_NEWLINE or isKey(c)))
  if a != T_NEWLINE: return false
  b == T_COMMA or isKey(b) or (b == T_NEWLINE and (c == T_NEWLINE or c == T_COMMA or isKey(c)))

proc metadata(q: Parser): seq[DraftProperty] =
  discard q.expect(T_METADATA_START)
  while q.types[q.p] == T_NEWLINE: inc q.p
  if isKey(q.types[q.p]):
    result.add q.property()
    while q.separatorAhead():
      if q.types[q.p] == T_COMMA: inc q.p
      else:
        while q.types[q.p] == T_NEWLINE: inc q.p
        if q.types[q.p] == T_COMMA: inc q.p
      while q.types[q.p] == T_NEWLINE: inc q.p
      result.add q.property()
    if q.types[q.p] == T_COMMA: inc q.p
    while q.types[q.p] == T_NEWLINE: inc q.p
  discard q.expect(T_RBRACE)

proc classSuffix(q: Parser, classes: var seq[string]) =
  while true:
    inc q.p
    let id = q.expect(T_IDENTIFIER)
    classes.add q.image(id)
    if q.types[q.p] != T_COMMA: break

# An id with an optional label in parentheses or brackets, or a string that stands for both.
proc name(q: Parser, brackets: bool): Item =
  let k = q.p
  let kind = q.types[q.p]
  result = Item(span: q.content(k), generated: kind != T_IDENTIFIER)
  if kind == T_IDENTIFIER:
    inc q.p
    result.id = q.image(k)
    let open = q.types[q.p]
    if open == T_LPAREN or (brackets and open == T_LBRACKET):
      inc q.p
      result.label = q.label()
      discard q.expect(if open == T_LPAREN: T_RPAREN else: T_RBRACKET)
      result.shape = if open == T_LPAREN: "ellipse" else: "rect"
    else: result.label = q.tokenLabel(k)
  elif kind == T_PLAIN_STRING or kind == T_MARKDOWN_STRING:
    inc q.p
    result.label = q.tokenLabel(k)
    result.id = generatedId(result.label.text)
  else: q.noAlternative(NAMES)

proc element(q: Parser, actor: bool): Item =
  result = q.name(not actor)
  if actor: result.shape = ""
  if q.types[q.p] == T_METADATA_START:
    result.metadata = q.metadata()
    result.hasMetadata = true
  if q.types[q.p] == T_STEREOTYPE_START:
    inc q.p
    let text = q.expect(T_STEREOTYPE_TEXT)
    discard q.expect(T_STEREOTYPE_END)
    result.stereotype = jsTrim(q.image(text))
  if q.types[q.p] == T_CLASS_SEPARATOR: q.classSuffix(result.classes)
  result.explicit = result.shape != "" or result.hasMetadata or result.stereotype != ""

proc draft(q: Parser, item: Item, kind: string): DraftElement =
  DraftElement(id: item.id, kind: kind, label: item.label, span: item.span, generated: item.generated,
               parent: q.parent, shape: item.shape, metadata: item.metadata, stereotype: item.stereotype,
               classes: item.classes)

proc endpoint(item: Item, declares: bool): DraftEndpoint =
  DraftEndpoint(id: item.id, label: item.label, span: item.span, generated: item.generated, declares: declares,
                classed: item.classes.len > 0)

# Whether a label and then one of the operators that can close it come next.
proc labeledRight(q: Parser, closers: int): bool =
  if q.types[q.p] < T_USECASE or q.types[q.p] > T_MARKDOWN_STRING: return false
  var k = q.p + 1
  while true:
    let kind = q.types[k]
    if kind == T_MARKERLESS_SOLID or (FLAGS[kind] and closers) != 0: return true
    if kind < T_USECASE or kind > T_MARKDOWN_STRING: return false
    inc k

# Each dash beyond the second asks for one more rank between the two ends.
proc minimumLength(q: Parser, k: int): int =
  let dashes = q.ends[k] - q.starts[k] - (if q.types[k] == T_MARKERLESS_SOLID: 0 else: 1)
  max(1, dashes - 1)

proc relationTail(q: Parser): Tail =
  let first = q.p
  var tail = Tail(kind: "association", arrowType: SOLID_ARROW, minlen: 1)
  if q.types[q.p] == T_IDENTIFIER and q.types[q.p + 1] == T_AT:
    tail.explicitId = q.image(q.p)
    tail.explicitIdSpan = q.span(q.p)
    q.p += 2
  let k = q.p
  let kind = q.types[q.p]
  inc q.p
  if kind == T_DEPENDENCY_ARROW:
    discard q.expect(T_COLON)
    if q.types[q.p] != T_INCLUDE and q.types[q.p] != T_EXTEND: q.noAlternative("INCLUDE|EXTEND")
    tail.kind = if q.types[q.p] == T_INCLUDE: "include" else: "extend"
    tail.hasLabel = true
    tail.label = DraftLabel(text: tail.kind, span: q.span(q.p))
    inc q.p
  elif kind == T_GENERALIZATION: tail.kind = "generalization"
  elif kind == T_FORWARD_SOLID: tail.minlen = q.minimumLength(k)
  elif kind == T_BACKWARD_SOLID:
    tail.arrowType = BACK_ARROW
    # Only the shortest operator can open a label: `A <-- label -- B`.
    if q.ends[k] - q.starts[k] == 3 and q.labeledRight(0):
      tail.hasLabel = true
      tail.label = q.label()
      tail.minlen = q.minimumLength(q.expect(T_MARKERLESS_SOLID))
    else: tail.minlen = q.minimumLength(k)
  elif kind == T_MARKERLESS_SOLID:
    tail.arrowType = LINE_SOLID
    if q.ends[k] - q.starts[k] == 2 and q.labeledRight(CLOSES_LABEL):
      tail.hasLabel = true
      tail.label = q.label()
      let close = q.types[q.p]
      if close == T_FORWARD_SOLID: tail.arrowType = SOLID_ARROW
      elif close == T_FORWARD_CIRCLE: tail.arrowType = CIRCLE_ARROW
      elif close == T_FORWARD_CROSS: tail.arrowType = CROSS_ARROW
      elif close != T_MARKERLESS_SOLID: q.noAlternative("FORWARD_SOLID|MARKERLESS_SOLID|FORWARD_CIRCLE|FORWARD_CROSS")
      if tail.arrowType == SOLID_ARROW or tail.arrowType == LINE_SOLID: tail.minlen = q.minimumLength(q.p)
      inc q.p
    else: tail.minlen = q.minimumLength(k)
  elif kind == T_FORWARD_CIRCLE: tail.arrowType = CIRCLE_ARROW
  elif kind == T_FORWARD_CROSS: tail.arrowType = CROSS_ARROW
  elif kind == T_BACKWARD_CIRCLE or kind == T_BACKWARD_CROSS:
    tail.arrowType = if kind == T_BACKWARD_CIRCLE: CIRCLE_ARROW_REVERSED else: CROSS_ARROW_REVERSED
    if q.labeledRight(0):
      tail.hasLabel = true
      tail.label = q.label()
      discard q.expect(T_MARKERLESS_SOLID)
  else:
    dec q.p
    q.noAlternative(ARROWS)
  tail.target = q.element(false)
  tail.span = (q.starts[first], q.ends[q.p - 1])
  tail

proc relationship(q: Parser, source: Item, declaration: bool, tail: Tail) =
  let target = tail.target
  if target.explicit: q.drafts.elements.add q.draft(target, "usecase")
  q.drafts.relationships.add DraftRelationship(
    source: endpoint(source, declaration),
    target: endpoint(target, target.explicit),
    span: tail.span,
    id: tail.explicitId,
    idSpan: tail.explicitIdSpan,
    kind: tail.kind,
    arrowType: tail.arrowType,
    hasLabel: tail.hasLabel,
    label: tail.label,
    minlen: tail.minlen,
  )

# `actor A, B` declares several actors; at the top level `actor A --> B` declares one and relates it.
proc actors(q: Parser, top: bool) =
  inc q.p
  var items = @[q.element(true)]
  var hasTail = false
  var tail: Tail
  if q.types[q.p] == T_COMMA:
    while true:
      inc q.p
      items.add q.element(true)
      if q.types[q.p] != T_COMMA: break
  elif top and (FLAGS[q.types[q.p]] and RELATION) != 0:
    tail = q.relationTail()
    hasTail = true
  q.lineEnd()
  for item in items: q.drafts.elements.add q.draft(item, "actor")
  if hasTail: q.relationship(items[0], true, tail)

proc entity(q: Parser, top: bool) =
  var source = q.element(false)
  let hasTail = top and (FLAGS[q.types[q.p]] and RELATION) != 0
  let tail = if hasTail: q.relationTail() else: Tail()
  q.lineEnd()
  if not hasTail:
    source.explicit = true
    if source.shape == "": source.shape = "ellipse"
  if source.explicit: q.drafts.elements.add q.draft(source, "usecase")
  if hasTail: q.relationship(source, source.explicit, tail)

proc line(q: Parser, top: bool)

proc boundary(q: Parser) =
  inc q.p
  let named = q.name(true)
  let group = DraftBoundary(id: named.id, label: named.label, span: named.span, generated: named.generated)
  var hasInline = false
  var inline: seq[DraftProperty]
  if q.types[q.p] == T_METADATA_START:
    inline = q.metadata()
    hasInline = true
  if q.types[q.p] == T_CLASS_SEPARATOR: q.classSuffix(group.classes)
  q.lineEnd()
  q.drafts.boundaries.add group
  q.parent = group
  while (FLAGS[q.types[q.p]] and BOUNDARY_LINE) != 0: q.line(false)
  q.parent = nil
  discard q.expect(T_END)
  q.lineEnd()
  if hasInline:
    q.drafts.metadata.add DraftMetadata(target: group.id, span: group.span, properties: inline)

proc style(q: Parser): string =
  let first = q.p
  let kind = q.types[q.p]
  if isWord(kind) or kind == T_CSS_IDENTIFIER: inc q.p
  elif kind == T_MARKERLESS_SOLID:
    inc q.p
    if not isWord(q.types[q.p]): q.mismatch("WORD")
    inc q.p
  else: q.noAlternative("WORD|CSS_IDENTIFIER|MARKERLESS_SOLID")
  discard q.expect(T_COLON)
  if (FLAGS[q.types[q.p]] and STYLE_PART) == 0:
    q.fail("Expecting: expecting at least one iteration which starts with one of these possible Token " &
           "sequences::\n  <[" & STYLE_PARTS.replace("|", "] ,[") & "]>\nbut found: '" & q.image(q.p) & "'")
  while (FLAGS[q.types[q.p]] and STYLE_PART) != 0: inc q.p
  # The value is taken from the source, so the spaces inside `1px solid red` survive.
  q.src[q.starts[first] ..< q.ends[q.p - 1]].replace("\\,", ",")

proc styles(q: Parser): seq[string] =
  result = @[q.style()]
  while q.types[q.p] == T_COMMA:
    inc q.p
    result.add q.style()

proc identifiers(q: Parser): seq[int] =
  result = @[q.expect(T_IDENTIFIER)]
  while q.types[q.p] == T_COMMA:
    inc q.p
    result.add q.expect(T_IDENTIFIER)

proc topStatement(q: Parser) =
  let k = q.p
  let kind = q.types[q.p]
  if kind == T_ACC_TITLE_LINE or kind == T_ACC_DESCR_LINE or kind == T_ACC_DESCR_BLOCK:
    inc q.p
    let text = q.image(k)
    if kind == T_ACC_DESCR_BLOCK:
      q.drafts.accDescription = jsTrim(text[text.find('{') + 1 ..< text.rfind('}')])
    elif kind == T_ACC_DESCR_LINE: q.drafts.accDescription = jsTrim(text[text.find(':') + 1 .. ^1])
    else: q.drafts.accTitle = jsTrim(text[text.find(':') + 1 .. ^1])
  elif kind == T_DIRECTION:
    inc q.p
    let value = q.types[q.p]
    if value < T_TD or value > T_RL: q.noAlternative("TD|TB|BT|LR|RL")
    q.drafts.direction = if value == T_TD: "TB" else: q.image(q.p)
    inc q.p
  elif kind == T_ACTOR:
    q.actors(true)
    return
  elif kind == T_SYSTEM_BOUNDARY:
    q.boundary()
    return
  elif kind == T_NOTE:
    inc q.p
    discard q.expect(T_FOR)
    let target = q.expect(T_IDENTIFIER)
    let text = q.label()
    q.drafts.notes.add DraftNote(target: q.image(target), span: q.span(target), label: text)
  elif kind == T_JSON_DECLARATION_START:
    inc q.p
    let literal = q.expect(T_JSON_OBJECT_LITERAL)
    var classes: seq[string]
    if q.types[q.p] == T_CLASS_SEPARATOR: q.classSuffix(classes)
    var start = q.starts[k] + 4
    while start < q.src.len and q.src[start] in {' ', '\t'}: inc start
    var stop = start
    while stop < q.src.len and isWordChar(q.src[stop]): inc stop
    let json = DraftJson(id: q.src[start ..< stop], value: JsonValue(kind: jObject), span: (start, stop),
                         classes: classes)
    q.drafts.jsons.add json
    q.pendingJson.add (json, literal)
  elif kind == T_CLASS_DEF:
    inc q.p
    let ids = q.identifiers()
    q.drafts.classDefs.add DraftClassDef(ids: ids.mapIt(q.image(it)), styles: q.styles())
  elif kind == T_CLASS:
    inc q.p
    let targets = q.identifiers()
    let classes = q.identifiers()
    q.drafts.classes.add DraftClass(targets: targets.mapIt((q.image(it), q.span(it))),
                                    classes: classes.mapIt(q.image(it)))
  elif kind == T_STYLE:
    inc q.p
    let target = q.expect(T_IDENTIFIER)
    q.drafts.styles.add DraftStyle(target: q.image(target), span: q.span(target), styles: q.styles())
  else:
    let next = q.types[q.p + 1]
    if next == T_METADATA_START:
      if (FLAGS[q.types[q.p + 2]] and METADATA_FIRST) == 0: q.noAlternative(statementSequences())
      inc q.p
      let at = q.content(k)
      let id = if kind != T_IDENTIFIER: generatedId(q.src[at[0] ..< at[1]]) else: q.image(k)
      let assigned = q.metadata()
      q.drafts.metadata.add DraftMetadata(target: id, span: at, properties: assigned)
    else:
      let follows = (FLAGS[next] and FOLLOWS_NAME) != 0 or
        (kind == T_IDENTIFIER and (next == T_LPAREN or next == T_LBRACKET))
      # Mermaid turns away the PlantUML statements people are most likely to try.
      if not follows or (kind == T_IDENTIFIER and q.image(k).toLowerAscii in FORBIDDEN):
        q.noAlternative(statementSequences())
      q.entity(true)
      return
  q.lineEnd()

proc line(q: Parser, top: bool) =
  let kind = q.types[q.p]
  if kind == T_NEWLINE:
    inc q.p
    return
  if kind == T_COMMENT:
    inc q.p
    q.lineEnd()
    return
  if top: q.topStatement()
  elif kind == T_ACTOR: q.actors(false)
  else: q.entity(false)

proc parseUsecase*(source: string, title = ""): UsecaseModel =
  let tokens = tokenize(source)
  let q = Parser(src: source, types: tokens.types, starts: tokens.starts, ends: tokens.ends,
                 drafts: emptyDrafts())
  let header = q.expect(T_USECASE)
  q.lineEnd()
  while (FLAGS[q.types[q.p]] and LINE) != 0: q.line(true)
  if q.types[q.p] != T_EOF: q.fail("Redundant input, expecting EOF but found: " & q.image(q.p))
  # The whole text has to be well formed before the JSON in it is looked at, as in Mermaid.
  for (json, literal) in q.pendingJson:
    let at = q.starts[literal]
    let parsed = parseOrderedJson(q.image(literal), proc (): (int, int) = lineColumn(source, at))
    json.value = parsed.value
    json.propertyOrder = parsed.propertyOrder
  resolveUsecase(source, q.drafts, q.span(header), title)
