## port-of: src/diagrams/railroad/ir.ts
## port-status: draft
##
## `railroad-beta`: Mermaid's own notation, one constructor call per node.
import common, types

const
  # const enum T: the index of each token type in IR_TOKENS
  T_keyword = 0
  T_nonterminal = 1
  T_zeroOrMore = 2
  T_oneOrMore = 3
  T_sequence = 4
  T_optional = 5
  T_terminal = 6
  T_special = 7
  T_choice = 8
  T_equals = 9
  T_semicolon = 10
  T_open = 11
  T_comma = 12
  T_close = 13
  T_title = 14
  T_id = 17
  T_string = 18

let ID = identifier("RR_ID")
proc word(name: string): TokenType = literal(name, @[ID])

let IR_TOKENS*: seq[TokenType] = @[
  opening("railroad-beta", ID),
  word("nonterminal"),
  word("zeroOrMore"),
  word("oneOrMore"),
  word("sequence"),
  word("optional"),
  word("terminal"),
  word("special"),
  word("choice"),
  literal("="),
  literal(";"),
  literal("("),
  literal(","),
  literal(")"),
  title(wordRest),
  ACC_TITLE,
  ACC_DESCR,
  ID,
  quoted("RR_STRING"),
] & hiddenTokens("RR") & @[
  between("RR_BLOCK_COMMENT", "/*", "*/", "/"),
]

proc argument(r: Reader): string =
  inc r.i
  discard r.expect(T_open)
  let value = unescape(r.expect(T_string))
  discard r.expect(T_close)
  value

func isParent(e: Part): bool =
  ## 'elements' in value || 'alternatives' in value || 'element' in value
  e.kind notin ["RailroadTerminalExpr", "RailroadNonTerminalExpr", "RailroadSpecialExpr"]

func holdsOne(e: Part): bool =
  ## 'element' in parent
  e.kind in ["RailroadOptionalExpr", "RailroadOneOrMoreExpr", "RailroadZeroOrMoreExpr"]

proc expression(r: Reader): Part =
  var open: seq[Part]
  while true:
    var value: Part
    case r.kind
    of T_terminal: value = Part(kind: "RailroadTerminalExpr", text: argument(r))
    of T_nonterminal: value = Part(kind: "RailroadNonTerminalExpr", text: argument(r))
    of T_special: value = Part(kind: "RailroadSpecialExpr", text: argument(r))
    of T_sequence: value = Part(kind: "RailroadSequenceExpr")
    of T_choice: value = Part(kind: "RailroadChoiceExpr")
    of T_optional: value = Part(kind: "RailroadOptionalExpr")
    of T_oneOrMore: value = Part(kind: "RailroadOneOrMoreExpr")
    of T_zeroOrMore: value = Part(kind: "RailroadZeroOrMoreExpr")
    else: r.fail("an expression")
    if value.isParent:
      inc r.i
      discard r.expect(T_open)
      open.add value
      continue
    while true:
      if open.len == 0: return value
      let parent = open[^1]
      if parent.holdsOne:
        parent.kids = @[value]
      else:
        parent.kids.add value
        if r.accept(T_comma): break
      discard r.expect(T_close)
      discard open.pop()
      value = parent

proc parseIr*(src: string): Grammar =
  parseGrammar(src, IR_TOKENS, T_title, unescape, proc (r: Reader): RuleAst =
    let name = r.expect(T_id)
    discard r.expect(T_equals)
    let definition = expression(r)
    discard r.expect(T_semicolon)
    RuleAst(name: name, definition: definition))

proc node(e: Part, kids: seq[RailroadNode]): RailroadNode =
  case e.kind
  of "RailroadTerminalExpr": terminal(e.text)
  of "RailroadNonTerminalExpr": nonterminal(e.text)
  of "RailroadSpecialExpr": special(e.text)
  of "RailroadSequenceExpr": sequence(kids)
  of "RailroadChoiceExpr": choice(kids)
  of "RailroadOptionalExpr": optional(kids[0])
  else: repetition(kids[0], if e.kind == "RailroadOneOrMoreExpr": 1 else: 0)

proc irRules*(ast: Grammar): seq[RailroadRule] = toRules(ast, node)
