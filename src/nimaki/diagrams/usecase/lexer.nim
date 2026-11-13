## port-of: src/diagrams/usecase/lexer.ts
## port-status: draft
##
## Positions are byte offsets into the UTF-8 source (decision 0011). Every test here is of an
## ASCII character or of `c >= 128` (or `c < 127`), which read the same on bytes: every byte of a
## character that is not ASCII is 128 or more. Offsets in messages are counted in UTF-16 code
## units, as JavaScript counts them.
import std/strutils
import ../../errors
import ../../js
import ../../util/chars
import tokens

type Tokens* = object
  types*: seq[int]
  starts*: seq[int]
  ends*: seq[int]

const
  WORD = 1
  PUNCTUATION = 2

proc classTable(): array[128, int] =
  for c in 48 .. 57: result[c] = WORD
  for c in 65 .. 90:
    result[c] = WORD
    result[c + 32] = WORD
  result[95] = WORD
  for ch in "!#$&*+/=?^|~": result[ord(ch)] = PUNCTUATION

const CLASS = classTable()

const KEYWORD_LENGTH = [0, 12, 5, 14, 3, 9, 2, 2, 2, 2, 2, 4, 3, 4, 8, 5, 5, 7, 6, 4, 5]

template at(src: string, k: int): int =
  ## `src.charCodeAt(k)` on bytes: -1 (NaN) past the end.
  (if k >= 0 and k < src.len: ord(src[k]) else: -1)

func isWord(c: int): bool = c >= 0 and c < 128 and (CLASS[c] and WORD) != 0

func startsWith(src, word: string, at: int): bool =
  if at + word.len > src.len: return false
  for k in 0 ..< word.len:
    if src[at + k] != word[k]: return false
  true

# Mermaid's INCLUDE and EXTEND are the only keywords matched without regard to case.
func startsWithNoCase(src: string, at: int, word: string): bool =
  for k in 0 ..< word.len:
    if (src.at(at + k) or 32) != ord(word[k]): return false
  true

# The keyword that is a prefix of the text at `at`, tried in the order of Mermaid's token list.
func keywordAt(src: string, at, c: int): int =
  case c
  of 97: (if src.startsWith("actor", at): T_ACTOR else: 0)
  of 115:
    if src.startsWith("systemBoundary", at): T_SYSTEM_BOUNDARY
    elif src.startsWith("style", at): T_STYLE
    else: 0
  of 101:
    if src.startsWith("end", at): T_END
    elif startsWithNoCase(src, at, "extend"): T_EXTEND
    else: 0
  of 69: (if startsWithNoCase(src, at, "extend"): T_EXTEND else: 0)
  of 100: (if src.startsWith("direction", at): T_DIRECTION else: 0)
  of 84:
    if src.startsWith("TD", at): T_TD
    elif src.startsWith("TB", at): T_TB
    else: 0
  of 66: (if src.startsWith("BT", at): T_BT else: 0)
  of 76: (if src.startsWith("LR", at): T_LR else: 0)
  of 82: (if src.startsWith("RL", at): T_RL else: 0)
  of 110: (if src.startsWith("note", at): T_NOTE else: 0)
  of 102:
    if src.startsWith("for", at): T_FOR
    elif src.startsWith("false", at): T_FALSE
    else: 0
  of 106: (if src.startsWith("json", at): T_JSON else: 0)
  of 99:
    if src.startsWith("classDef", at): T_CLASS_DEF
    elif src.startsWith("class", at): T_CLASS
    else: 0
  of 105, 73: (if startsWithNoCase(src, at, "include"): T_INCLUDE else: 0)
  of 116: (if src.startsWith("true", at): T_TRUE else: 0)
  of 117: (if src.startsWith("usecase-beta", at): T_USECASE else: 0)
  else: 0

proc lineColumn*(src: string, offset: int): (int, int) =
  let (src, offset) = written(src, offset)
  var line = 1
  var lineStart = 0
  var i = 0
  while i < offset:
    let c = src.at(i)
    if c != 10 and c != 13:
      inc i
      continue
    if c == 13 and i + 1 < offset and src.at(i + 1) == 10: inc i
    inc line
    lineStart = i + 1
    inc i
  (line, utf16Len(src, lineStart, offset) + 1)

proc unitOffset(src: string, offset: int): int =
  ## `written(src, offset)[1]`, in UTF-16 code units.
  let (s, o) = written(src, offset)
  utf16Len(s, 0, o)

proc locationText*(src: string, start, stop: int): string =
  let (line, column) = lineColumn(src, start)
  "line " & $line & ", column " & $column & " [" & $unitOffset(src, start) & "," & $unitOffset(src, stop) & ")"

# The end of a quoted string that opens at `at`, or -1 when the line ends first.
func stringEnd(src: string, at, quote: int): int =
  for k in at + 1 ..< src.len:
    let c = ord(src[k])
    if c == quote: return k + 1
    if c == 10 or c == 13: return -1
  -1

func startsToken(src: string, at: int): bool =
  let c = src.at(at)
  if c != 34 and c != 39: return true
  (c == 34 and src.at(at + 1) == 96) or stringEnd(src, at, c) != -1

# Mermaid reports the first character no token starts with, and how many characters its lexer
# skipped before one did.
proc lexError(src: string, offset, length: int): ref PeleError =
  let (line, column) = lineColumn(src, offset)
  let first = unitOffset(src, offset)
  let last = unitOffset(src, offset + length)
  # The character is a quote or a line break: ASCII.
  let ch = if offset < src.len: $src[offset] else: ""
  newPeleError("Error lexing usecase diagram: unexpected character: ->" & ch & "<- at offset: " & $first &
               ", skipped " & $(last - first) & " characters. at line " & $line & ", column " & $column & " [" &
               $first & "," & $last & ")", "syntax", ErrorInfo(diagramType: "usecase", line: line, column: column))

proc tokenize*(src: string): Tokens =
  ## Produces the tokens of Mermaid's Chevrotain lexer for use case diagrams: the first pattern in
  ## its list that matches wins, a keyword gives way to a longer identifier, and `json id@` and `<<`
  ## switch to modes that read a JSON object and a stereotype.
  var types, starts, ends: seq[int]
  let n = src.len
  var i = 0
  # Whether only blanks came before on this line, where comments and accessibility lines may start.
  var lineStart = true
  var noBrace = false

  while i < n:
    let c = src.at(i)
    if c == 32 or c == 9:
      inc i
      continue
    var kind: int
    var stop = i + 1
    var fresh = false

    if c < 128 and (CLASS[c] and WORD) != 0:
      kind = 0
      var skip = false
      if c == 97 and lineStart and src.startsWith("acc", i):
        let descr = src.startsWith("Descr", i + 3)
        if descr or src.startsWith("Title", i + 3):
          var j = i + 8
          while isBlank(src.at(j)): inc j
          let next = src.at(j)
          if next == 58:
            kind = if descr: T_ACC_DESCR_LINE else: T_ACC_TITLE_LINE
            stop = j + 1
            while stop < n and src.at(stop) != 10 and src.at(stop) != 13: inc stop
          elif next == 123 and descr and not noBrace:
            let close = src.find('}', j + 1)
            if close == -1: noBrace = true
            else:
              kind = T_ACC_DESCR_BLOCK
              stop = close + 1
      elif c == 106 and src.startsWith("json", i) and isBlank(src.at(i + 4)):
        var j = i + 5
        while isBlank(src.at(j)): inc j
        let id = j
        while isWord(src.at(j)): inc j
        if j > id:
          while isBlank(src.at(j)): inc j
          if src.at(j) == 64:
            inc j
            while isBlank(src.at(j)): inc j
            if src.at(j) == 123:
              types.add T_JSON_DECLARATION_START
              starts.add i
              ends.add j
              i = j
              var depth = 0
              var quoted = false
              var escaped = false
              var k = j
              while k < n:
                let ch = ord(src[k])
                if quoted:
                  if escaped: escaped = false
                  elif ch == 92: escaped = true
                  elif ch == 34: quoted = false
                elif ch == 34: quoted = true
                elif ch == 123: inc depth
                elif ch == 125:
                  dec depth
                  if depth == 0: break
                inc k
              types.add(if k < n: T_JSON_OBJECT_LITERAL else: T_UNCLOSED_JSON_OBJECT_LITERAL)
              starts.add j
              i = if k < n: k + 1 else: n
              ends.add i
              lineStart = false
              skip = true
      if skip: continue
      if kind == 0:
        while stop < n and isWord(src.at(stop)): inc stop
        let keyword = keywordAt(src, i, c)
        if keyword != 0:
          # A keyword that is only the start of a longer word is an identifier.
          if keyword == T_USECASE or stop - i == KEYWORD_LENGTH[keyword]:
            kind = keyword
            stop = i + KEYWORD_LENGTH[keyword]
          else: kind = T_IDENTIFIER
        elif (c == 111 or c == 120) and src.at(i + 1) == 45 and src.at(i + 2) == 45:
          kind = if c == 111: T_BACKWARD_CIRCLE else: T_BACKWARD_CROSS
          stop = i + 3
        elif isDigit(c):
          # `1mg` is an identifier, and `1.5px` is a number because the identifier stops at the dot.
          var digits = i + 1
          while isDigit(src.at(digits)): inc digits
          if src.at(digits) == 46 and isDigit(src.at(digits + 1)):
            kind = T_NUMBER
            stop = digits + 2
            while isDigit(src.at(stop)): inc stop
            while isLetter(src.at(stop)): inc stop
          else: kind = T_IDENTIFIER
        else:
          kind = T_IDENTIFIER
          while src.at(stop) == 45 and isWord(src.at(stop + 1)):
            kind = T_CSS_IDENTIFIER
            stop += 2
            while isWord(src.at(stop)): inc stop
    elif c == 10:
      kind = T_NEWLINE
      fresh = true
    elif c == 13:
      kind = T_NEWLINE
      fresh = true
      if src.at(stop) == 10: inc stop
    elif c == 34 or c == 39:
      if c == 34 and src.at(i + 1) == 96:
        let close = src.find("`\"", i + 2)
        kind = if close == -1: T_UNCLOSED_MARKDOWN_STRING else: T_MARKDOWN_STRING
        stop = if close == -1: n else: close + 2
      else:
        kind = T_PLAIN_STRING
        stop = stringEnd(src, i, c)
        if stop == -1:
          var resume = i + 1
          while resume < n and not startsToken(src, resume): inc resume
          raise lexError(src, i, resume - i)
    elif c == 37:
      if lineStart and src.at(stop) == 37:
        kind = T_COMMENT
        while stop < n and src.at(stop) != 10 and src.at(stop) != 13: inc stop
      else: kind = T_PERCENT
    elif c == 45:
      if src.at(stop) != 45: kind = T_DASH
      else:
        while src.at(stop) == 45: inc stop
        let next = src.at(stop)
        let two = stop - i == 2
        if two and next == 124 and src.at(stop + 1) == 62:
          kind = T_GENERALIZATION
          stop += 2
        elif next == 62:
          kind = T_FORWARD_SOLID
          inc stop
        elif two and (next == 111 or next == 120):
          kind = if next == 111: T_FORWARD_CIRCLE else: T_FORWARD_CROSS
          inc stop
        else: kind = T_MARKERLESS_SOLID
    elif c == 46:
      let next = src.at(stop)
      if next == 46 and src.at(stop + 1) == 62:
        kind = T_DEPENDENCY_ARROW
        stop += 2
      elif isDigit(next):
        kind = T_NUMBER
        while isDigit(src.at(stop)): inc stop
        while isLetter(src.at(stop)): inc stop
      else: kind = T_DOT
    elif c == 60:
      if src.at(stop) == 60:
        types.add T_STEREOTYPE_START
        starts.add i
        ends.add i + 2
        lineStart = false
        i += 2
        if i >= n: break
        if src.at(i) == 62 and src.at(i + 1) == 62:
          kind = T_STEREOTYPE_END
          stop = i + 2
        else:
          var close = i
          var found = false
          while close < n:
            let ch = ord(src[close])
            if ch == 10 or ch == 13: break
            if ch == 62 and src.at(close + 1) == 62:
              found = true
              break
            inc close
          if found and jsTrim(src[i ..< close]) != "":
            types.add T_STEREOTYPE_TEXT
            starts.add i
            ends.add close
            kind = T_STEREOTYPE_END
            i = close
            stop = close + 2
          else:
            while close < n and src.at(close) != 10 and src.at(close) != 13: inc close
            if close == i:
              while close < n and (src.at(close) == 10 or src.at(close) == 13): inc close
              raise lexError(src, i, close - i)
            kind = T_UNCLOSED_STEREOTYPE_TEXT
            stop = close
      elif src.at(stop) == 45 and src.at(stop + 1) == 45:
        kind = T_BACKWARD_SOLID
        stop += 2
        while src.at(stop) == 45: inc stop
      else: kind = T_LABEL_PUNCTUATION
    elif c == 58:
      if src.at(stop) == 58 and src.at(stop + 1) == 58:
        kind = T_CLASS_SEPARATOR
        stop += 2
      else: kind = T_COLON
    elif c == 64:
      if src.at(stop) == 123:
        kind = T_METADATA_START
        inc stop
      else: kind = T_AT
    elif c == 123: kind = T_LBRACE
    elif c == 125: kind = T_RBRACE
    elif c == 91: kind = T_LBRACKET
    elif c == 93: kind = T_RBRACKET
    elif c == 40: kind = T_LPAREN
    elif c == 41: kind = T_RPAREN
    elif c == 44: kind = T_COMMA
    elif c == 35:
      while isHex(src.at(stop)): inc stop
      kind = if stop > i + 1: T_HASH_COLOR else: T_CSS_PUNCTUATION
    elif c == 92:
      if src.at(stop) == 44:
        kind = T_CSS_ESCAPED_COMMA
        inc stop
      else: kind = T_LABEL_PUNCTUATION
    elif c < 127 and c > 32:
      kind = if (CLASS[c] and PUNCTUATION) != 0: T_CSS_PUNCTUATION else: T_LABEL_PUNCTUATION
    else:
      kind = T_LABEL_SYMBOL
      while stop < n:
        let ch = ord(src[stop])
        if (ch >= 32 and ch < 127) or ch == 9 or ch == 10 or ch == 13: break
        inc stop

    types.add kind
    starts.add i
    ends.add stop
    i = stop
    lineStart = fresh

  for k in 0 ..< 3:
    types.add T_EOF
    starts.add n
    ends.add n
  Tokens(types: types, starts: starts, ends: ends)
