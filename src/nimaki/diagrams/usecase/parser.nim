## port-of: src/diagrams/usecase/parser.ts
## port-status: conformant
##
## Mermaid parses use case diagrams with a Chevrotain parser, which decides each choice by
## looking at most three tokens ahead and reports the first token that fits nowhere. This parser
## makes the same decisions from the same lookahead, so it accepts the same text and names the
## same token in its errors. It builds the model directly, where Mermaid builds a syntax tree and
## then visits it, and records each statement with the positions of its parts, as Pele does.
import std/[options, strutils, sequtils]
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
    stereotypeSpan: Option[Span]
    classes: seq[string]
    classSpans: seq[Span]
    nodeSpan: Span
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
    lastEnd: int
    edgeCount, noteCount: int

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
  q.lastEnd = q.ends[q.p - 1]
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
  ## A scanner, as a regex here reads a character past U+FFFF as one, where Pele writes two `_`.
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

func occurrences(properties: seq[DraftProperty]): seq[MetadataOccurrence] =
  for property in properties:
    result.add MetadataOccurrence(key: property.key, span: property.span, keySpan: property.keySpan,
                                  valueSpan: property.valueSpan)

proc classSuffix(q: Parser, classes: var seq[string], spans: var seq[Span]) =
  while true:
    inc q.p
    let id = q.expect(T_IDENTIFIER)
    classes.add q.image(id)
    spans.add q.span(id)
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
  let first = q.p
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
    result.stereotypeSpan = some q.span(text)
  if q.types[q.p] == T_CLASS_SEPARATOR: q.classSuffix(result.classes, result.classSpans)
  result.explicit = result.shape != "" or result.hasMetadata or result.stereotype != ""
  result.nodeSpan = (q.starts[first], q.ends[q.p - 1])

proc draft(q: Parser, item: Item, kind: string): DraftElement =
  DraftElement(id: item.id, kind: kind, label: item.label, span: item.span, generated: item.generated,
               parent: q.parent, shape: item.shape, metadata: item.metadata, stereotype: item.stereotype,
               classes: item.classes)

proc endpoint(item: Item, declares: bool): DraftEndpoint =
  DraftEndpoint(id: item.id, label: item.label, span: item.span, generated: item.generated, declares: declares,
                classed: item.classes.len > 0)

proc occurrence(item: Item, defines: bool): NodeOccurrence =
  result = NodeOccurrence(id: item.id, span: item.nodeSpan, idSpan: item.span, labelSpan: some item.label.span)
  if defines: result.defines = some true
  result.stereotypeSpan = item.stereotypeSpan
  if item.hasMetadata: result.metadata = some occurrences(item.metadata)
  if item.classSpans.len > 0: result.classSpans = some item.classSpans

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

func statement(kind: string): GraphStatement = GraphStatement(statementKind: kind)

proc relationship(q: Parser, source: Item, declaration: bool, tail: Tail,
                  nodes: sink seq[NodeOccurrence]): GraphStatement =
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
  var nodes = nodes
  nodes.add occurrence(target, target.explicit)
  result = statement("edge")
  result.nodes = some nodes
  var edge = EdgeOccurrence(id: tail.explicitId)
  if tail.explicitId == "":
    edge.id = "edge-" & $q.edgeCount
    inc q.edgeCount
  else: edge.idSpan = some tail.explicitIdSpan
  if tail.hasLabel: edge.labelSpan = some tail.label.span
  result.edges = some @[edge]

proc declaration(nodes: seq[NodeOccurrence]): GraphStatement =
  result = statement("node")
  result.nodes = some nodes

# `actor A, B` declares several actors; at the top level `actor A --> B` declares one and relates it.
proc actors(q: Parser, top: bool): GraphStatement =
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
  let nodes = items.mapIt(occurrence(it, true))
  if hasTail: q.relationship(items[0], true, tail, nodes) else: declaration(nodes)

proc entity(q: Parser, top: bool): GraphStatement =
  var source = q.element(false)
  let hasTail = top and (FLAGS[q.types[q.p]] and RELATION) != 0
  let tail = if hasTail: q.relationTail() else: Tail()
  q.lineEnd()
  if not hasTail:
    source.explicit = true
    if source.shape == "": source.shape = "ellipse"
  if source.explicit: q.drafts.elements.add q.draft(source, "usecase")
  let nodes = @[occurrence(source, source.explicit)]
  if hasTail: q.relationship(source, source.explicit, tail, nodes) else: declaration(nodes)

proc line(q: Parser, top: bool): GraphStatement

proc boundary(q: Parser): GraphStatement =
  inc q.p
  let named = q.name(true)
  let group = DraftBoundary(id: named.id, label: named.label, span: named.span, generated: named.generated)
  var hasInline = false
  var inline: seq[DraftProperty]
  if q.types[q.p] == T_METADATA_START:
    inline = q.metadata()
    hasInline = true
  var classSpans: seq[Span]
  if q.types[q.p] == T_CLASS_SEPARATOR: q.classSuffix(group.classes, classSpans)
  q.lineEnd()
  q.drafts.boundaries.add group
  q.parent = group
  var children: seq[GraphStatement]
  while (FLAGS[q.types[q.p]] and BOUNDARY_LINE) != 0: children.add q.line(false)
  q.parent = nil
  let stop = q.expect(T_END)
  q.lineEnd()
  result = statement("group")
  result.group = some group.id
  result.idSpan = some group.span
  result.titleSpan = some group.label.span
  result.endSpan = some q.span(stop)
  result.classSpans = some classSpans
  if children.len > 0: result.children = some children
  if hasInline:
    result.metadata = some occurrences(inline)
    q.drafts.metadata.add DraftMetadata(target: group.id, span: group.span, properties: inline, statement: result)

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

proc reference(q: Parser, k: int): NodeOccurrence =
  let at = q.content(k)
  NodeOccurrence(id: q.image(k), span: at, idSpan: at)

proc topStatement(q: Parser): GraphStatement =
  let k = q.p
  let kind = q.types[q.p]
  if kind == T_ACC_TITLE_LINE or kind == T_ACC_DESCR_LINE or kind == T_ACC_DESCR_BLOCK:
    inc q.p
    let text = q.image(k)
    if kind == T_ACC_DESCR_BLOCK:
      q.drafts.accDescription = jsTrim(text[text.find('{') + 1 ..< text.rfind('}')])
    elif kind == T_ACC_DESCR_LINE: q.drafts.accDescription = jsTrim(text[text.find(':') + 1 .. ^1])
    else: q.drafts.accTitle = jsTrim(text[text.find(':') + 1 .. ^1])
    result = statement(if kind == T_ACC_TITLE_LINE: "accTitle" else: "accDescr")
  elif kind == T_DIRECTION:
    inc q.p
    let value = q.types[q.p]
    if value < T_TD or value > T_RL: q.noAlternative("TD|TB|BT|LR|RL")
    q.drafts.direction = if value == T_TD: "TB" else: q.image(q.p)
    inc q.p
    result = statement("direction")
  elif kind == T_ACTOR:
    return q.actors(true)
  elif kind == T_SYSTEM_BOUNDARY:
    return q.boundary()
  elif kind == T_NOTE:
    inc q.p
    discard q.expect(T_FOR)
    let target = q.expect(T_IDENTIFIER)
    let text = q.label()
    q.drafts.notes.add DraftNote(target: q.image(target), span: q.span(target), label: text)
    result = statement("note")
    result.`ref` = some("note-" & $q.noteCount)
    inc q.noteCount
    result.refSpan = some text.span
    result.nodes = some @[q.reference(target)]
  elif kind == T_JSON_DECLARATION_START:
    inc q.p
    let literal = q.expect(T_JSON_OBJECT_LITERAL)
    var classes: seq[string]
    var classSpans: seq[Span]
    if q.types[q.p] == T_CLASS_SEPARATOR: q.classSuffix(classes, classSpans)
    var start = q.starts[k] + 4
    while start < q.src.len and q.src[start] in {' ', '\t'}: inc start
    var stop = start
    while stop < q.src.len and isWordChar(q.src[stop]): inc stop
    let json = DraftJson(id: q.src[start ..< stop], value: JsonValue(kind: jObject), span: (start, stop),
                         classes: classes)
    q.drafts.jsons.add json
    q.pendingJson.add (json, literal)
    result = statement("json")
    result.nodes = some @[NodeOccurrence(id: json.id, span: json.span, idSpan: json.span, defines: some true,
                                         classSpans: some classSpans)]
    result.classSpans = some classSpans
  elif kind == T_CLASS_DEF:
    inc q.p
    let ids = q.identifiers()
    q.drafts.classDefs.add DraftClassDef(ids: ids.mapIt(q.image(it)), styles: q.styles())
    result = statement("classDef")
    result.`ref` = some q.image(ids[0])
    result.refSpan = some q.span(ids[0])
  elif kind == T_CLASS:
    inc q.p
    let targets = q.identifiers()
    let classes = q.identifiers()
    q.drafts.classes.add DraftClass(targets: targets.mapIt((q.image(it), q.span(it))),
                                    classes: classes.mapIt(q.image(it)))
    result = statement("classAssign")
    result.`ref` = some q.image(classes[0])
    result.refSpan = some q.span(classes[0])
    result.nodes = some targets.mapIt(q.reference(it))
  elif kind == T_STYLE:
    inc q.p
    let target = q.expect(T_IDENTIFIER)
    q.drafts.styles.add DraftStyle(target: q.image(target), span: q.span(target), styles: q.styles())
    result = statement("style")
    result.nodes = some @[q.reference(target)]
  else:
    let next = q.types[q.p + 1]
    if next == T_METADATA_START:
      if (FLAGS[q.types[q.p + 2]] and METADATA_FIRST) == 0: q.noAlternative(statementSequences())
      inc q.p
      var target = q.reference(k)
      if kind != T_IDENTIFIER: target.id = generatedId(q.src[target.span[0] ..< target.span[1]])
      let assigned = q.metadata()
      result = statement("metadata")
      result.nodes = some @[target]
      result.metadata = some occurrences(assigned)
      q.drafts.metadata.add DraftMetadata(target: target.id, span: target.span, properties: assigned,
                                          statement: result)
    else:
      let follows = (FLAGS[next] and FOLLOWS_NAME) != 0 or
        (kind == T_IDENTIFIER and (next == T_LPAREN or next == T_LBRACKET))
      # Mermaid turns away the PlantUML statements people are most likely to try.
      if not follows or (kind == T_IDENTIFIER and q.image(k).toLowerAscii in FORBIDDEN):
        q.noAlternative(statementSequences())
      return q.entity(true)
  q.lineEnd()

proc line(q: Parser, top: bool): GraphStatement =
  let k = q.p
  let kind = q.types[q.p]
  if kind == T_NEWLINE:
    inc q.p
    return GraphStatement(statementKind: "blank", span: q.span(k))
  if kind == T_COMMENT:
    inc q.p
    q.lineEnd()
    return GraphStatement(statementKind: "comment", span: q.span(k))
  result = if top: q.topStatement() elif kind == T_ACTOR: q.actors(false) else: q.entity(false)
  result.span = (q.starts[k], q.lastEnd)
  if result.edges.isSome:
    for edge in result.edges.get.mitems: edge.span = result.span

proc inUtf16(statements: var seq[GraphStatement], headerSpan: var Span, src: string) =
  ## Pele's positions count UTF-16 code units, as JavaScript's strings do, and the parser's count
  ## bytes: the positions it records are turned into Pele's once the text is read.
  var ascii = true
  for c in src:
    if ord(c) >= 0x80:
      ascii = false
      break
  if ascii: return
  var units = newSeq[int](src.len + 1)
  var i, u = 0
  while i < src.len:
    let (cp, size) = codePointAt(src, i)
    for j in i ..< min(i + size, src.len): units[j] = u
    u += (if cp >= 0x10000: 2 else: 1)
    i += size
  units[src.len] = u
  proc fix(x: var Span) = x = (units[x[0]], units[x[1]])
  proc fix(x: var Option[Span]) =
    if x.isSome: fix(x.get)
  proc fix(x: var Option[seq[Span]]) =
    if x.isSome:
      for s in x.get.mitems: fix(s)
  proc fix(x: var Option[seq[MetadataOccurrence]]) =
    if x.isSome:
      for m in x.get.mitems:
        fix(m.span)
        fix(m.keySpan)
        fix(m.valueSpan)
  proc fix(statement: GraphStatement) =
    fix(statement.span)
    if statement.nodes.isSome:
      for n in statement.nodes.get.mitems:
        fix(n.span)
        fix(n.idSpan)
        fix(n.labelSpan)
        fix(n.stereotypeSpan)
        fix(n.metadata)
        fix(n.classSpans)
    if statement.edges.isSome:
      for e in statement.edges.get.mitems:
        fix(e.span)
        fix(e.labelSpan)
        fix(e.idSpan)
        fix(e.metadata)
    fix(statement.idSpan)
    fix(statement.titleSpan)
    fix(statement.endSpan)
    fix(statement.refSpan)
    fix(statement.metadata)
    fix(statement.classSpans)
    if statement.children.isSome:
      for child in statement.children.get: fix(child)
  for statement in statements: fix(statement)
  fix(headerSpan)

proc parseUsecase*(source: string, title = ""): UsecaseModel =
  let tokens = tokenize(source)
  let q = Parser(src: source, types: tokens.types, starts: tokens.starts, ends: tokens.ends,
                 drafts: emptyDrafts())
  let header = q.expect(T_USECASE)
  q.lineEnd()
  var statements: seq[GraphStatement]
  while (FLAGS[q.types[q.p]] and LINE) != 0: statements.add q.line(true)
  if q.types[q.p] != T_EOF: q.fail("Redundant input, expecting EOF but found: " & q.image(q.p))
  # The whole text has to be well formed before the JSON in it is looked at, as in Mermaid.
  for (json, literal) in q.pendingJson:
    let at = q.starts[literal]
    let parsed = parseOrderedJson(q.image(literal), proc (): (int, int) = lineColumn(source, at))
    json.value = parsed.value
    json.propertyOrder = parsed.propertyOrder
  result = resolveUsecase(source, q.drafts, q.span(header), statements, title)
  inUtf16(result.statements, result.headerSpan, source)
