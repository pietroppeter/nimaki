## port-of: src/diagrams/treeview/boxDrawing.ts
## port-status: conformant
##
## Mermaid's box-drawing preprocessor: turns `├──`, `└──`, `│` (and the heavy variants) into the
## indentation the grammar reads.
##
## JavaScript indexes a line in UTF-16 code units, and Pele does its arithmetic on those indices:
## the depth of an entry is the index of its branch character divided by the width of a segment.
## A box character is one code unit and three bytes, so here the indices that enter arithmetic,
## and the ones the column maps take and give, are counted in code units; the slicing is in bytes.
import std/[strutils, tables]
import ../../errors
import ../../js

type
  PreprocessResult* = object
    text*: string
    lineMap*: Table[int, int]
      ## Output line number to original line number, both from 1. Empty when the text is unchanged.
    columns*: Table[int, proc (at: int): int]
      ## Per output line, maps rewritten indices to original indices (UTF-16 code units).

const INDENT_UNIT = "    "

func isBranch(c: int): bool = c == 0x2514 or c == 0x2517 or c == 0x251c or c == 0x2523   # [└┗├┣]
func isDash(c: int): bool = c == 0x2500 or c == 0x2501                                   # [─━]
func isVertical(c: int): bool = c == 0x2502 or c == 0x2503                               # [│┃]
func isBoxChar(c: int): bool = isBranch(c) or isDash(c) or isVertical(c)    # [─━│┃└┗├┣]

func hasBoxChar(s: string): bool =
  ## ALL_BOX_CHARS.test(s)
  var i = 0
  while i < s.len:
    let (c, size) = codePointAt(s, i)
    if isBoxChar(c): return true
    i += size
  false

func onlyOf(s: string, allowed: proc (c: int): bool {.noSideEffect.}): bool =
  ## /^[\s<allowed>]+$/.test(s)
  if s.len == 0: return false
  var i = 0
  while i < s.len:
    let (c, size) = codePointAt(s, i)
    if not (isJsSpace(c) or allowed(c)): return false
    i += size
  true

func decorationOnly(s: string): bool = onlyOf(s, isVertical)   # DECORATION_ONLY = /^[\s│┃]+$/
func boxOnly(s: string): bool = onlyOf(s, isBoxChar)           # BOX_ONLY = /^[\s─━│┃└┗├┣]+$/

func afterSpaces(s: string): int =
  ## where /^\s*/ ends
  result = 0
  while true:
    let n = spaceLenAt(s, result)
    if n == 0: break
    result += n

func blanksFrom(s: string, i: int): int =
  result = i
  while result < s.len and s[result] in {'\t', ' '}: inc result

func metadataLine(s: string): bool =
  ## METADATA_LINE = /^\s*(title[\t ]|accTitle[\t ]*:|accDescr[\t ]*[:{])/
  let i = afterSpaces(s)
  if s.continuesWith("title", i): return i + 5 < s.len and s[i + 5] in {'\t', ' '}
  if s.continuesWith("accTitle", i):
    let j = blanksFrom(s, i + 8)
    return j < s.len and s[j] == ':'
  if s.continuesWith("accDescr", i):
    let j = blanksFrom(s, i + 8)
    return j < s.len and s[j] in {':', '{'}
  false

func commentLine(s: string): bool = s.continuesWith("%%", afterSpaces(s))   # COMMENT_LINE = /^\s*%%/

func expandTabs(s: string): string = s.replace("\t", "    ")   # s.replace(/\t/g, '    ')

func branchAt(s: string): int =
  ## The byte index of the first branch character, or -1 (BRANCH_CHAR.exec(s)).
  var i = 0
  while i < s.len:
    let (c, size) = codePointAt(s, i)
    if isBranch(c): return i
    i += size
  -1

func isBoxDrawingFormat*(lines: seq[string]): bool =
  for line in lines:
    if hasBoxChar(line): return true
  false

func inferSegmentWidth(contentLines: seq[string]): int =
  for line in contentLines:
    let at = branchAt(line)
    if at > 0:
      let index = utf16Len(line, 0, at)
      if index > 0: return index
  4

func remapErrorLines*(message: string, lineMap: Table[int, int]): string =
  ## message.replace(/\bline\s+(\d+)\b/gi, ...): the line numbers the map knows become the
  ## original ones.
  var i = 0
  while i < message.len:
    if (i == 0 or not isWordChar(message[i - 1])) and i + 4 <= message.len and
        message[i ..< i + 4].toLowerAscii == "line":
      var j = i + 4
      let spaced = j
      while true:
        let n = spaceLenAt(message, j)
        if n == 0: break
        j += n
      let digitsFrom = j
      while j < message.len and message[j] in {'0'..'9'}: inc j
      if j > spaced and digitsFrom > spaced and j > digitsFrom and
          (j >= message.len or not isWordChar(message[j])):
        let original = lineMap.getOrDefault(parseInt(message[digitsFrom ..< j]), 0)
        result.add(if original != 0: "line " & $original else: message[i ..< j])
        i = j
        continue
    result.add message[i]
    inc i

func lineStart*(text: string, line: int): int =
  ## The byte offset where line `line` (from 1) starts.
  var at = 0
  for n in 1 ..< line: at = text.find('\n', at) + 1
  at

proc fail(input: string, index: int, message: string) {.noreturn.} =
  let line = locate(input, lineStart(input, index + 1)).line
  raise newPeleError("Line " & $line & ": " & message, "syntax",
                     ErrorInfo(diagramType: "treeView", line: line))

func beforeTabs(line: string, at: int): int =
  ## Undo four-space tab expansion, in code units.
  var n = 0
  for unit in codeUnits(line):
    if n >= at: break
    n += (if unit == 9: 4 else: 1)
    inc result

proc columnMap(line: string, start, indentLen: int): proc (at: int): int =
  ## A closure of its own per line: closures made in a loop would share the loop's variables.
  result = proc (at: int): int = beforeTabs(line, start + max(at - indentLen, 0))

proc preprocessBoxDrawing*(input: string): PreprocessResult =
  var lineMap = initTable[int, int]()
  var columns = initTable[int, proc (at: int): int]()
  if not hasBoxChar(input): return PreprocessResult(text: input, lineMap: lineMap, columns: columns)
  let lines = input.split('\n')

  var keywordIdx = -1
  for i in 0 ..< lines.len:
    if jsTrim(lines[i]) == "treeView-beta":
      keywordIdx = i
      break
  if keywordIdx == -1: return PreprocessResult(text: input, lineMap: lineMap, columns: columns)

  proc passes(line: string): bool = jsTrim(line) == "" or commentLine(line) or metadataLine(line)

  var contentLines: seq[string]
  for i in keywordIdx + 1 ..< lines.len:
    let line = lines[i]
    if passes(line) or decorationOnly(line): continue
    contentLines.add expandTabs(line)
  if not isBoxDrawingFormat(contentLines):
    return PreprocessResult(text: input, lineMap: lineMap, columns: columns)

  let segmentWidth = inferSegmentWidth(contentLines)
  var output: seq[string]
  proc keep(text: string, index: int, column: proc (at: int): int = nil) =
    output.add text
    lineMap[output.len] = index + 1
    if column != nil: columns[output.len] = column

  for i in 0 .. keywordIdx: keep(lines[i], i)
  for i in keywordIdx + 1 ..< lines.len:
    let line = lines[i]
    if passes(line):
      keep(line, i)
      continue
    if decorationOnly(line): continue

    let normalized = expandTabs(line)
    let branch = branchAt(normalized)
    if branch >= 0:
      let index = utf16Len(normalized, 0, branch)
      let depth = int(jsRound(index / segmentWidth)) + 1
      var pos = branch + 3                      # a branch character is three bytes
      var units = index + 1
      while pos < normalized.len:
        let (c, size) = codePointAt(normalized, pos)
        if not isDash(c): break
        pos += size
        inc units
      while pos < normalized.len and normalized[pos] == ' ':
        inc pos
        inc units
      let content = jsTrimEnd(normalized[pos .. ^1])
      if content == "":
        fail(input, i, "Empty node — expected a filename or directory name after the box-drawing prefix")
      let indent = INDENT_UNIT.repeat(depth)
      keep(indent & content, i, columnMap(line, units, indent.len))
    elif boxOnly(normalized):
      continue
    elif hasBoxChar(normalized):
      # A name that happens to contain a box character, such as "Section ─ A.txt", is a root item.
      keep(line, i)
    elif spaceLenAt(normalized, 0) > 0:
      fail(input, i,
        "Unexpected indentation without box-drawing characters. In box-drawing format, use ├── or └── prefixes for indented nodes.")
    else:
      keep(line, i)
  PreprocessResult(text: output.join("\n"), lineMap: lineMap, columns: columns)
