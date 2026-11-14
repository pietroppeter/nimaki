## port-of: src/diagrams/venn/lexer.ts
## port-status: conformant
##
## Positions are byte offsets. `charCodeAt` becomes `cu`, which reads the character at a byte
## offset (-1 past the end, as NaN is nothing; the high surrogate for a character past U+FFFF);
## a step over a whitespace character takes its bytes.
import std/strutils
import ../../js
import ../../util/chars

const
  T_END* = 0
  T_ERROR* = 1
  T_EOF* = 2
  T_NEWLINE* = 3
  T_VENN* = 4
  T_TITLE* = 5
  T_SET* = 6
  T_UNION* = 7
  T_TEXT* = 8
  T_INDENT_TEXT* = 9
  T_STYLE* = 10
  T_BRACKET_LABEL* = 11
  T_NUMERIC* = 12
  T_HEXCOLOR* = 13
  T_RGBCOLOR* = 14
  T_RGBACOLOR* = 15
  T_IDENTIFIER* = 16
  T_STRING* = 17
  T_COMMA* = 18
  T_COLON* = 19

const TOKEN_NAMES* = ["$end", "INVALID", "EOF", "NEWLINE", "VENN", "TITLE", "SET", "UNION", "TEXT",
                      "INDENT_TEXT", "STYLE", "BRACKET_LABEL", "NUMERIC", "HEXCOLOR", "RGBCOLOR",
                      "RGBACOLOR", "IDENTIFIER", "STRING", "COMMA", "COLON"]

type
  IndentHost* = object
    ## The part of the model the lexer talks to: an indented `text` line is a different token
    ## after a set or union than anywhere else, and the parser is what knows which came before.
    getIndentMode*: proc (): bool
    setIndentMode*: proc (enabled: bool)

  VennLexer* = ref object
    ## Reads tokens one at a time, as Mermaid's Jison lexer for venn diagrams does: every rule
    ## ignores case, the first rule that matches wins, and a keyword must end at a word boundary.
    text*: string            ## the text and position of the token `next` returned last
    start*: int
    at: int
    lineStart: bool
    ended: bool
    src: string
    host: IndentHost

const KEYWORDS = [("venn-beta", T_VENN), ("set", T_SET), ("union", T_UNION), ("text", T_TEXT),
                  ("style", T_STYLE)]

func cu(src: string, i: int): int =
  if i < 0 or i >= src.len: return -1
  let b = ord(src[i])
  if b < 0x80: return b
  let (cp, _) = codePointAt(src, i)
  if cp >= 0x10000: 0xD800 + ((cp - 0x10000) shr 10) else: cp

func charLen*(src: string, i: int): int =
  if i >= src.len: 1 elif ord(src[i]) < 0x80: 1 else: codePointAt(src, i)[1]

proc newVennLexer*(src: string, host: IndentHost): VennLexer =
  VennLexer(src: src, host: host)

proc word(lx: VennLexer, at: int, word: string): bool =
  for k in 0 ..< word.len:
    let c = cu(lx.src, at + k)
    let w = ord(word[k])
    if c != w and (c + 32 != w or c < 65 or c > 90): return false
  true

proc keyword(lx: VennLexer, at: int, word: string): bool =
  lx.word(at, word) and not isWord(cu(lx.src, at + word.len))

proc color(lx: VennLexer, at: int, parts: int): int =
  ## The end of `rgb(1, 2, 3)` or `rgba(1, 2, 3, 0.5)` whose parenthesis opens at `at`, or -1.
  let src = lx.src
  var i = at + 1
  for part in 0 ..< parts:
    while isSpace(cu(src, i)): i += charLen(src, i)
    let source = i
    while isDigit(cu(src, i)) or cu(src, i) == 46: inc i
    if i == source: return -1
    while isSpace(cu(src, i)): i += charLen(src, i)
    if cu(src, i) != (if part == parts - 1: 41 else: 44): return -1
    inc i
  i

proc afterLineFeed(lx: VennLexer, at: int): bool =
  var k = at - 1
  while cu(lx.src, k) == 32 or cu(lx.src, k) == 9: dec k
  cu(lx.src, k) == 10

proc lineEnd(lx: VennLexer, source: int): int =
  let e = lx.src.find('\n', source)
  if e == -1: lx.src.len else: e

proc token(lx: VennLexer, kind, e: int): int =
  lx.text = lx.src[lx.at ..< e]
  lx.at = e
  kind

proc next*(lx: VennLexer): int =
  let src = lx.src
  let n = src.len
  while true:
    var i = lx.at
    lx.start = i
    lx.text = ""
    if i >= n:
      if lx.ended: return T_END
      lx.ended = true
      return T_EOF
    let c = cu(src, i)
    if c == 37 and cu(src, i + 1) == 37 and cu(src, i + 2) != 123:
      lx.at = lx.lineEnd(i + 2)
      continue
    if lx.lineStart and lx.word(i, "title") and lx.afterLineFeed(i) and
        jsTrim(src[min(i + 5, n) ..< lx.lineEnd(i + 5)]) == "":
      # Skip a bare title like a comment, so it doesn't end indented text.
      var j = lx.lineEnd(i + 5)
      while cu(src, j) == 10 or cu(src, j) == 13: inc j
      lx.at = j
      continue
    if lx.lineStart:
      if c == 32 or c == 9:
        var j = i + 1
        while cu(src, j) == 32 or cu(src, j) == 9: inc j
        lx.at = j
        if lx.keyword(j, "text") and lx.host.getIndentMode():
          # The word `text` itself is dropped; the indentation stands for it.
          lx.at = j + 4
          lx.lineStart = false
          lx.text = src[i ..< j]
          return T_INDENT_TEXT
        continue
      if c != 10 and c != 13:
        lx.host.setIndentMode(false)
        lx.lineStart = false
    if c == 10 or c == 13:
      inc i
      while cu(src, i) == 10 or cu(src, i) == 13: inc i
      lx.lineStart = true
      return lx.token(T_NEWLINE, i)
    if c == 37 and cu(src, i + 1) == 37:
      lx.at = lx.lineEnd(i)
      continue
    if c == 32 or c == 9:
      inc i
      while cu(src, i) == 32 or cu(src, i) == 9: inc i
      lx.at = i
      continue

    if ((c or 32) >= 97 and (c or 32) <= 122) or c == 95:
      let sep = cu(src, i + 5)
      if lx.word(i, "title") and isSpace(sep) and sep != 10 and sep != 13:
        # i + 6 in UTF-16 units: past the title and the one character after it
        let after = i + 5 + charLen(src, i + 5)
        var e = after
        while e < n:
          let ch = cu(src, e)
          if ch == 35 or ch == 10 or ch == 59: break
          e += charLen(src, e)
        if e > after: return lx.token(T_TITLE, e)
      for (word, kind) in KEYWORDS:
        # A hyphen continues a name, as in `set-theory`.
        if lx.keyword(i, word) and cu(src, i + word.len) != 45: return lx.token(kind, i + word.len)
      if lx.word(i, "rgb"):
        let alpha = (cu(src, i + 3) or 32) == 97
        let open = i + (if alpha: 4 else: 3)
        let e = if cu(src, open) == 40: lx.color(open, if alpha: 4 else: 3) else: -1
        if e != -1: return lx.token(if alpha: T_RGBACOLOR else: T_RGBCOLOR, e)
      inc i
      while isWord(cu(src, i)) or cu(src, i) == 45: inc i
      return lx.token(T_IDENTIFIER, i)
    if c == 91:
      if cu(src, i + 1) == 34:
        let quote = src.find('"', i + 2)
        if quote == -1 or cu(src, quote + 1) != 93: return T_ERROR
        lx.at = quote + 2
        lx.text = src[i + 2 ..< quote]
        return T_BRACKET_LABEL
      var e = i + 1
      while e < n and cu(src, e) != 93 and cu(src, e) != 34: inc e
      if e == i + 1 or cu(src, e) != 93: return T_ERROR
      lx.at = e + 1
      lx.text = jsTrim(src[i + 1 ..< e])
      return T_BRACKET_LABEL
    if isDigit(c) or c == 46 or c == 43 or c == 45:
      if c == 43 or c == 45: inc i
      let source = i
      while isDigit(cu(src, i)): inc i
      if i > source:
        if cu(src, i) == 46 and isDigit(cu(src, i + 1)):
          i += 2
          while isDigit(cu(src, i)): inc i
      elif cu(src, i) == 46 and isDigit(cu(src, i + 1)):
        i += 2
        while isDigit(cu(src, i)): inc i
      else: return T_ERROR
      return lx.token(T_NUMERIC, i)
    if c == 35:
      var e = i + 1
      while e < i + 9 and isHex(cu(src, e)): inc e
      return if e >= i + 4: lx.token(T_HEXCOLOR, e) else: T_ERROR
    if c == 34:
      let quote = src.find('"', i + 1)
      return if quote == -1: T_ERROR else: lx.token(T_STRING, quote + 1)
    if c == 44: return lx.token(T_COMMA, i + 1)
    if c == 58: return lx.token(T_COLON, i + 1)
    return T_ERROR
