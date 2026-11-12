## port-of: src/diagrams/common/tokens.ts
## port-status: draft
##
## Tokenizer for the diagram types Mermaid defines with Langium grammars. Token types are tried
## in order and the first match wins, as in Chevrotain; the tables in each diagram's folder are
## checked against Mermaid's generated lexers by the tests.
##
## A token type's sticky regular expression is a matcher here: a proc that answers, at a byte
## position, where the match ends (or -1). Each one names the pattern it answers as.
import std/strutils
import ../../errors
import ../../js

type
  Scanner* = proc (src: string, at: int, previous: int): int
    ## `previous` is the last visible token's type index, or -1 at the start.

  Matcher* = proc (src: string, at: int): int {.noSideEffect.}
    ## A sticky pattern: the end of its match at `at`, or -1.

  TokenType* = ref object
    name*: string
    literal*: string        ## a literal pattern ("" when `pattern` is a matcher)
    pattern*: Matcher
    hidden*: bool
    opener*: Matcher
      ## Start of a construct that needs a closer. When this matches but the whole pattern does
      ## not, no closer exists in the rest of the text, so the pattern is not tried again.
    first*: string
    hasFirst*: bool
      ## Every ASCII character a match of a regular expression can start with, when that is
      ## known. The type is then tried only at those characters and at characters outside ASCII.
    longer*: seq[TokenType]
      ## Chevrotain's LONGER_ALT. When this type matches, these are tried at the same place, and
      ## the first one that matches more text becomes the token.
    scanner*: proc (): Scanner
      ## Makes a matcher that answers as `pattern` does, for a pattern that could rescan the
      ## text. It is called once per text, so the matcher may remember what it has scanned.
    match*: Scanner
      ## Matches in place of the pattern, for a pattern that would rescan text from every
      ## position or that depends on the token before it.

  Tokens* = object
    kinds*, starts*, ends*: seq[int]
    src*: string

type Table = object
  starting: array[128, seq[int]]
    ## For each ASCII character, the token types that can start with it, in matching order.
  every: seq[int]
  longer: seq[seq[int]]

proc prepare(types: seq[TokenType]): Table =
  for k in 0 ..< types.len: result.every.add k
  for c in 0 ..< 128:
    let ch = char(c)
    for k in 0 ..< types.len:
      let t = types[k]
      if (if t.literal != "": t.literal[0] == ch else: not t.hasFirst or ch in t.first):
        result.starting[c].add k
  for t in types:
    var alts: seq[int]
    for alt in t.longer: alts.add types.find(alt)
    result.longer.add alts

proc tokenize*(src: string, types: seq[TokenType], diagram: string): Tokens =
  var kinds, starts, ends: seq[int]
  var dead = newSeq[bool](types.len)
  let table = prepare(types)
  var scanners = newSeq[Scanner](types.len)
  let n = src.len

  proc match(k, p: int): int =
    if dead[k]: return -1
    let t = types[k]
    let previous = if kinds.len > 0: kinds[^1] else: -1
    if t.match != nil: return t.match(src, p, previous)
    if t.scanner != nil:
      if scanners[k] == nil: scanners[k] = t.scanner()
      return scanners[k](src, p, previous)
    if t.literal != "": return (if src.continuesWith(t.literal, p): p + t.literal.len else: -1)
    let stop = t.pattern(src, p)
    if stop >= 0: return stop
    if t.opener != nil and t.opener(src, p) >= 0: dead[k] = true
    -1

  var p = 0
  while p < n:
    let c = ord(src[p])
    var found = false
    for k in (if c < 128: table.starting[c] else: table.every):
      var stop = match(k, p)
      if stop <= p: continue
      var kind = k
      for alt in table.longer[k]:
        let altEnd = match(alt, p)
        if altEnd > stop:
          kind = alt
          stop = altEnd
          break
      if not types[kind].hidden:
        kinds.add kind
        starts.add p
        ends.add stop
      p = stop
      found = true
      break
    if not found: raise syntaxError(diagram, src, p, "", true)
  kinds.add -1
  starts.add n
  ends.add n
  Tokens(kinds: kinds, starts: starts, ends: ends, src: src)

# ---------------------------------------------------------------------------------------------
# Pieces of the patterns

func blanks(s: string, i: int): int =
  ## [\t ]* from i
  result = i
  while result < s.len and s[result] in {'\t', ' '}: inc result

func lineEnd(s: string, i: int): int =
  ## [^\n\r]* from i
  result = i
  while result < s.len and s[result] notin {'\n', '\r'}: inc result

func toCommentOrLineEnd(s: string, i: int): int =
  ## [^\n\r]*?(?=%%)|[^\n\r]*: up to the first `%%` of the line, or its end.
  let stop = lineEnd(s, i)
  let at = s.find("%%", i)
  if at != -1 and at < stop: at else: stop

func spaces(s: string, i: int): int =
  ## \s* from i
  result = i
  while true:
    let n = spaceLenAt(s, result)
    if n == 0: break
    result += n

func newlineAt(s: string, i: int): int =
  ## \r?\n at i: its end, or -1
  if i < s.len and s[i] == '\n': i + 1
  elif i + 1 < s.len and s[i] == '\r' and s[i + 1] == '\n': i + 2
  else: -1

func notNonSpace(s: string, i: int): bool =
  ## (?!\S) at i
  i >= s.len or isJsSpaceAt(s, i)

func matchAccDescr(s: string, p: int): int =
  ## /[\t ]*accDescr(?:[\t ]*:([^\n\r]*?(?=%%)|[^\n\r]*)|\s*{([^}]*)})/y
  var i = blanks(s, p)
  if not s.continuesWith("accDescr", i): return -1
  i += 8
  let j = blanks(s, i)
  if j < s.len and s[j] == ':': return toCommentOrLineEnd(s, j + 1)
  let k = spaces(s, i)
  if k < s.len and s[k] == '{':
    let close = s.find('}', k + 1)
    if close != -1: return close + 1
  -1

func matchAccTitle(s: string, p: int): int =
  ## /[\t ]*accTitle[\t ]*:(?:[^\n\r]*?(?=%%)|[^\n\r]*)/y
  var i = blanks(s, p)
  if not s.continuesWith("accTitle", i): return -1
  i = blanks(s, i + 8)
  if i < s.len and s[i] == ':': toCommentOrLineEnd(s, i + 1) else: -1

func matchTitle(s: string, p: int): int =
  ## /[\t ]*title(?:[\t ][^\n\r]*?(?=%%)|[\t ][^\n\r]*|)/y
  let i = blanks(s, p)
  if not s.continuesWith("title", i): return -1
  let j = i + 5
  if j < s.len and s[j] in {'\t', ' '}: toCommentOrLineEnd(s, j + 1) else: j

func matchString(s: string, p: int): int =
  ## /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/y
  if p >= s.len or s[p] notin {'"', '\''}: return -1
  let q = s[p]
  var i = p + 1
  while i < s.len:
    let c = s[i]
    if c == q: return i + 1
    if c == '\\':
      # `.` is any character but a line terminator
      if i + 1 >= s.len or s[i + 1] in {'\n', '\r'} or s.continuesWith(" ", i + 1) or
         s.continuesWith(" ", i + 1):
        return -1
      i += 1 + codePointAt(s, i + 1).size
    else:
      inc i
  -1

func matchNewline(s: string, p: int): int = newlineAt(s, p)

func matchWhitespace(s: string, p: int): int =
  ## /[\t ]+/y
  let i = blanks(s, p)
  if i > p: i else: -1

func yamlOpener(s: string, p: int): int =
  ## /---[\t ]*\r?\n/y
  if not s.continuesWith("---", p): return -1
  newlineAt(s, blanks(s, p + 3))

func fenceEnd(s: string, i: int): int =
  ## ---(?:\r?\n|(?!\S)) at i
  if not s.continuesWith("---", i): return -1
  let j = i + 3
  let nl = newlineAt(s, j)
  if nl >= 0: nl elif notNonSpace(s, j): j else: -1

func matchYaml(s: string, p: int): int =
  ## /---[\t ]*\r?\n(?:[\S\s]*?\r?\n)?---(?:\r?\n|(?!\S))/y
  let q = yamlOpener(s, p)
  if q < 0: return -1
  let direct = fenceEnd(s, q)
  if direct >= 0: return direct
  var j = q
  while j < s.len:
    let nl = newlineAt(s, j)
    if nl >= 0:
      let e = fenceEnd(s, nl)
      if e >= 0: return e
    inc j
  -1

func directiveOpener(s: string, p: int): int =
  ## /[\t ]*%%{/y
  let i = blanks(s, p)
  if s.continuesWith("%%{", i): i + 3 else: -1

func matchDirective(s: string, p: int): int =
  ## /[\t ]*%%{[\S\s]*?}%%(?:\r?\n|(?!\S))/y
  let q = directiveOpener(s, p)
  if q < 0: return -1
  var j = s.find("}%%", q)
  while j != -1:
    let k = j + 3
    let nl = newlineAt(s, k)
    if nl >= 0: return nl
    if notNonSpace(s, k): return k
    j = s.find("}%%", j + 1)
  -1

func matchComment(s: string, p: int): int =
  ## /[\t ]*%%[^\n\r]*/y
  let i = blanks(s, p)
  if s.continuesWith("%%", i): lineEnd(s, i + 2) else: -1

let ACC_DESCR* = TokenType(name: "ACC_DESCR", pattern: matchAccDescr, first: "\t a", hasFirst: true)
let ACC_TITLE* = TokenType(name: "ACC_TITLE", pattern: matchAccTitle, first: "\t a", hasFirst: true)
let TITLE* = TokenType(name: "TITLE", pattern: matchTitle, first: "\t t", hasFirst: true)
let STRING* = TokenType(name: "STRING", pattern: matchString, first: "\"'", hasFirst: true)
let NEWLINE* = TokenType(name: "NEWLINE", pattern: matchNewline, first: "\r\n", hasFirst: true)
let WHITESPACE* = TokenType(name: "WHITESPACE", pattern: matchWhitespace, hidden: true,
                            first: "\t ", hasFirst: true)
let YAML* = TokenType(name: "YAML", pattern: matchYaml, hidden: true, opener: yamlOpener,
                      first: "-", hasFirst: true)
let DIRECTIVE* = TokenType(name: "DIRECTIVE", pattern: matchDirective, hidden: true,
                           opener: directiveOpener, first: "\t %", hasFirst: true)
let SINGLE_LINE_COMMENT* = TokenType(name: "SINGLE_LINE_COMMENT", pattern: matchComment,
                                     first: "\t %", hasFirst: true, hidden: true)

proc titleBefore*(rest: proc (s: string, i: int): bool {.noSideEffect.}): TokenType =
  ## `rest` matches a name suffix so `title` does not split longer names: the pattern is
  ## /[\t ]*title(?:[\t ][^\n\r]*?(?=%%)|[\t ][^\n\r]*|(?!rest))/y
  let m = proc (s: string, p: int): int {.noSideEffect.} =
    let i = blanks(s, p)
    if not s.continuesWith("title", i): return -1
    let j = i + 5
    if j < s.len and s[j] in {'\t', ' '}: return toCommentOrLineEnd(s, j + 1)
    if rest(s, j): -1 else: j
  TokenType(name: TITLE.name, pattern: m, first: TITLE.first, hasFirst: true)

proc keyword*(word: string): TokenType =
  ## Mermaid ends a keyword only at whitespace, a comment, or the end of input.
  let m = proc (s: string, p: int): int {.noSideEffect.} =
    if not s.continuesWith(word, p): return -1
    let j = p + word.len
    if s.continuesWith("%%", j) or notNonSpace(s, j): j else: -1
  TokenType(name: word, pattern: m, first: word[0 .. 0], hasFirst: true)

# ---------------------------------------------------------------------------------------------
# Token values

func collapseBlanks(s: string): string =
  ## s.replace(/[\t ]{2,}/gm, ' ')
  var i = 0
  while i < s.len:
    if s[i] in {'\t', ' '}:
      let j = blanks(s, i)
      if j - i >= 2:
        result.add ' '
        i = j
        continue
    result.add s[i]
    inc i

func single(text: string): string =
  collapseBlanks(jsTrim(text))

proc titleValue*(text: string): string =
  ## /title([\t ][^\n\r]*|)/
  let at = text.find("title")
  let j = at + 5
  single(if j < text.len and text[j] in {'\t', ' '}: text[j ..< lineEnd(text, j + 1)] else: "")

proc accTitleValue*(text: string): string =
  ## /accTitle[\t ]*:([^\n\r]*)/
  var at = text.find("accTitle")
  while at != -1:
    let i = blanks(text, at + 8)
    if i < text.len and text[i] == ':': return single(text[i + 1 ..< lineEnd(text, i + 1)])
    at = text.find("accTitle", at + 1)
  ""

func isLineStart(s: string, i: int): bool =
  ## ^ with the m flag
  if i == 0: return true
  let k = prevRuneStart(s, i)
  s[k] in {'\n', '\r'} or s.continuesWith(" ", k) or s.continuesWith(" ", k)

func isLineEndAt(s: string, i: int): bool =
  ## $ with the m flag
  i >= s.len or s[i] in {'\n', '\r'} or s.continuesWith(" ", i) or s.continuesWith(" ", i)

func dropLeadingSpaces(s: string): string =
  ## s.replace(/^\s*/gm, '')
  var i = 0
  while i < s.len:
    if isLineStart(s, i):
      let j = spaces(s, i)
      if j > i:
        i = j
        continue
    result.add s[i]
    inc i

func dropTrailingSpaces(s: string): string =
  ## s.replace(/\s+$/gm, '')
  var i = 0
  while i < s.len:
    let n = spaceLenAt(s, i)
    if n > 0:
      # the longest run of \s from i that ends where $ holds
      var best = -1
      var k = i
      while true:
        let m = spaceLenAt(s, k)
        if m == 0: break
        k += m
        if isLineEndAt(s, k): best = k
      if best >= 0:
        i = best
        continue
    result.add s[i]
    inc i

func collapseLineBreaks(s: string): string =
  ## s.replace(/[\n\r]{2,}/gm, '\n')
  var i = 0
  while i < s.len:
    if s[i] in {'\n', '\r'}:
      var j = i
      while j < s.len and s[j] in {'\n', '\r'}: inc j
      if j - i >= 2:
        result.add '\n'
        i = j
        continue
    result.add s[i]
    inc i

proc accDescrValue*(text: string): string =
  ## /accDescr(?:[\t ]*:([^\n\r]*)|\s*{([^}]*)})/
  var at = text.find("accDescr")
  while at != -1:
    let i = at + 8
    let j = blanks(text, i)
    if j < text.len and text[j] == ':':
      return single(text[j + 1 ..< lineEnd(text, j + 1)])
    let k = spaces(text, i)
    if k < text.len and text[k] == '{':
      let close = text.find('}', k + 1)
      if close != -1:
        return collapseLineBreaks(collapseBlanks(dropTrailingSpaces(dropLeadingSpaces(text[k + 1 ..< close]))))
    at = text.find("accDescr", at + 1)
  ""

proc stringValue*(text: string): string =
  if '\\' notin text: return text[1 ..< text.len - 1]
  var i = 1
  while i < text.len - 1:
    let c = text[i]
    if c == '\\':
      inc i
      let next = text[i]
      case next
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'v': result.add '\v'
      of '0': result.add '\0'
      else:
        let size = codePointAt(text, i).size
        result.add text[i ..< i + size]
        i += size
        continue
    else:
      result.add c
    inc i

type Reader* = ref object
  ## Reads tokens for a hand-written parser, with Chevrotain-style messages on failure.
  i*: int
  kinds*: seq[int]
  tokens*: Tokens
  types*: seq[TokenType]
  diagram*: string

proc newReader*(tokens: Tokens, types: seq[TokenType], diagram: string): Reader =
  Reader(tokens: tokens, types: types, diagram: diagram, kinds: tokens.kinds)

proc kind*(r: Reader): int = r.kinds[r.i]

proc text*(r: Reader, index: int): string =
  r.tokens.src[r.tokens.starts[index] ..< r.tokens.ends[index]]

proc text*(r: Reader): string = r.text(r.i)

proc take*(r: Reader): string =
  result = r.text(r.i)
  inc r.i

proc accept*(r: Reader, kind: int): bool =
  if r.kinds[r.i] != kind: return false
  inc r.i
  true

proc fail*(r: Reader, expected: string) {.noreturn.} =
  let found = if r.kind == -1: "end of input" else: "`" & r.text() & "`"
  let src = r.tokens.src
  var at = r.tokens.starts[r.i]
  if r.kind == -1:
    # Locate EOF errors after the last token, before trailing line breaks and hidden comments.
    var k = r.i
    while k > 0 and jsTrim(src[r.tokens.starts[k - 1] ..< r.tokens.ends[k - 1]]) == "": dec k
    if k > 0: at = r.tokens.ends[k - 1]
  raise syntaxError(r.diagram, src, at, "Expecting " & expected & " but found " & found & ".")

proc expect*(r: Reader, kind: int): string =
  if r.kinds[r.i] != kind: r.fail("token of type '" & r.types[kind].name & "'")
  r.take()
