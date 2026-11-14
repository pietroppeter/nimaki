## port-of: src/diagrams/ishikawa/lexer.ts
## port-status: conformant
##
## Offsets are bytes (decision 0011); the parser counts an indentation in UTF-16 code units.
import std/strutils
import ../../util/chars
import ../common/scan

const
  T_STOP* = 0 ## Pele's `T.END`
  T_EOF* = 1
  T_SPACELINE* = 2
  T_NL* = 3
  T_ISHIKAWA* = 4
  T_SPACELIST* = 5
  T_TEXT* = 6

const TOKEN_NAMES* = ["$end", "EOF", "SPACELINE", "NL", "ISHIKAWA", "SPACELIST", "TEXT"]

type IshTokens* = object
  types*: seq[int]
  starts*: seq[int]
  ends*: seq[int]

func keyword(src: string, at: int): int =
  const word = "ishikawa-beta"
  var k = 0
  while k < 13:
    let c = if at + k < src.len: ord(src[at + k]) else: -1
    let w = ord(word[k])
    if c != w and (c + 32 != w or c < 65 or c > 90): break
    inc k
  # `ishikawa-beta`, or failing that `ishikawa`, either one ending at a word boundary.
  if k == 13 and not isWord(codeAt(src, at + 13)): return 13
  if k >= 8 and not isWord(codeAt(src, at + 8)): 8 else: 0

proc tokenize*(src: string): IshTokens =
  ## Produces the tokens of Mermaid's Jison lexer for Ishikawa diagrams, where the first rule that
  ## matches wins: white space up to a comment or up to the last line break in it is a blank line,
  ## a single line break before text is a new line, other white space is indentation, and the rest
  ## of a line is text.
  let n = src.len
  var i = 0
  while i < n:
    var j = i
    var lastBreak = -1
    while j < n and isSpace(codeAt(src, j)):
      if src[j] == '\n': lastBreak = j
      j += sizeAt(src, j)
    var kind, stop: int
    if codeAt(src, j) == 37 and codeAt(src, j + 1) == 37:
      kind = T_SPACELINE
      stop = j + 2
      while stop < n:
        let c = codeAt(src, stop)
        if c == 10 or c == 13 or c == 0x2028 or c == 0x2029: break
        stop += sizeAt(src, stop)
    elif j == i:
      let length = keyword(src, i)
      if length > 0:
        kind = T_ISHIKAWA
        stop = i + length
      else:
        kind = T_TEXT
        stop = src.find('\n', i)
        if stop == -1: stop = n
    elif lastBreak > i:
      kind = T_SPACELINE
      stop = lastBreak + 1
    elif lastBreak == i:
      kind = T_NL
      stop = i + 1
    else:
      kind = T_SPACELIST
      stop = j
    result.types.add kind
    result.starts.add i
    result.ends.add stop
    i = stop
  result.types.add [T_EOF, T_STOP]
  result.starts.add [n, n]
  result.ends.add [n, n]
