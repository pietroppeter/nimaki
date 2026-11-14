## port-of: src/diagrams/common/scan.ts
## port-status: conformant
import std/strutils
import ../../js
import ../../util/chars

# Lexer rules that Mermaid's journey and timeline grammars have in common, ported from the
# compiled Jison rules: comments, whitespace, and the accTitle and accDescr statements.
#
# Offsets are bytes (decision 0011). `codeAt` reads the character at a byte as `charCodeAt`
# would: one code point, or -1 past the end (NaN in JavaScript, which no test matches). A code
# point above U+FFFF reads whole instead of as its first surrogate; no test here tells them apart.

type Tokens* = object
  types*: seq[int]
  texts*: seq[string]
  starts*: seq[int]

func codeAt*(src: string, p: int): int =
  if p < 0 or p >= src.len: -1 else: codePointAt(src, p).rune

func sizeAt*(src: string, p: int): int =
  ## The bytes of the character at `p` (1 past the end), the step of a `p++` over it.
  if p >= src.len: 1 else: codePointAt(src, p).size

func lineEnd*(src: string, start: int): int =
  let at = src.find('\n', start)
  if at == -1: src.len else: at

func keywordAt*(src: string, p: int, word: string): bool =
  ## `word` is lowercase ASCII letters; the grammars are case-insensitive.
  for i in 0 ..< word.len:
    if p + i >= src.len or (ord(src[p + i]) or 32) != ord(word[i]): return false
  true

func skipTrivia*(src: string, start: int): int =
  ## Skips comments and whitespace. Stops at a line break that starts a token, which is a NEWLINE.
  ## Jison compiles `\%%` to `%`, so a single `%` starts a comment.
  let n = src.len
  var p = start
  while p < n:
    let c = codeAt(src, p)
    if c == 37 and codeAt(src, p + 1) != 123:
      p = lineEnd(src, p)
    elif c == 10:
      return p
    elif isSpace(c):
      p += sizeAt(src, p)
      while p < n and isSpace(codeAt(src, p)): p += sizeAt(src, p)
    elif c == 35:
      p = lineEnd(src, p)
    else:
      return p
  p

func skipSpace(src: string, start: int): int =
  var p = start
  while isSpace(codeAt(src, p)): p += sizeAt(src, p)
  p

proc accessibility*(src: string, p: int, output: var Tokens, first: int): int =
  ## Lexes an accTitle or accDescr statement at `p` and returns where it ends, or `p` if there is
  ## none. The token types acc_title, acc_title_value, acc_descr, acc_descr_value and
  ## acc_descr_multiline_value must be numbered consecutively from `first`.
  let descr = keywordAt(src, p, "accdescr")
  if not descr and not keywordAt(src, p, "acctitle"): return p
  let n = src.len
  var q = skipSpace(src, p + 8)
  let c = codeAt(src, q)
  template emit(kind, s, e: int) =
    output.types.add kind
    output.texts.add src[s ..< e]
    output.starts.add s
  if c == 58:
    q = skipSpace(src, q + 1)
    let stop = lineEnd(src, q)
    emit((if descr: first + 2 else: first), p, q)
    emit((if descr: first + 3 else: first + 1), q, stop)
    return stop
  if not descr or c != 123: return p
  q = skipSpace(src, q + 1)
  while codeAt(src, q) != 125:
    var stop = src.find('}', q)
    if stop == -1: stop = n
    emit(first + 4, q, stop)
    if q == n: return n
    q = stop
  q + 1
