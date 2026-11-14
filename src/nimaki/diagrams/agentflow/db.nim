## port-of: src/diagrams/agentflow/db.ts
## port-status: draft
##
## Left out, because nothing drawn reads them: the semantic model, the element mappings and the
## diagnostics (Pele's `log` option is never set by the entry point). Metadata is a YAML record,
## nil for undefined; `Object.assign` of a list or a string adds its indexes as keys, as in Pele.
import std/[algorithm, options, sets, strutils, tables, unicode]
from std/math import isNaN
import ../../errors
import ../../js
import ../../util/[url, yaml]
import shapes, types
import ../../jsregex

type
  AgentflowDbOptions* = object
    maxEdges*: Option[int]
    inheritDir*: bool
    direction*: string         ## "" for undefined
    lineOffset*: int
    source*: Option[string]

const TOOL_SHAPES = ["subroutine", "subprocess", "subproc", "framed-rectangle", "tool"]

proc isToolDefinition*(vertex: AgentNode): bool = vertex.kind in TOOL_SHAPES

proc labelType(t: string): LabelType =
  ## `t` "" is undefined.
  if t == "markdown" or t == "string" or t == "text": t else: "markdown"

proc labelTypeOf(v: YamlValue): LabelType =
  labelType(if v != nil and v.kind == yString: v.s else: "")

proc unquote(text: string): string =
  if text.startsWith("\"") and text.endsWith("\""): text.substr(1, text.len - 2) else: text

func isObject(v: YamlValue): bool = v.isRecord

# Drops `__proto__`, `constructor` and `prototype` keys at every level, so that a consumer
# merging metadata into its own objects cannot be made to pollute a prototype.
proc stripPrototypeKeys(root: YamlValue): YamlValue =
  if root == nil: return root
  case root.kind
  of ySeq:
    result = yseq()
    for entry in root.items: result.items.add stripPrototypeKeys(entry)
  of yMap:
    result = ymap()
    for key, entry in root.fields:
      if key == "__proto__" or key == "constructor" or key == "prototype": continue
      result.fields[key] = stripPrototypeKeys(entry)
  else: result = root

# Adds what a metadata block holds to an element's metadata. Mermaid spreads the parsed YAML
# whatever it is, so a list adds its indexes as keys and a string its characters.
proc merge(into: YamlValue, doc: YamlValue): YamlValue =
  result = if into == nil: ymap() else: into
  case doc.kind
  of yMap:
    for k, v in doc.fields: result.fields[k] = v
  of ySeq:
    for k, v in doc.items: result.fields[$k] = v
  of yString:
    var k = 0
    var i = 0
    while i < doc.s.len:
      let (cp, size) = codePointAt(doc.s, i)
      if cp >= 0x10000:
        # Two code units, each a lone surrogate: kept whole here, which nothing drawn can tell.
        result.fields[$k] = ystr(doc.s[i ..< i + size])
        result.fields[$(k + 1)] = ystr("")
        k += 2
      else:
        result.fields[$k] = ystr(doc.s[i ..< i + size])
        inc k
      i += size
  else: discard

proc jsonQuote(s: string): string =
  result = "\""
  for ch in s:
    case ch
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    of '\b': result.add "\\b"
    of '\f': result.add "\\f"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    elif ord(ch) < 0x20: result.add "\\u" & toHex(ord(ch), 4).toLowerAscii
    else: result.add ch
  result.add '"'

func arrayIndex(key: string): int64 =
  ## The value of a key JavaScript orders as an array index, -1 for any other.
  if key.len == 0 or key.len > 10 or (key.len > 1 and key[0] == '0'): return -1
  for c in key:
    if c notin Digits: return -1
  let n = parseBiggestInt(key)
  if n < 4294967295'i64: n else: -1

proc jsonStringify(v: YamlValue): string =
  ## JSON.stringify of what YAML gives, with JavaScript's order of keys.
  if v == nil: return "undefined"
  case v.kind
  of yNull: "null"
  of yBool: (if v.b: "true" else: "false")
  of yNumber: (if v.n.isNaN or v.n == Inf or v.n == -Inf: "null" else: jsString(v.n))
  of yString: jsonQuote(v.s)
  of ySeq:
    var parts: seq[string]
    for it in v.items: parts.add(if it == nil: "null" else: jsonStringify(it))
    "[" & parts.join(",") & "]"
  of yMap:
    var indexed: seq[(int64, string)]
    var named: seq[string]
    for k in v.fields.keys:
      let n = arrayIndex(k)
      if n >= 0: indexed.add (n, k) else: named.add k
    indexed.sort()
    var parts: seq[string]
    for (_, k) in indexed: parts.add jsonQuote(k) & ":" & jsonStringify(v.fields[k])
    for k in named:
      if v.fields[k] != nil: parts.add jsonQuote(k) & ":" & jsonStringify(v.fields[k])
    "{" & parts.join(",") & "}"

func isJsSpaceNoNewline(s: string, i: int): bool = s[i] != '\n' and isJsSpaceAt(s, i)

proc blockScalarHeader(code: string): bool =
  ## /:\s*[>|][\d+-]*\s*$/.test(code)
  var k = code.len
  while k > 0 and isJsSpaceBefore(code, k): k = prevRuneStart(code, k)
  while k > 0 and code[k - 1] in {'0'..'9', '+', '-'}: dec k
  if k == 0 or code[k - 1] notin {'>', '|'}: return false
  dec k
  while k > 0 and isJsSpaceBefore(code, k): k = prevRuneStart(code, k)
  k > 0 and code[k - 1] == ':'

proc withoutTrailingComma(code: string): string =
  ## code.replace(/,([\t ]*)$/, '$1')
  var k = code.len
  while k > 0 and code[k - 1] in {'\t', ' '}: dec k
  if k > 0 and code[k - 1] == ',': code[0 ..< k - 1] & code[k .. ^1] else: code

proc indentOf(line: string): int = utf16Len(line) - utf16Len(line.jsTrimStart)

# Removes the comma that ends a line of a multi-line metadata body, which block YAML does not allow.
# Commas inside quoted scalars, flow collections and block scalars are content and stay.
proc stripLineTrailingCommas(body: string): string =
  var inSingle = false
  var inDouble = false
  var flowDepth = 0
  var blockScalarIndent = -1
  var output: seq[string]
  for line in body.split('\n'):
    if blockScalarIndent >= 0:
      let indent = indentOf(line)
      if line.jsTrim == "" or indent > blockScalarIndent:
        output.add line
        continue
      blockScalarIndent = -1
    var commentStart = -1
    var i = 0
    while i < line.len:
      let ch = line[i]
      if inDouble:
        if ch == '\\': inc i
        elif ch == '"': inDouble = false
      elif inSingle:
        if ch == '\'': inSingle = false
      elif ch == '"':
        inDouble = true
      elif ch == '\'':
        inSingle = true
      elif ch == '#' and (i == 0 or line[i - 1] == ' ' or line[i - 1] == '\t'):
        commentStart = i
        break
      elif ch == '[' or ch == '{':
        inc flowDepth
      elif ch == ']' or ch == '}':
        flowDepth = max(0, flowDepth - 1)
      inc i
    if inSingle or inDouble or flowDepth > 0:
      output.add line
      continue
    let code = if commentStart >= 0: line[0 ..< commentStart] else: line
    let comment = if commentStart >= 0: line[commentStart .. ^1] else: ""
    if blockScalarHeader(code):
      blockScalarIndent = indentOf(line)
      output.add line
      continue
    output.add withoutTrailingComma(code) & comment
  output.join("\n")

proc edgeSemanticOf(t, stroke: string): string =
  if t == "arrow_point" and stroke == "normal": return "sequence"
  if t == "arrow_cross" and stroke == "normal": return "failure"
  if t == "arrow_open" and stroke == "dotted": return "reference"
  ""

proc destructEndLink(raw: string): tuple[kind, stroke: string, length: int] =
  # A link token is ASCII, so a byte is a code unit here.
  let str = raw.jsTrim
  var line = str.substr(0, str.len - 2)
  var t = "arrow_open"
  case (if str.len > 0: str[^1] else: '\0')
  of 'x': t = "arrow_cross"
  of '>': t = "arrow_point"
  of '-', '.': line = str
  else: discard
  var stroke = "normal"
  var length = line.len - 1
  var dots = 0
  for c in line:
    if c == '.': inc dots
  if dots > 0:
    stroke = "dotted"
    length = dots
  (t, stroke, length)

type AgentflowDb* = ref object of RootObj
  direction*: string           ## "" for undefined
  nodes*: OrderedTable[string, AgentNode]
  edges*: seq[AgentEdge]
  subgraphs*: seq[AgentSubgraph]
  connectors*: OrderedTable[string, AgentNode]
  classes*: Table[string, AgentClassDef]
  tooltips*: Table[string, string]
  defaultEdgeStyle*: seq[string]  ## empty for undefined (only copied from)
  defaultInterpolate*: string     ## "" for undefined
  title*: string
  accTitle*: string
  accDescr*: string
  lineOffset*: int
  graph*: RootRef               ## the drawn graph, built once (Pele keeps it in a WeakMap)

  subgraphLookup: Table[string, AgentSubgraph]
  globalNodes: HashSet[string]
  members: HashSet[string]
  edgeById: Table[string, AgentEdge]
  pairCount: Table[string, int]
  subCount: int
  options: AgentflowDbOptions

proc newAgentflowDb*(options = AgentflowDbOptions()): AgentflowDb =
  AgentflowDb(options: options, lineOffset: options.lineOffset)

proc errorAt(db: AgentflowDb, loc: Option[Loc]): tuple[line, column: int] =
  if loc.isNone: return (0, 0)
  let l = loc.get
  if db.options.source.isNone: return (l.firstLine + db.lineOffset, l.firstColumn + 1)
  let source = db.options.source.get
  var start = 0
  for line in 1 ..< l.firstLine: start = source.find('\n', start) + 1
  let at = locate(source, unitOffset(source, start, l.firstColumn))
  (at.line, at.column)

proc metadata(db: AgentflowDb, id, source: string, loc: Option[Loc]): YamlValue =
  let multiline = '\n' in source
  var parsed: YamlValue
  try:
    parsed = parseYaml(if multiline: source & "\n" else: "{\n" & source & "\n}")
  except YamlError as error:
    # Block YAML rejects the comma-separated style of the single-line form, so try once more without the commas.
    let stripped = if multiline: stripLineTrailingCommas(source) else: source
    var retried: YamlValue = nil
    if stripped != source:
      try:
        retried = parseYaml(stripped & "\n")
      except YamlError:
        retried = nil
    if retried == nil:
      let (line, column) = db.errorAt(loc)
      let at = if loc.isSome: " (" & $line & ":" & $column & ")" else: ""
      raise newPeleError("Metadata of \"" & id & "\" is not valid YAML. " & error.msg & at, "syntax",
                         ErrorInfo(diagramType: "agentflow", line: line, column: column))
    parsed = retried
  stripPrototypeKeys(if parsed == nil or parsed.kind == yNull: ymap() else: parsed)

proc shapeError(db: AgentflowDb, message: string, loc: Option[Loc]): ref PeleError =
  let (line, column) = db.errorAt(loc)
  newPeleError(message, "semantic", ErrorInfo(diagramType: "agentflow", line: line, column: column))

proc addVertex*(db: AgentflowDb, id: string, textObj = none(FlowText), typ = "",
                style = none(seq[string]), props = none(Table[string, string]),
                metadata = none(string), metadataLoc = none(Loc)) =
  ## `typ` "" is undefined. Pele's `classes` and `dir` are never given here and are left out.
  if id.len == 0 or id.jsTrim.len == 0: return

  var doc: YamlValue = nil
  var fields: YamlValue = nil
  var authoredShape: YamlValue = nil
  if metadata.isSome:
    doc = db.metadata(id, metadata.get, metadataLoc)
    if isObject(doc):
      fields = doc
      let s = doc["shape"]
      if s != nil and s.kind == yString:
        authoredShape = s
        doc["shape"] = ystr(resolveShapeAlias(s.s))

  let hasDoc = truthy(doc)
  let subgraph = db.subgraphLookup.getOrDefault(id, nil)
  if subgraph != nil and hasDoc:
    subgraph.metadata = merge(subgraph.metadata, doc)
    return

  let connector = db.connectors.getOrDefault(id, nil)
  if connector != nil and hasDoc:
    connector.metadata = merge(connector.metadata, doc)
    return

  # Mermaid reserves this id and creates no node for it.
  if id == "connectors": return

  let edge = db.edgeById.getOrDefault(id, nil)
  if edge != nil:
    if fields != nil:
      if fields["animate"] != nil: edge.animate = fields["animate"]
      if fields["animation"] != nil: edge.animation = fields["animation"]
      if fields["curve"] != nil: edge.interpolate = jsStr(fields["curve"])
    if hasDoc: edge.metadata = merge(edge.metadata, doc)
    return

  var vertex = db.nodes.getOrDefault(id, nil)
  if vertex == nil:
    vertex = AgentNode(id: id, labelType: "text")
    db.nodes[id] = vertex

  if textObj.isSome:
    vertex.labelType = textObj.get.kind
    vertex.text = some(unquote(textObj.get.text.jsTrim))
  elif vertex.text.isNone:
    vertex.text = some(id)
  if typ != "": vertex.kind = typ
  if style.isSome:
    for s in style.get: vertex.styles.add s
  if props.isSome:
    for k, v in props.get: vertex.props[k] = v

  if not hasDoc: return
  vertex.metadata = merge(vertex.metadata, doc)
  if fields == nil: return

  if truthy(fields["shape"]):
    let authored = if authoredShape != nil: authoredShape else: fields["shape"]
    if authored.kind != yString:
      raise db.shapeError("No such shape: " & jsonStringify(authored) & ".", metadataLoc)
    if authored.s != unicode.toLower(authored.s) or '_' in authored.s:
      raise db.shapeError("No such shape: " & authored.s & ". Shape names should be lowercase.", metadataLoc)
    let shape = fields["shape"].s
    if not isValidShape(shape): raise db.shapeError("No such shape: " & shape & ".", metadataLoc)
    vertex.kind = shape
  if truthy(fields["label"]):
    vertex.text = some(jsStr(fields["label"]))
    vertex.labelType = labelTypeOf(fields["labelType"])

proc addSingleLink*(db: AgentflowDb, start, stop: string, info: Option[LinkInfo], id = "") =
  let edge = AgentEdge(start: start, stop: stop, text: "", labelType: "text",
                       isUserDefinedId: false, interpolate: db.defaultInterpolate, length: NO_LENGTH)
  if info.isSome and info.get.text.isSome:
    let linkText = info.get.text.get
    edge.text = unquote(linkText.text.jsTrim)
    edge.labelType = labelType(linkText.kind)
  if info.isSome:
    edge.kind = info.get.kind
    edge.stroke = info.get.stroke
    edge.length = if info.get.length != NO_LENGTH and info.get.length > 10: 10 else: info.get.length
    if info.get.edgeSemantic != "": edge.edgeSemantic = info.get.edgeSemantic
  let pair = start & "\0" & stop
  let count = db.pairCount.getOrDefault(pair, 0)
  if id != "" and not db.edgeById.hasKey(id):
    edge.id = id
    edge.isUserDefinedId = true
  else:
    edge.id = "L_" & start & "_" & stop & "_" & $(if count == 0: 0 else: count + 1)

  let max = db.options.maxEdges
  if max.isSome and db.edges.len >= max.get:
    raise newPeleError("Edge limit exceeded. The limit is " & $max.get & ".", "limit", "agentflow")
  db.edges.add edge
  db.pairCount[pair] = count + 1
  if not db.edgeById.hasKey(edge.id): db.edgeById[edge.id] = edge

proc addLink*(db: AgentflowDb, starts, ends: seq[string], linkData: Option[LinkInfo]) =
  # `linkData.id.replace('@', '')` replaces the first one.
  let id = if linkData.isSome and linkData.get.id != "": linkData.get.id.replaceFirst("@", "") else: ""
  let lastStart = starts[^1]
  let firstEnd = ends[0]
  for start in starts:
    for e in ends:
      db.addSingleLink(start, e, linkData, if start == lastStart and e == firstEnd: id else: "")

proc edgeAt(db: AgentflowDb, pos: string): AgentEdge =
  let n = jsNumber(pos)
  if n.isNaN or n < 0 or n != float(int(n)) or int(n) >= db.edges.len:
    raise newPeleError("The index " & pos & " for linkStyle is out of bounds. Valid indices for linkStyle are between 0 and " &
      $(db.edges.len - 1) & ". (Help: Ensure that the index is within the range of existing edges.)", "semantic", "agentflow")
  db.edges[int(n)]

proc updateLinkInterpolate*(db: AgentflowDb, positions: seq[string], interpolate: string) =
  for pos in positions:
    if pos == "default": db.defaultInterpolate = interpolate
    else: db.edgeAt(pos).interpolate = interpolate

proc updateLink*(db: AgentflowDb, positions: seq[string], styleIn: seq[string]) =
  # As in the flowchart: one array for every edge of the statement, `fill:none` pushed once.
  var style = styleIn
  for pos in positions:
    if pos == "default":
      db.defaultEdgeStyle = style
      continue
    let edge = db.edgeAt(pos)
    var anyFill = false
    for s in style:
      if s.startsWith("fill"): anyFill = true
    if style.len > 0 and not anyFill: style.add "fill:none"
    edge.style = style

proc addClass*(db: AgentflowDb, ids: string, styles: seq[string]) =
  let style = styles.join(",").replace("\\,", "§§§").replace(",", ";").replace("§§§", ",").split(';')
  for id in ids.split(','):
    var classNode = db.classes.getOrDefault(id, nil)
    if classNode == nil:
      classNode = AgentClassDef(id: id)
      db.classes[id] = classNode
    for s in style:
      if "color" in s: classNode.textStyles.add s.replaceFirst("fill", "bgFill")
      classNode.styles.add s

proc setDirection*(db: AgentflowDb, dir: string) =
  var d = dir.jsTrim
  if '<' in d: d = "RL"
  if '^' in d: d = "BT"
  if '>' in d: d = "LR"
  if 'v' in d: d = "TB"
  if d == "TD": d = "TB"
  db.direction = d

proc setClass*(db: AgentflowDb, ids, className: string) =
  for id in ids.split(','):
    if db.nodes.hasKey(id): db.nodes[id].classes.add className
    if db.edgeById.hasKey(id): db.edgeById[id].classes.add className
    if db.subgraphLookup.hasKey(id): db.subgraphLookup[id].classes.add className

proc setTooltip*(db: AgentflowDb, ids: string, tooltip: Option[string]) =
  if tooltip.isNone: return
  for id in ids.split(','): db.tooltips[id] = tooltip.get

proc setLink*(db: AgentflowDb, ids, link: string, target = "") =
  let url = link.jsTrim
  for id in ids.split(','):
    let vertex = db.nodes.getOrDefault(id, nil)
    if vertex != nil:
      vertex.link = if url != "": safeUrl(url) else: ""
      vertex.linkTarget = target
  db.setClass(ids, "clickable")

proc setClickEvent*(db: AgentflowDb, ids: string, functionName = "", functionArgs = "") =
  db.setClass(ids, "clickable")

proc setAccTitle*(db: AgentflowDb, text: string) =
  db.accTitle = text.jsTrimStart

proc setAccDescription*(db: AgentflowDb, text: string) =
  db.accDescr = text.replace(jsre"/\n\s+/g", "\n")

proc addSubGraph*(db: AgentflowDb, idText: Option[FlowText], list: seq[DocItem],
                  titleText: Option[FlowText]): string =
  ## Pele's `idText === titleText` never holds here: a flow's title is always an object of its own.
  var id = if idText.isSome: idText.get.text.jsTrim else: ""
  let hasId = idText.isSome
  let title = if titleText.isSome: titleText.get.text else: ""

  var seen = initHashSet[string]()
  var nodeList: seq[string]
  var dir = ""
  for entry in list:
    case entry.kind
    of dkString:
      if entry.s.jsTrim != "" and entry.s notin seen:
        seen.incl entry.s
        nodeList.add entry.s
    of dkList:
      for item in entry.items:
        if item.jsTrim != "" and item notin seen:
          seen.incl item
          nodeList.add item
    of dkDir:
      dir = entry.value
  if dir == "" and db.options.inheritDir:
    dir = if db.direction != "": db.direction else: db.options.direction

  if not hasId: id = "subGraph" & $db.subCount
  inc db.subCount

  var nodes: seq[string]
  for nodeId in nodeList:
    if nodeId != id and nodeId notin db.globalNodes and nodeId notin db.members: nodes.add nodeId
  for nodeId in nodes: db.members.incl nodeId

  let existing = db.subgraphLookup.getOrDefault(id, nil)
  if existing != nil:
    for nodeId in nodes: existing.nodes.add nodeId
    if title.jsTrim != "": existing.title = title.jsTrim
    if dir != "": existing.dir = dir
    return id
  let subgraph = AgentSubgraph(id: id, nodes: nodes, title: title.jsTrim, dir: dir,
                               labelType: labelType(if titleText.isSome: titleText.get.kind else: ""))
  db.subgraphs.add subgraph
  db.subgraphLookup[id] = subgraph
  id

proc addGlobal*(db: AgentflowDb, list: seq[DocItem]) =
  var release = false
  proc add(item: string) =
    let id = item.jsTrim
    if id == "": return
    db.globalNodes.incl id
    if id in db.members:
      db.members.excl id
      release = true
  for entry in list:
    case entry.kind
    of dkString: add(entry.s)
    of dkList:
      for item in entry.items: add(item)
    of dkDir: discard
  if not release: return
  for subgraph in db.subgraphs:
    var kept: seq[string]
    for nodeId in subgraph.nodes:
      if nodeId notin db.globalNodes: kept.add nodeId
    subgraph.nodes = kept

proc addConnector*(db: AgentflowDb, textObj: FlowText, titleObj: FlowText): string =
  let id = textObj.text.jsTrim
  if id == "": return ""
  let title = titleObj.text.jsTrim
  let connector = db.connectors.getOrDefault(id, nil)
  if connector == nil:
    let created = AgentNode(id: id, labelType: "text", isConnector: true,
                            text: some(if title.len > 0: title else: id))
    db.connectors[id] = created
    db.nodes[id] = created
  elif title.len > 0:
    connector.text = some(title)
  id

proc destructLink*(db: AgentflowDb, stop: string, start = ""): LinkInfo =
  ## `start` "" is undefined.
  let info = destructEndLink(stop)
  if start != "":
    let stroke = if '.' in start: "dotted" else: "normal"
    if stroke != info.stroke: return LinkInfo(kind: "INVALID", stroke: "INVALID", length: NO_LENGTH)
  LinkInfo(kind: info.kind, stroke: info.stroke, length: info.length,
           edgeSemantic: edgeSemanticOf(info.kind, info.stroke))

proc subgraph*(db: AgentflowDb, id: string): AgentSubgraph =
  ## nil when there is none.
  db.subgraphLookup.getOrDefault(id, nil)

proc vertexKind*(db: AgentflowDb, vertex: AgentNode): string =
  if isToolDefinition(vertex): return "tool"
  let shape = resolveShapeAlias(vertex.kind)
  if shape == "hexagon" or shape == "hex": return "action"
  if shape == "lean-right" or shape == "lean_right": return "input"
  if shape == "lin-doc" or shape == "lined-document": return "refdoc"
  if shape == "diamond": return "decision"
  "task"
