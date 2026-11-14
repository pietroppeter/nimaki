## port-of: src/diagrams/treemap/parser.ts
## port-status: draft
import std/strutils
import ../common/tokens
import ../../js

const
  # const enum T: the index of each token type in TREEMAP_TOKENS
  T_accDescr = 0
  T_accTitle = 1
  T_title = 2
  T_keyword = 3
  T_classDef = 4
  T_styleSeparator = 5
  T_separator = 6
  T_comma = 7
  T_indentation = 8
  T_whitespace = 9
  T_comment = 10
  T_newline = 11
  T_id = 12
  T_number = 13
  T_string = 14

func isIdStart(c: char): bool = c in {'a'..'z', 'A'..'Z', '_'}
func isIdChar(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func classDefParts(s: string, p: int): tuple[stop, nameStart, nameEnd, styleStart, styleEnd: int] =
  ## /classDef\s+([a-zA-Z_][a-zA-Z0-9_]+)(?:\s+([^;\r\n]*))?(?:;)?/y: where it ends (-1 for no
  ## match), the class name, and the style text (styleStart -1 when the group did not match).
  ## `\s` takes line breaks too.
  result = (-1, 0, 0, -1, -1)
  if not s.continuesWith("classDef", p): return
  var i = p + 8
  let spaces = i
  while true:
    let n = spaceLenAt(s, i)
    if n == 0: break
    i += n
  if i == spaces: return
  if not (i + 1 < s.len and isIdStart(s[i]) and isIdChar(s[i + 1])): return
  let nameStart = i
  i += 2
  while i < s.len and isIdChar(s[i]): inc i
  result.nameStart = nameStart
  result.nameEnd = i
  var j = i
  while true:
    let n = spaceLenAt(s, j)
    if n == 0: break
    j += n
  if j > i:
    var k = j
    while k < s.len and s[k] notin {';', '\r', '\n'}: inc k
    result.styleStart = j
    result.styleEnd = k
    i = k
  if i < s.len and s[i] == ';': inc i
  result.stop = i

func matchKeyword(s: string, p: int): int =
  ## /treemap-beta|treemap/y
  if s.continuesWith("treemap-beta", p): p + 12
  elif s.continuesWith("treemap", p): p + 7
  else: -1

func matchClassDef(s: string, p: int): int = classDefParts(s, p).stop

func matchLiteral(text: string): Matcher =
  result = proc (s: string, p: int): int {.noSideEffect.} =
    if s.continuesWith(text, p): p + text.len else: -1

func matchBlanks(s: string, p: int): int =
  ## /[ \t]{1,}/y
  var i = p
  while i < s.len and s[i] in {' ', '\t'}: inc i
  if i > p: i else: -1

func matchComment(s: string, p: int): int =
  ## /\%\%[^\n]*/y
  if not s.continuesWith("%%", p): return -1
  var i = p + 2
  while i < s.len and s[i] != '\n': inc i
  i

func matchNewline(s: string, p: int): int =
  ## /\r?\n/y
  if s.continuesWith("\r\n", p): p + 2
  elif p < s.len and s[p] == '\n': p + 1
  else: -1

func matchId(s: string, p: int): int =
  ## /[a-zA-Z_][a-zA-Z0-9_]*/y
  if p >= s.len or not isIdStart(s[p]): return -1
  var i = p + 1
  while i < s.len and isIdChar(s[i]): inc i
  i

func matchNumber(s: string, p: int): int =
  ## /[0-9_\.\,]+/y
  var i = p
  while i < s.len and s[i] in {'0'..'9', '_', '.', ','}: inc i
  if i > p: i else: -1

func matchString(s: string, p: int): int =
  ## /"[^"]*"|'[^']*'/y
  if p >= s.len or s[p] notin {'"', '\''}: return -1
  let close = s.find(s[p], p + 1)
  if close == -1: -1 else: close + 1

# Mermaid's treemap grammar has its own terminals. Every run of spaces or tabs is an INDENTATION
# token, since that comes before WS, and line breaks are hidden, so rows are told apart by their
# tokens alone and the indentation of a row is whatever whitespace precedes it.
let TREEMAP_TOKENS*: seq[TokenType] = @[
  ACC_DESCR,
  ACC_TITLE,
  titleBefore(r"\w"),
  TokenType(name: "TREEMAP_KEYWORD", matcher: matchKeyword),
  TokenType(name: "CLASS_DEF", matcher: matchClassDef),
  TokenType(name: "STYLE_SEPARATOR", matcher: matchLiteral(":::")),
  TokenType(name: "SEPARATOR", matcher: matchLiteral(":")),
  TokenType(name: "COMMA", matcher: matchLiteral(",")),
  TokenType(name: "INDENTATION", matcher: matchBlanks),
  TokenType(name: "WS", matcher: matchBlanks, hidden: true),
  TokenType(name: "ML_COMMENT", matcher: matchComment, hidden: true),
  TokenType(name: "NL", matcher: matchNewline, hidden: true),
  TokenType(name: "ID2", matcher: matchId),
  TokenType(name: "NUMBER2", matcher: matchNumber),
  TokenType(name: "STRING2", matcher: matchString),
]

type
  TreemapItemAst* = object
    leaf*: bool          ## Pele's $type: 'Leaf' or 'Section'
    name*: string
    value*: float        ## a leaf's
    classSelector*: string   ## "" for undefined

  TreemapRowAst* = object
    classDef*: bool      ## Pele's $type: 'ClassDefStatement' or 'TreemapRow'
    indent*: int
    hasIndent*: bool
    item*: TreemapItemAst
    className*: string
    styleText*: string   ## "" for undefined

  TreemapAst* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    rows*: seq[TreemapRowAst]              ## Pele's TreemapRows

proc parseTreemap*(src: string): TreemapAst =
  let r = newReader(tokenize(src, TREEMAP_TOKENS, "treemap"), TREEMAP_TOKENS, "treemap")
  let kinds = r.kinds
  var ast = TreemapAst()

  proc classSelector(): string = (if r.accept(T_styleSeparator): r.expect(T_id) else: "")

  discard r.expect(T_keyword)
  while r.kind != -1:
    let kind = r.kind
    if kind == T_accDescr:
      ast.accDescr = accDescrValue(r.take())
      continue
    if kind == T_accTitle:
      ast.accTitle = accTitleValue(r.take())
      continue
    if kind == T_title:
      ast.title = titleValue(r.take())
      continue
    if kind != T_indentation and kind != T_string and kind != T_classDef:
      r.fail("a node, a class definition, or a title")

    let hasIndent = kind == T_indentation
    let indent = if hasIndent: r.take().len else: 0
    if r.kind == T_classDef:
      # RE_CLASS_DEF: /classDef\s+([A-Z_a-z]\w+)(?:\s+([^\n\r;]*))?;?/ on the token
      let text = r.take()
      let m = classDefParts(text, 0)
      var row = TreemapRowAst(classDef: true, className: text[m.nameStart ..< m.nameEnd])
      if m.styleStart >= 0 and m.styleEnd > m.styleStart: row.styleText = text[m.styleStart ..< m.styleEnd]
      row.indent = indent
      row.hasIndent = hasIndent
      ast.rows.add row
      continue

    let quoted = r.expect(T_string)
    let name = quoted[1 ..< quoted.len - 1]
    # A leaf is a name followed by a colon or comma, with or without whitespace before it.
    let after = if kinds[r.i] == T_indentation: r.i + 1 else: r.i
    var item: TreemapItemAst
    if kinds[after] == T_separator or kinds[after] == T_comma:
      r.i = after + 1
      discard r.accept(T_indentation)
      item = TreemapItemAst(leaf: true, name: name, value: jsParseFloat(r.expect(T_number).replace(",", "")))
    else:
      item = TreemapItemAst(leaf: false, name: name)
    item.classSelector = classSelector()
    ast.rows.add TreemapRowAst(item: item, indent: indent, hasIndent: hasIndent)
  ast
