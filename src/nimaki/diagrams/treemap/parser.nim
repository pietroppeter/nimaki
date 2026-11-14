## port-of: src/diagrams/treemap/parser.ts
## port-status: conformant
import ../common/tokens
import ../../js
import ../../jsregex

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

const RE_CLASS_DEF = jsre"/classDef\s+([A-Z_a-z]\w+)(?:\s+([^\n\r;]*))?;?/"

# Mermaid's treemap grammar has its own terminals. Every run of spaces or tabs is an INDENTATION
# token, since that comes before WS, and line breaks are hidden, so rows are told apart by their
# tokens alone and the indentation of a row is whatever whitespace precedes it.
let TREEMAP_TOKENS*: seq[TokenType] = @[
  ACC_DESCR,
  ACC_TITLE,
  titleBefore(r"\w"),
  TokenType(name: "TREEMAP_KEYWORD", pattern: jsre"/treemap-beta|treemap/y"),
  TokenType(name: "CLASS_DEF", pattern: jsre"/classDef\s+([a-zA-Z_][a-zA-Z0-9_]+)(?:\s+([^;\r\n]*))?(?:;)?/y"),
  TokenType(name: "STYLE_SEPARATOR", pattern: jsre"/:::/y"),
  TokenType(name: "SEPARATOR", pattern: jsre"/:/y"),
  TokenType(name: "COMMA", pattern: jsre"/,/y"),
  TokenType(name: "INDENTATION", pattern: jsre"/[ \t]{1,}/y"),
  TokenType(name: "WS", pattern: jsre"/[ \t]+/y", hidden: true),
  TokenType(name: "ML_COMMENT", pattern: jsre"/\%\%[^\n]*/y", hidden: true),
  TokenType(name: "NL", pattern: jsre"/\r?\n/y", hidden: true),
  TokenType(name: "ID2", pattern: jsre"/[a-zA-Z_][a-zA-Z0-9_]*/y"),
  TokenType(name: "NUMBER2", pattern: jsre"/[0-9_\.\,]+/y"),
  TokenType(name: "STRING2", pattern: jsre"""/"[^"]*"|'[^']*'/y"""),
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
      let m = RE_CLASS_DEF.exec(r.take())
      var row = TreemapRowAst(classDef: true, className: m[1])
      if m[2] != "": row.styleText = m[2]
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
      item = TreemapItemAst(leaf: true, name: name, value: jsParseFloat(r.expect(T_number).replace(jsre"/,/g", "")))
    else:
      item = TreemapItemAst(leaf: false, name: name)
    item.classSelector = classSelector()
    ast.rows.add TreemapRowAst(item: item, indent: indent, hasIndent: hasIndent)
  ast
