## port-of: src/diagrams/journey/lexer.ts
## port-status: draft
import ../../util/chars
import ../common/scan

const
  T_END* = 0
  T_EOF* = 1
  T_INVALID* = 2
  T_NEWLINE* = 3
  T_journey* = 4
  T_title* = 5
  T_acc_title* = 6
  T_acc_title_value* = 7
  T_acc_descr* = 8
  T_acc_descr_value* = 9
  T_acc_descr_multiline_value* = 10
  T_section* = 11
  T_taskName* = 12
  T_taskData* = 13
  T_colon* = 14

const TOKEN_NAMES* = [
  "$end",
  "EOF",
  "INVALID",
  "NEWLINE",
  "journey",
  "title",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "section",
  "taskName",
  "taskData",
  ":",
]

func textEnd(src: string, start: int, colon: bool): int =
  ## `#`, a line break, and `;` end every kind of text; a colon also ends a task name or a section.
  ## All are ASCII, so the loop steps byte by byte.
  let n = src.len
  var e = start
  while e < n:
    let c = src[e]
    if c == '#' or c == '\n' or c == ';' or (colon and c == ':'): break
    inc e
  e

proc tokenize*(src: string): Tokens =
  ## Offsets are bytes; where Pele steps over one character that may be outside ASCII, the port
  ## steps over the whole character (`sizeAt`).
  let n = src.len
  var output: Tokens
  var p = 0

  template emit(kind, e: int) =
    output.types.add kind
    output.texts.add src[p ..< e]
    output.starts.add p
    p = e

  while true:
    p = skipTrivia(src, p)
    if p >= n: break
    let c = codeAt(src, p)
    var e = p + 1
    if c == 10:
      while codeAt(src, e) == 10: inc e
      emit(T_NEWLINE, e)
      continue
    if keywordAt(src, p, "journey") and not isWord(codeAt(src, p + 7)):
      emit(T_journey, p + 7)
      continue
    if keywordAt(src, p, "title"):
      # Unlike Mermaid, ignore bare titles.
      e = p + 5
      while codeAt(src, e) != 10 and isSpace(codeAt(src, e)): e += sizeAt(src, e)
      if e == n or codeAt(src, e) == 10:
        p = e
        continue
      let sep = codeAt(src, p + 5)
      if sep != 13 and isSpace(sep):
        let first = p + 5 + sizeAt(src, p + 5)
        e = textEnd(src, first, false)
        if e > first:
          emit(T_title, e)
          continue
    e = accessibility(src, p, output, T_acc_title)
    if e != p:
      p = e
      continue
    # Like Mermaid, a bare section uses the next line as its name.
    if keywordAt(src, p, "section") and isSpace(codeAt(src, p + 7)):
      let first = p + 7 + sizeAt(src, p + 7)
      e = textEnd(src, first, true)
      if e > first:
        emit(T_section, e)
        continue
    if c == 58:
      e = textEnd(src, p + 1, false)
      emit((if e > p + 1: T_taskData else: T_colon), (if e > p + 1: e else: p + 1))
    elif c == 59:
      emit(T_INVALID, p + 1)
    else:
      emit(T_taskName, textEnd(src, p + 1, true))

  # Jison marks its lexer done when a rule runs on empty input, so an accessibility value that
  # matches nothing at the very end of the text is followed by no EOF token.
  if output.starts.len == 0 or output.starts[^1] < n: emit(T_EOF, n)
  emit(T_END, n)
  output
