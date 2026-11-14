## port-of: src/diagrams/common/tokens.ts
## port-status: draft
##
## Tokenizer for the diagram types Mermaid defines with Langium grammars. Token types are tried
## in order and the first match wins, as in Chevrotain; the tables in each diagram's folder are
## checked against Mermaid's generated lexers by the tests.
##
## A token type's pattern is Pele's sticky regular expression, written as Pele writes it
## (`jsregex.nim`, decision 0015).
import std/strutils
import ../../errors
import ../../js
import ../../jsregex

type
  Scanner* = proc (src: string, at: int, previous: int): int
    ## `previous` is the last visible token's type index, or -1 at the start.

  TokenType* = ref object
    name*: string
    literal*: string        ## a literal pattern ("" when `pattern` is a regex)
    pattern*: JsRegExp      ## a regular expression with the sticky flag
    hidden*: bool
    opener*: JsRegExp
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
    let stop = t.pattern.matchEnd(src, p)
    if stop >= 0: return stop
    if t.opener.isSet and t.opener.test(src, p): dead[k] = true
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
# The token types every Langium diagram shares

let ACC_DESCR* = TokenType(name: "ACC_DESCR",
  pattern: jsre"/[\t ]*accDescr(?:[\t ]*:([^\n\r]*?(?=%%)|[^\n\r]*)|\s*{([^}]*)})/y",
  first: "\t a", hasFirst: true)
let ACC_TITLE* = TokenType(name: "ACC_TITLE",
  pattern: jsre"/[\t ]*accTitle[\t ]*:(?:[^\n\r]*?(?=%%)|[^\n\r]*)/y",
  first: "\t a", hasFirst: true)
let TITLE* = TokenType(name: "TITLE",
  pattern: jsre"/[\t ]*title(?:[\t ][^\n\r]*?(?=%%)|[\t ][^\n\r]*|)/y",
  first: "\t t", hasFirst: true)

proc titleBefore*(rest: string): TokenType =
  ## `rest` matches a name suffix so `title` does not split longer names.
  TokenType(name: TITLE.name, first: TITLE.first, hasFirst: true, pattern: newRegExp(
    r"[\t ]*title(?:[\t ][^\n\r]*?(?=%%)|[\t ][^\n\r]*|(?!" & rest & "))", "y"))

let STRING* = TokenType(name: "STRING", pattern: jsre"""/"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/y""",
                        first: "\"'", hasFirst: true)
let NEWLINE* = TokenType(name: "NEWLINE", pattern: jsre"/\r?\n/y", first: "\r\n", hasFirst: true)
let WHITESPACE* = TokenType(name: "WHITESPACE", pattern: jsre"/[\t ]+/y", hidden: true,
                            first: "\t ", hasFirst: true)
let YAML* = TokenType(name: "YAML",
  pattern: jsre"/---[\t ]*\r?\n(?:[\S\s]*?\r?\n)?---(?:\r?\n|(?!\S))/y",
  hidden: true, opener: jsre"/---[\t ]*\r?\n/y", first: "-", hasFirst: true)
let DIRECTIVE* = TokenType(name: "DIRECTIVE",
  pattern: jsre"/[\t ]*%%{[\S\s]*?}%%(?:\r?\n|(?!\S))/y",
  hidden: true, opener: jsre"/[\t ]*%%{/y", first: "\t %", hasFirst: true)
let SINGLE_LINE_COMMENT* = TokenType(name: "SINGLE_LINE_COMMENT", pattern: jsre"/[\t ]*%%[^\n\r]*/y",
                                     first: "\t %", hasFirst: true, hidden: true)

proc keyword*(word: string): TokenType =
  ## Mermaid ends a keyword only at whitespace, a comment, or the end of input.
  TokenType(name: word, pattern: newRegExp(escapeRegExp(word) & r"(?:(?=%%)|(?!\S))", "y"),
            first: word[0 .. 0], hasFirst: true)

const
  RE_ACC_DESCR = jsre"/accDescr(?:[\t ]*:([^\n\r]*)|\s*{([^}]*)})/"
  RE_ACC_TITLE = jsre"/accTitle[\t ]*:([^\n\r]*)/"
  RE_TITLE = jsre"/title([\t ][^\n\r]*|)/"

proc single(text: string): string =
  jsTrim(text).replace(jsre"/[\t ]{2,}/gm", " ")

proc titleValue*(text: string): string =
  single(RE_TITLE.exec(text)[1])

proc accTitleValue*(text: string): string =
  single(RE_ACC_TITLE.exec(text)[1])

proc accDescrValue*(text: string): string =
  let m = RE_ACC_DESCR.exec(text)
  if m.has(1): return single(m[1])
  m[2]
    .replace(jsre"/^\s*/gm", "")
    .replace(jsre"/\s+$/gm", "")
    .replace(jsre"/[\t ]{2,}/gm", " ")
    .replace(jsre"/[\n\r]{2,}/gm", "\n")

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
