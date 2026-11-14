## port-of: src/diagrams/railroad/common.ts
## port-status: draft
##
## What the four railroad grammars share: the title and accessibility tokens (which, unlike
## the ones in Mermaid's common grammar, do not take leading blanks), the hidden tokens, the
## statements before the first rule, string values, and the walk from a syntax tree to the rule model.
##
## Port notes: the four syntax trees are one node type here, `Part`, whose `kind` is the
## TypeScript `$type` and whose `kids` are what Pele's `parts` finds in it: an EBNF term's base
## and then the right side of each exception, in order. A sticky regular expression is a matcher
## with its pattern in a comment, as everywhere in the port.
import std/strutils except unescape
import ../common/tokens except ACC_TITLE, ACC_DESCR
import ../../js
import types

export tokens except ACC_TITLE, ACC_DESCR

const LETTERS* = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

func lineEnd(s: string, i: int): int =
  ## [^\n\r]* from i
  result = i
  while result < s.len and s[result] notin {'\n', '\r'}: inc result

func toCommentOrLineEnd(s: string, i: int): int =
  ## [^\n\r]*?(?=%%)|[^\n\r]*: up to the first `%%` of the line, or its end.
  let stop = lineEnd(s, i)
  let at = s.find("%%", i)
  if at != -1 and at < stop: at else: stop

func blanks(s: string, i: int): int =
  ## [\t ]* from i
  result = i
  while result < s.len and s[result] in {'\t', ' '}: inc result

func spaces*(s: string, i: int): int =
  ## \s* from i (isSpace for each character)
  result = i
  while true:
    let n = spaceLenAt(s, result)
    if n == 0: break
    result += n

proc accDescrScanner(): Scanner =
  ## The braced form scans to the next closing brace. Once none is found, none exists further on
  ## either, so later braced descriptions fail without scanning again.
  var unclosed = high(int)
  result = proc (src: string, at: int, previous: int): int =
    if not src.continuesWith("accDescr", at): return -1
    let n = src.len
    var i = blanks(src, at + 8)
    if i < n and src[i] == ':':
      inc i
      while i < n:
        let c = src[i]
        if c == '\n' or c == '\r' or (c == '%' and i + 1 < n and src[i + 1] == '%'): break
        inc i
      return i
    i = spaces(src, i)
    if i >= n or src[i] != '{' or i >= unclosed: return -1
    let close = src.find('}', i + 1)
    if close == -1: unclosed = i
    if close == -1: -1 else: close + 1

proc title*(rest: proc (c: char): bool {.noSideEffect.}): TokenType =
  ## `rest` matches a name suffix so `title` does not split longer names:
  ## /title(?:[\t ][^\n\r]*?(?=%%)|[\t ][^\n\r]*|(?!rest))/y
  let m = proc (s: string, p: int): int {.noSideEffect.} =
    if not s.continuesWith("title", p): return -1
    let j = p + 5
    if j < s.len and s[j] in {'\t', ' '}: return toCommentOrLineEnd(s, j + 1)
    if j < s.len and rest(s[j]): -1 else: j
  TokenType(name: "TITLE", matcher: m, first: "t", hasFirst: true)

func wordRest*(c: char): bool = isWordChar(c) or c == '-'   ## [\w-]

func matchAccTitle(s: string, p: int): int =
  ## /accTitle[\t ]*:(?:[^\n\r]*?(?=%%)|[^\n\r]*)/y
  if not s.continuesWith("accTitle", p): return -1
  let i = blanks(s, p + 8)
  if i < s.len and s[i] == ':': toCommentOrLineEnd(s, i + 1) else: -1

let ACC_TITLE* = TokenType(name: "ACC_TITLE", matcher: matchAccTitle, first: "a", hasFirst: true)
let ACC_DESCR* = TokenType(name: "ACC_DESCR", scanner: accDescrScanner, first: "a", hasFirst: true)
  ## /accDescr(?:[\t ]*:([^\n\r]*?(?=%%)|[^\n\r]*)|\s*{([^}]*)})/y, read by the scanner

proc literal*(name: string, longer: seq[TokenType] = @[]): TokenType =
  TokenType(name: name, literal: name, longer: longer)

proc opening*(word: string, name: TokenType): TokenType =
  ## The diagram's keyword. A name that starts with it and goes on is a name.
  result = keyword(word)
  result.longer = @[name]

func matchIdentifier(s: string, p: int): int =
  ## /[A-Z_a-z][\w-]*/y
  if p >= s.len or s[p] notin {'A'..'Z', 'a'..'z', '_'}: return -1
  result = p + 1
  while result < s.len and wordRest(s[result]): inc result

proc identifier*(name: string): TokenType =
  TokenType(name: name, matcher: matchIdentifier, first: LETTERS & "_", hasFirst: true)

proc quoted*(name: string): TokenType =
  ## /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/y
  TokenType(name: name, pattern: STRING.pattern, first: "\"'", hasFirst: true)

proc between*(name, open, close: string, first: string): TokenType =
  ## A hidden comment from `open` to the first `close` after it: /open[\s\S]*?close/y, with
  ## `open` as its opener.
  let m = proc (s: string, p: int): int {.noSideEffect.} =
    if not s.continuesWith(open, p): return -1
    let at = s.find(close, p + open.len)
    if at == -1: -1 else: at + close.len
  let o = proc (s: string, p: int): int {.noSideEffect.} =
    if s.continuesWith(open, p): p + open.len else: -1
  TokenType(name: name, matcher: m, hidden: true, first: first, hasFirst: true, openMatcher: o)

proc lineComment*(name: string, start: char): TokenType =
  ## /start[^\n\r]*/y, hidden
  let m = proc (s: string, p: int): int {.noSideEffect.} =
    if p < s.len and s[p] == start: lineEnd(s, p + 1) else: -1
  TokenType(name: name, matcher: m, hidden: true, first: $start, hasFirst: true)

func matchBlankRun(s: string, p: int): int =
  ## /[\t \r\n]+/y
  var i = p
  while i < s.len and s[i] in {'\t', ' ', '\r', '\n'}: inc i
  if i > p: i else: -1

proc renamed(t: TokenType, name: string): TokenType =
  ## `{ ...t, name }`
  result = TokenType()
  result[] = t[]
  result.name = name

proc hiddenTokens*(prefix: string): seq[TokenType] =
  ## Whitespace, front matter, directive, and `%%` comment, in the order every railroad grammar lists them.
  @[
    TokenType(name: prefix & "_WHITESPACE", matcher: matchBlankRun, hidden: true, first: "\t \r\n", hasFirst: true),
    YAML.renamed(prefix & "_YAML"),
    DIRECTIVE.renamed(prefix & "_DIRECTIVE"),
    SINGLE_LINE_COMMENT.renamed(prefix & "_SINGLE_LINE_COMMENT"),
  ]

proc unescape*(text: string): string =
  ## Mermaid's railroad value converters know three escapes; any other escaped character stands for itself.
  if '\\' notin text: return text[1 ..< text.len - 1]
  let stop = text.len - 1
  var i = 1
  while i < stop:
    if text[i] == '\\' and i + 1 < stop:
      inc i
      case text[i]
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      else:
        let size = codePointAt(text, i).size
        result.add text[i ..< i + size]
        i += size
        continue
      inc i
    else:
      result.add text[i]
      inc i

type
  Part* = ref object
    ## A node of any of the four syntax trees.
    kind*: string            ## the TypeScript `$type`
    text*: string            ## value, name, text, dot, operator or repeat ("" for undefined)
    kids*: seq[Part]
    postfixes*: seq[string]  ## an EBNF term's postfixes, by `$type`

  RuleAst* = object
    name*: string
    definition*: Part

  Grammar* = object
    title*, accTitle*, accDescr*: string   ## "" for undefined
    rules*: seq[RuleAst]

proc parseGrammar*(src: string, types: seq[TokenType], meta: int,
                   unquote: proc (text: string): string, rule: proc (r: Reader): RuleAst): Grammar =
  ## Parses the keyword, then any titles and accessibility statements, then rules to the end of the text.
  ## Every table starts with its keyword and has TITLE, ACC_TITLE, and ACC_DESCR in a row from `meta`.
  let r = newReader(tokenize(src, types, "railroad"), types, "railroad")
  discard r.expect(0)
  while true:
    let kind = r.kind
    if kind == meta:
      let title = titleValue(r.take())
      let quote = if title.len > 0: title[0] else: '\0'
      result.title = if (quote == '"' or quote == '\'') and title.endsWith(quote): unquote(title) else: title
    elif kind == meta + 1:
      result.accTitle = accTitleValue(r.take())
    elif kind == meta + 2:
      result.accDescr = accDescrValue(r.take())
    else:
      break
  while r.kind != -1: result.rules.add rule(r)

proc fold*[T, R](root: T, children: proc (node: T): seq[T], build: proc (node: T, results: seq[R]): R): R =
  ## Rebuilds a tree bottom-up without recursion, so that nesting depth is bounded by memory, not by the stack.
  var nodes = @[root]
  var lists = @[children(root)]
  var done: seq[seq[R]] = @[newSeq[R]()]
  while true:
    let top = nodes.len - 1
    if done[top].len < lists[top].len:
      let child = lists[top][done[top].len]
      nodes.add child
      lists.add children(child)
      done.add newSeq[R]()
    else:
      let value = build(nodes[top], done[top])
      if top == 0: return value
      discard nodes.pop()
      discard lists.pop()
      discard done.pop()
      done[top - 1].add value

proc partsOf*(node: Part): seq[Part] = node.kids
proc partsOf*(node: RailroadNode): seq[RailroadNode] = node.kids

proc terminal*(value: string): RailroadNode = RailroadNode(kind: nkTerminal, text: value)
proc nonterminal*(name: string): RailroadNode = RailroadNode(kind: nkNonterminal, text: name)
proc special*(text: string): RailroadNode = RailroadNode(kind: nkSpecial, text: text)
proc optional*(element: RailroadNode): RailroadNode = RailroadNode(kind: nkOptional, kids: @[element])
proc repetition*(element: RailroadNode, min: float, max = Inf): RailroadNode =
  RailroadNode(kind: nkRepetition, kids: @[element], min: min, max: max)

proc sequence*(elements: seq[RailroadNode]): RailroadNode =
  ## A sequence or a choice of one is that one, in every notation.
  if elements.len == 1: elements[0] else: RailroadNode(kind: nkSequence, kids: elements)

proc choice*(alternatives: seq[RailroadNode]): RailroadNode =
  if alternatives.len == 1: alternatives[0] else: RailroadNode(kind: nkChoice, kids: alternatives)

proc toRules*(ast: Grammar, build: proc (part: Part, kids: seq[RailroadNode]): RailroadNode): seq[RailroadRule] =
  ## Turns each rule's syntax tree into the common model, given how one node is built from its parts.
  for rule in ast.rules:
    result.add RailroadRule(name: rule.name, definition: fold[Part, RailroadNode](rule.definition, partsOf, build))
