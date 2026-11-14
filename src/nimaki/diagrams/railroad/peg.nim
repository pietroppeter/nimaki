## port-of: src/diagrams/railroad/peg.ts
## port-status: conformant
##
## `railroad-peg-beta`: parsing expression grammars.
import common, types
import ../../jsregex

const
  # const enum T: the index of each token type in PEG_TOKENS
  T_keyword = 0
  T_arrow = 1
  T_semicolon = 2
  T_slash = 3
  T_and = 4
  T_not = 5
  T_question = 6
  T_star = 7
  T_plus = 8
  T_group = 9
  T_groupEnd = 10
  T_dot = 11
  T_title = 12
  T_id = 15
  T_string = 16

let ID = identifier("PEG_ID")

let PEG_TOKENS*: seq[TokenType] = @[
  opening("railroad-peg-beta", ID),
  literal("<-"),
  literal(";"),
  literal("/"),
  literal("&"),
  literal("!"),
  literal("?"),
  literal("*"),
  literal("+"),
  literal("("),
  literal(")"),
  literal("."),
  title(r"[\w-]"),
  ACC_TITLE,
  ACC_DESCR,
  ID,
  quoted("PEG_STRING"),
] & hiddenTokens("PEG") & @[
  TokenType(name: "PEG_LINE_COMMENT", pattern: jsre"/#[^\n\r]*/y", hidden: true, first: "#", hasFirst: true),
]

type Frame = ref object
  ## One open group, or the rule itself at the bottom of the stack.
  choice: Part
  sequence: Part
  node: Part        ## the group's node
  operator: string  ## the predicate written before it ("" for undefined)

proc frame(node: Part, choice: Part, operator: string): Frame =
  let sequence = Part(kind: "PegSequence")
  choice.kids.add sequence
  Frame(choice: choice, sequence: sequence, node: node, operator: operator)

proc definition(r: Reader): Part =
  var stack: seq[Frame]
  var top = frame(nil, Part(kind: "PegOrderedChoice"), "")
  while true:
    var operator = if r.kind == T_and or r.kind == T_not: r.take() else: ""
    var primary: Part
    case r.kind
    of T_string: primary = Part(kind: "PegLiteral", text: unescape(r.take()))
    of T_id: primary = Part(kind: "PegIdentifier", text: r.take())
    of T_dot: primary = Part(kind: "PegAny", text: r.take())
    of T_group:
      inc r.i
      let element = Part(kind: "PegOrderedChoice")
      stack.add top
      top = frame(Part(kind: "PegGroup", kids: @[element]), element, operator)
      continue
    else: r.fail("a literal, a name, a dot, or an opening parenthesis")
    while true:
      let suffix = Part(kind: "PegSuffix", kids: @[primary])
      if r.kind == T_question or r.kind == T_star or r.kind == T_plus: suffix.text = r.take()
      top.sequence.kids.add Part(kind: "PegPrefix", text: operator, kids: @[suffix])
      let k = r.kind
      if k == T_groupEnd and stack.len > 0:
        inc r.i
        primary = top.node
        operator = top.operator
        top = stack.pop()
        continue
      if k == T_slash:
        inc r.i
        top.sequence = Part(kind: "PegSequence")
        top.choice.kids.add top.sequence
      elif k notin [T_and, T_not, T_string, T_id, T_dot, T_group]:
        if stack.len == 0: return top.choice
        r.fail("token of type ')'")
      break

proc parsePeg*(src: string): Grammar =
  parseGrammar(src, PEG_TOKENS, T_title, unescape, proc (r: Reader): RuleAst =
    let name = r.expect(T_id)
    discard r.expect(T_arrow)
    result = RuleAst(name: name, definition: definition(r))
    discard r.expect(T_semicolon))

proc label(node: RailroadNode): string =
  ## What a predicate shows of the expression it looks ahead for.
  case node.kind
  of nkTerminal: "\"" & node.text & "\""
  of nkNonterminal, nkSpecial: node.text
  else: "(...)"

proc node(part: Part, kids: seq[RailroadNode]): RailroadNode =
  let kid = if kids.len > 0: kids[0] else: nil
  case part.kind
  of "PegOrderedChoice": choice(kids)
  of "PegSequence": sequence(kids)
  of "PegPrefix": (if part.text != "": special(part.text & label(kid)) else: kid)
  of "PegSuffix":
    if part.text == "": kid
    elif part.text == "?": optional(kid)
    else: repetition(kid, if part.text == "+": 1 else: 0)
  of "PegLiteral": terminal(part.text)
  of "PegIdentifier": nonterminal(part.text)
  of "PegAny": special(part.text)
  else: kid

proc pegRules*(ast: Grammar): seq[RailroadRule] = toRules(ast, node)
