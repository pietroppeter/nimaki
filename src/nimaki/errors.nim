## port-of: src/errors.ts
## port-status: conformant
##
## Offsets here are byte offsets in UTF-8 text; `locate` turns the column into UTF-16 code units,
## as JavaScript counts it (decision 0011).
import std/strutils
import js

type
  PeleError* = object of CatchableError
    ## An error Pele throws. `code` is one of `unsupported-diagram`, `syntax`, `semantic`,
    ## `limit`; nimaki adds `unsupported` for a type it does not draw yet.
    code*: string
    diagramType*: string   ## Pele's `type` ("" for null)
    mermaidType*: string
    line*, column*: int
    snippet*: string

  JsRangeError* = object of CatchableError
    ## What JavaScript throws as a RangeError (a stack overflow, an invalid code point):
    ## render() reports it as a `limit` error, as Pele does.

  ErrorInfo* = object
    diagramType*, mermaidType*: string
    line*, column*: int
    snippet*: string

proc newPeleError*(message: string, code = "syntax", info = ErrorInfo()): ref PeleError =
  (ref PeleError)(msg: message, code: code, diagramType: info.diagramType,
                  mermaidType: info.mermaidType, line: info.line, column: info.column,
                  snippet: info.snippet)

proc newPeleError*(message, code, diagramType: string): ref PeleError =
  newPeleError(message, code, ErrorInfo(diagramType: diagramType))

type
  Edit* = tuple[first, last, length: int]
    ## Input range [first, last) replaced by `length` output bytes (`[from, to, length]`).

func stepInput(edits: seq[Edit], at: int): int =
  var shift = 0
  for (first, last, length) in edits:
    let start = first - shift
    if at < start: break
    if at < start + length: return first + min(at - start, last - first - 1)
    shift += last - first - length
  at + shift

func inputOffset*(steps: seq[seq[Edit]], at: int): int =
  result = at
  for s in countdown(steps.high, 0): result = stepInput(steps[s], result)

type
  Origin* = object
    parsed*: string
    find*: proc (offset: int): (string, int)

var origin: ref Origin

proc locatingIn*[T](next: Origin, run: proc (): T): T =
  ## Report positions in the original source while `run` parses.
  let outer = origin
  var o = new Origin
  o[] = next
  origin = o
  try:
    result = run()
  finally:
    origin = outer

proc written*(src: string, offset: int): (string, int) =
  ## Maps only when `src` is exactly the text being parsed.
  if origin != nil and src == origin.parsed: origin.find(offset) else: (src, offset)

proc locate*(src: string, offset: int): tuple[line, column: int, snippet: string] =
  var src = src
  var offset = offset
  # Keep EOF errors on the last content line.
  let stop = jsTrimEnd(src).len
  if stop > 0 and offset >= stop:
    # one code unit back is one code point back in UTF-8 for what precedes a trimmed end
    var k = stop - 1
    while k > 0 and (ord(src[k]) and 0xC0) == 0x80: dec k
    (src, offset) = written(src, k)
    offset += codePointAt(src, offset).size
  else:
    (src, offset) = written(src, offset)
  var line = 1
  var lineStart = 0
  var i = src.find('\n')
  while i != -1 and i < offset:
    inc line
    lineStart = i + 1
    i = src.find('\n', i + 1)
  var lineEnd = src.find('\n', offset)
  if lineEnd == -1: lineEnd = src.len
  let column = utf16Len(src, lineStart, offset) + 1
  let text = src[lineStart ..< max(lineStart, lineEnd)]
  (line, column, text & "\n" & repeat('-', column - 1) & "^")

proc syntaxError*(diagram, src: string, offset: int, detail: string,
                  lexical = false): ref PeleError =
  let loc = locate(src, offset)
  let head = if lexical: "Lexical error on line " & $loc.line & ". Unrecognized text."
             else: "Parse error on line " & $loc.line & ":"
  let message = if lexical: head & "\n" & loc.snippet else: head & "\n" & loc.snippet & "\n" & detail
  newPeleError(message, "syntax", ErrorInfo(diagramType: diagram, line: loc.line,
                                             column: loc.column, snippet: loc.snippet))
