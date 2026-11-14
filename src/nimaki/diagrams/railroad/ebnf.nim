## port-of: src/diagrams/railroad/ebnf.ts
## port-status: conformant
##
## `railroad-ebnf-beta`: EBNF in the W3C and ISO 14977 styles.
import ../../js
import common, types
import ../../jsregex

const
  # const enum T: the index of each token type in EBNF_TOKENS
  T_keyword = 0
  T_defines = 1
  T_equals = 2
  T_semicolon = 3
  T_bar = 4
  T_comma = 5
  T_group = 6
  T_option = 8
  T_repeat = 10
  T_question = 12
  T_star = 13
  T_plus = 14
  T_minus = 15
  T_title = 16
  T_id = 19
  T_string = 20
  T_special = 21

func specialSequence(src: string, at: int): int =
  ## A question mark, text with something other than blanks in it and no `?` or `;`, and a question mark.
  ## Mermaid's pattern looks ahead with two nested runs, which rescans; this reads the text once.
  ## /\?(?=[^?;]*[^?\s;][^?;]*\?)[^?;]*\?/y
  if at >= src.len or src[at] != '?': return -1
  var solid = false
  var i = at + 1
  while i < src.len:
    let c = src[i]
    if c == '?': return (if solid: i + 1 else: -1)
    if c == ';': return -1
    let n = spaceLenAt(src, i)
    if n > 0:
      i += n
    else:
      solid = true
      i += codePointAt(src, i).size
  -1

let ID = identifier("EBNF_ID")
let SPECIAL = TokenType(name: "EBNF_SPECIAL_SEQUENCE", pattern: jsre"/\?(?=[^?;]*[^?\s;][^?;]*\?)[^?;]*\?/y",
                        first: "?", hasFirst: true,
                        scanner: proc (): Scanner =
                          proc (src: string, at: int, previous: int): int = specialSequence(src, at))
let HIDDEN = hiddenTokens("EBNF")
let ISO_COMMENT = TokenType(name: "EBNF_ISO_COMMENT", pattern: jsre"/\(\*[\s\S]*?\*\)/y", hidden: true,
                            first: "(", hasFirst: true, opener: jsre"/\(\*/y")

let EBNF_TOKENS*: seq[TokenType] = @[
  opening("railroad-ebnf-beta", ID),
  literal("::="),
  literal("="),
  literal(";"),
  literal("|"),
  literal(","),
  literal("(", @[ISO_COMMENT]),
  literal(")"),
  literal("["),
  literal("]"),
  literal("{"),
  literal("}"),
  literal("?", @[SPECIAL]),
  literal("*"),
  literal("+"),
  literal("-", @[HIDDEN[1]]),
  title(r"[\w-]"),
  ACC_TITLE,
  ACC_DESCR,
  ID,
  quoted("EBNF_STRING"),
  SPECIAL,
] & HIDDEN & @[
  TokenType(name: "EBNF_BLOCK_COMMENT", pattern: jsre"/\/\*[\s\S]*?\*\//y", hidden: true, first: "/", hasFirst: true,
            opener: jsre"/\/\*/y"),
  ISO_COMMENT,
]

type Frame = ref object
  ## One open bracket, or the rule itself at the bottom of the stack.
  choice: Part
  sequence: Part
  term: Part              ## nil for undefined
  node: Part              ## the bracket's node
  close: int              ## its closing token
  exception: bool            ## whether it is the right side of an exception

proc frame(node: Part, choice: Part, close: int, isExcept: bool): Frame =
  let sequence = Part(kind: "EbnfSequence")
  choice.kids.add sequence
  Frame(choice: choice, sequence: sequence, node: node, close: close, exception: isExcept)

const BRACKETS = ["EbnfGroup", "EbnfOptional", "EbnfRepetition"]

proc definition(r: Reader): Part =
  var stack: seq[Frame]
  var top = frame(nil, Part(kind: "EbnfChoice"), -2, false)
  var isExcept = false
  while true:
    var primary: Part
    let kind = r.kind
    case kind
    of T_string: primary = Part(kind: "EbnfTerminal", text: unescape(r.take()))
    of T_id: primary = Part(kind: "EbnfNonTerminal", text: r.take())
    of T_special:
      let text = r.take()
      primary = Part(kind: "EbnfSpecial", text: jsTrim(text[1 ..< text.len - 1]))
    of T_group, T_option, T_repeat:
      inc r.i
      let element = Part(kind: "EbnfChoice")
      stack.add top
      top = frame(Part(kind: BRACKETS[(kind - T_group) shr 1], kids: @[element]), element, kind + 1, isExcept)
      isExcept = false
      continue
    else: r.fail("a terminal, a name, or an opening bracket")
    while true:
      if isExcept:
        top.term.postfixes.add "EbnfExceptionPostfix"
        top.term.kids.add primary
        isExcept = false
      else:
        top.term = Part(kind: "EbnfTerm", kids: @[primary])
        top.sequence.kids.add top.term
      let term = top.term
      while true:
        let k = r.kind
        if k == T_question: term.postfixes.add "EbnfOptionalPostfix"
        elif k == T_star: term.postfixes.add "EbnfZeroOrMorePostfix"
        elif k == T_plus: term.postfixes.add "EbnfOneOrMorePostfix"
        else: break
        inc r.i
      let k = r.kind
      if k == top.close:
        inc r.i
        primary = top.node
        isExcept = top.exception
        top = stack.pop()
        continue
      if k == T_minus:
        inc r.i
        isExcept = true
      elif k == T_comma:
        inc r.i
      elif k == T_bar:
        inc r.i
        top.sequence = Part(kind: "EbnfSequence")
        top.choice.kids.add top.sequence
      elif k notin [T_string, T_id, T_special, T_group, T_option, T_repeat]:
        if stack.len == 0: return top.choice
        r.fail("token of type '" & EBNF_TOKENS[top.close].name & "'")
      break

proc parseEbnf*(src: string): Grammar =
  parseGrammar(src, EBNF_TOKENS, T_title, unescape, proc (r: Reader): RuleAst =
    let name = r.expect(T_id)
    if not r.accept(T_equals): discard r.expect(T_defines)
    result = RuleAst(name: name, definition: definition(r))
    discard r.expect(T_semicolon))

proc node(part: Part, kids: seq[RailroadNode]): RailroadNode =
  case part.kind
  of "EbnfChoice": choice(kids)
  of "EbnfSequence": sequence(kids)
  of "EbnfTerm":
    # Each postfix operator applies to everything before it in the term.
    var value = kids[0]
    var next = 1
    for postfix in part.postfixes:
      if postfix == "EbnfOptionalPostfix": value = optional(value)
      elif postfix == "EbnfExceptionPostfix":
        value = RailroadNode(kind: nkSequence, kids: @[value, terminal("-"), kids[next]])
        inc next
      else: value = repetition(value, if postfix == "EbnfOneOrMorePostfix": 1 else: 0)
    value
  of "EbnfTerminal": terminal(part.text)
  of "EbnfNonTerminal": nonterminal(part.text)
  of "EbnfSpecial": special(part.text)
  of "EbnfGroup": kids[0]
  of "EbnfOptional": optional(kids[0])
  else: repetition(kids[0], 0)

proc ebnfRules*(ast: Grammar): seq[RailroadRule] = toRules(ast, node)
