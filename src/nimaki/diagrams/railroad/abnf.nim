## port-of: src/diagrams/railroad/abnf.ts
## port-status: conformant
##
## `railroad-abnf-beta`: ABNF as in RFC 5234, with each rule closed by a semicolon.
import std/strutils except unescape
import ../../js
import common, types
import ../../jsregex

const
  # const enum T: the index of each token type in ABNF_TOKENS
  T_keyword = 0
  T_equals = 1
  T_semicolon = 2
  T_slash = 3
  T_group = 4
  T_option = 6
  T_title = 8
  T_name = 11
  T_string = 12
  T_number = 13
  T_repeat = 14
  T_exact = 15

const DIGITS = "0123456789"

let NAME = TokenType(name: "ABNF_RULENAME", pattern: jsre"/[A-Za-z][A-Za-z0-9-]*/y", first: LETTERS, hasFirst: true)
let COMMENT = TokenType(name: "ABNF_COMMENT", pattern: jsre"/;[^\n\r]*/y", hidden: true, first: ";", hasFirst: true)

let ABNF_TOKENS*: seq[TokenType] = @[
  opening("railroad-abnf-beta", NAME),
  literal("="),
  # A semicolon closes a rule only at the end of its line; with anything after it, it starts a comment.
  literal(";", @[COMMENT]),
  literal("/"),
  literal("("),
  literal(")"),
  literal("["),
  literal("]"),
  title(r"[A-Za-z0-9-]"),
  ACC_TITLE,
  ACC_DESCR,
  NAME,
  TokenType(name: "ABNF_STRING", pattern: jsre"""/"[^"]*"/y""", first: "\"", hasFirst: true),
  TokenType(name: "ABNF_NUMVAL", pattern: jsre"/%[xXdDbB][0-9A-Fa-f]+(?:-[0-9A-Fa-f]+|\.[0-9A-Fa-f]+)*/y", first: "%", hasFirst: true),
  TokenType(name: "ABNF_REPEAT", pattern: jsre"/[0-9]*\*[0-9]*/y", first: DIGITS & "*", hasFirst: true),
  TokenType(name: "ABNF_EXACT_REPEAT", pattern: jsre"/[0-9]+/y", first: DIGITS, hasFirst: true),
] & hiddenTokens("ABNF") & @[COMMENT]

type Frame = ref object
  ## One open bracket, or the rule itself at the bottom of the stack.
  alternation: Part
  concatenation: Part
  node: Part      ## the bracket's node
  close: int      ## its closing token
  repeat: string  ## the repeat written before it ("" for undefined)

proc frame(node: Part, alternation: Part, close: int, repeat: string): Frame =
  let concatenation = Part(kind: "AbnfConcatenation")
  alternation.kids.add concatenation
  Frame(alternation: alternation, concatenation: concatenation, node: node, close: close, repeat: repeat)

proc alternation(r: Reader): Part =
  var stack: seq[Frame]
  var top = frame(nil, Part(kind: "AbnfAlternation"), -2, "")
  while true:
    var repeat = if r.kind == T_repeat or r.kind == T_exact: r.take() else: ""
    var primary: Part
    let kind = r.kind
    case kind
    of T_string:
      let text = r.take()
      primary = Part(kind: "AbnfStringLiteral", text: text[1 ..< text.len - 1])
    of T_number: primary = Part(kind: "AbnfNumVal", text: r.take())
    of T_name: primary = Part(kind: "AbnfRuleName", text: r.take())
    of T_group, T_option:
      inc r.i
      let element = Part(kind: "AbnfAlternation")
      stack.add top
      top = frame(Part(kind: (if kind == T_group: "AbnfGroup" else: "AbnfOptionalGroup"), kids: @[element]),
                  element, kind + 1, repeat)
      continue
    else: r.fail("a string, a number, a name, or an opening bracket")
    while true:
      top.concatenation.kids.add Part(kind: "AbnfElement", text: repeat, kids: @[primary])
      let k = r.kind
      if k == top.close:
        inc r.i
        primary = top.node
        repeat = top.repeat
        top = stack.pop()
        continue
      if k == T_slash:
        inc r.i
        top.concatenation = Part(kind: "AbnfConcatenation")
        top.alternation.kids.add top.concatenation
      elif k notin [T_string, T_number, T_name, T_group, T_option, T_repeat, T_exact]:
        if stack.len == 0: return top.alternation
        r.fail("token of type '" & ABNF_TOKENS[top.close].name & "'")
      break

proc parseAbnf*(src: string): Grammar =
  parseGrammar(src, ABNF_TOKENS, T_title,
    proc (text: string): string = text[1 ..< text.len - 1],
    proc (r: Reader): RuleAst =
      let name = r.expect(T_name)
      discard r.expect(T_equals)
      let definition = alternation(r)
      discard r.expect(T_semicolon)
      RuleAst(name: name, definition: definition))

func digitRun(s: string, i: int): int =
  result = i
  while result < s.len and s[result] in Digits: inc result

func parseIntPrefix(s: string): float =
  ## parseInt(s, 10) of a text that starts with digits
  jsNumber(s[0 ..< digitRun(s, 0)])

proc node(part: Part, kids: seq[RailroadNode]): RailroadNode =
  case part.kind
  of "AbnfAlternation": choice(kids)
  of "AbnfConcatenation": sequence(kids)
  of "AbnfElement":
    let repeat = part.text
    if repeat == "": return kids[0]
    let star = repeat.find('*')
    let exact = star == -1
    let min = if star > 0 or exact: parseIntPrefix(repeat) else: 0.0
    let max = if exact: min
              elif star < repeat.len - 1: parseIntPrefix(repeat[star + 1 .. ^1])
              else: Inf
    if min == 0 and max == 1: optional(kids[0]) else: repetition(kids[0], min, max)
  of "AbnfStringLiteral", "AbnfNumVal": terminal(part.text)
  of "AbnfRuleName": nonterminal(part.text)
  of "AbnfGroup": kids[0]
  else: optional(kids[0])

proc abnfRules*(ast: Grammar): seq[RailroadRule] = toRules(ast, node)
