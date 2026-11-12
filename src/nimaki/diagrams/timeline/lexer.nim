## port-of: src/diagrams/timeline/lexer.ts
## port-status: draft
import ../../util/chars
import ../common/scan

const
  T_END* = 0
  T_EOF* = 1
  T_INVALID* = 2
  T_NEWLINE* = 3
  T_timeline* = 4
  T_timeline_lr* = 5
  T_timeline_td* = 6
  T_title* = 7
  T_acc_title* = 8
  T_acc_title_value* = 9
  T_acc_descr* = 10
  T_acc_descr_value* = 11
  T_acc_descr_multiline_value* = 12
  T_section* = 13
  T_period* = 14
  T_event* = 15

const TOKEN_NAMES* = [
  "$end",
  "EOF",
  "INVALID",
  "NEWLINE",
  "timeline",
  "timeline_lr",
  "timeline_td",
  "title",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "section",
  "period",
  "event",
]

proc tokenize*(src: string): Tokens =
  ## Offsets are bytes. Where Pele steps one code unit over a character that may be outside
  ## ASCII, the port steps over the whole character (`sizeAt`).
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
    if keywordAt(src, p, "timeline"):
      e = p + 8
      while codeAt(src, e) == 32 or codeAt(src, e) == 9: inc e
      let lr = keywordAt(src, e, "lr")
      if e > p + 8 and (lr or keywordAt(src, e, "td")) and not isWord(codeAt(src, e + 2)):
        emit((if lr: T_timeline_lr else: T_timeline_td), e + 2)
        continue
      if not isWord(codeAt(src, p + 8)):
        emit(T_timeline, p + 8)
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
        emit(T_title, lineEnd(src, p + 5 + sizeAt(src, p + 5)))
        continue
    e = accessibility(src, p, output, T_acc_title)
    if e != p:
      p = e
      continue
    # Like Mermaid, a bare section uses the next line as its name.
    if keywordAt(src, p, "section") and isSpace(codeAt(src, p + 7)):
      e = p + 7 + sizeAt(src, p + 7)
      let first = e
      while e < n and codeAt(src, e) != 58 and codeAt(src, e) != 10: inc e
      if e > first:
        emit(T_section, e)
        continue
    if c != 58:
      # Bytes after the first: a byte of a longer character is none of #, : and a line break.
      e = p + 1
      while e < n and src[e] notin {'#', ':', '\n'}: inc e
      emit(T_period, e)
      continue
    # An event runs to the end of the line or to a colon that is followed by whitespace.
    if isSpace(codeAt(src, p + 1)):
      e = p + 1 + sizeAt(src, p + 1)
      let first = e
      while e < n:
        let k = src[e]
        if k == '\n' or (k == ':' and isSpace(codeAt(src, e + 1))): break
        inc e
      if e > first:
        emit(T_event, e)
        continue
    emit(T_INVALID, p + 1)

  # Jison marks its lexer done when a rule runs on empty input, so an accessibility value that
  # matches nothing at the very end of the text is followed by no EOF token.
  if output.starts.len == 0 or output.starts[^1] < n: emit(T_EOF, n)
  emit(T_END, n)
  output
