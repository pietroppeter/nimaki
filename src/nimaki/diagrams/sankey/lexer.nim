## port-of: src/diagrams/sankey/lexer.ts
## port-status: conformant
##
## Positions are byte offsets; a character is read whole (`codePointAt`), where Pele steps one
## or two UTF-16 units.
import ../../js
import ../../util/chars

const
  T_END* = 0
  T_STUCK* = 1   ## Not a Jison token: the reference lexer would return the same empty token forever from here.
  T_SANKEY* = 2
  T_NEWLINE* = 3
  T_COMMA* = 4
  T_DQUOTE* = 5
  T_NON_ESCAPED_TEXT* = 6
  T_ESCAPED_TEXT* = 7
  T_EOF* = 8

  TOKEN_NAMES*: array[9, string] = ["$end", "STUCK", "SANKEY", "NEWLINE", "COMMA", "DQUOTE",
                                    "NON_ESCAPED_TEXT", "ESCAPED_TEXT", "EOF"]

type
  Tokens* = object
    types*: seq[int]
    texts*: seq[string]
    starts*: seq[int]

const
  S_INITIAL = 0
  S_CSV = 1
  S_ESCAPED_TEXT = 2

func isTextData(c: int): bool =
  ## RFC 4180 TEXTDATA extended to Unicode, excluding controls and invalid XML characters.
  (c >= 32 and c <= 126 and c != 34 and c != 44) or
    (c >= 0xa0 and c <= 0xd7ff) or
    (c >= 0xe000 and c <= 0xfffd) or
    (c >= 0x10000 and c <= 0x10ffff)

func at(s: string, i: int): int =
  ## `charCodeAt` for what is only compared with ASCII: -1 past the end (NaN).
  if i >= 0 and i < s.len: ord(s[i]) else: -1

func keyword(src: string, p: int, word: string): int =
  ## The byte length of `word` at p when `src.slice(p, p + word.length).toLowerCase() === word`
  ## and no word character follows, else 0. Only the Kelvin sign lowercases to an ASCII letter
  ## of these words ("k").
  var q = p
  for ch in word:
    if q >= src.len: return 0
    let (cp, size) = codePointAt(src, q)
    let lower = if cp >= 65 and cp <= 90: cp + 32 else: cp
    if lower != ord(ch) and not (ch == 'k' and cp == 0x212A): return 0
    q += size
  if isWord(at(src, q)): 0 else: q - p

func tokenize*(src: string): Tokens =
  let n = src.len
  var stack: seq[int]
  var state = S_INITIAL
  var p = 0

  template emit(kind, s, e: int) =
    result.types.add kind
    result.texts.add src[s ..< e]
    result.starts.add s
    p = e

  while p < n:
    let c = ord(src[p])
    let start = p
    var q = p
    if state == S_ESCAPED_TEXT:
      if c == 34 and at(src, p + 1) != 34:
        if stack.len > 0: state = stack.pop()
        emit(T_DQUOTE, p, p + 1)
        continue
      while q < n:
        let (d, size) = codePointAt(src, q)
        if isTextData(d) or d == 44 or d == 13 or d == 10: q += size
        elif d == 34 and at(src, q + 1) == 34: q += 2
        else: break
      emit(T_ESCAPED_TEXT, p, q)
    else:
      if state == S_INITIAL and (c or 32) == 115:
        var length = keyword(src, p, "sankey-beta")
        if length == 0: length = keyword(src, p, "sankey")
        if length > 0:
          stack.add state
          state = S_CSV
          emit(T_SANKEY, p, p + length)
          continue
      if c == 10 or (c == 13 and at(src, p + 1) == 10):
        emit(T_NEWLINE, p, (if c == 10: p + 1 else: p + 2))
        continue
      if c == 44:
        emit(T_COMMA, p, p + 1)
        continue
      if c == 34:
        stack.add state
        state = S_ESCAPED_TEXT
        emit(T_DQUOTE, p, p + 1)
        continue
      while q < n:
        let (d, size) = codePointAt(src, q)
        if not isTextData(d): break
        q += size
      emit(T_NON_ESCAPED_TEXT, p, q)
    # A character outside the CSV alphabet matches as empty text and is never consumed.
    if q == start:
      emit(T_STUCK, p, p)
      return

  emit((if state == S_ESCAPED_TEXT: T_ESCAPED_TEXT else: T_EOF), n, n)
  emit(T_END, n, n)
