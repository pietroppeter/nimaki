## port-of: src/diagrams/sankey/parser.ts
## port-status: draft
##
## Edits and error offsets are in bytes.
import std/[strutils, math]
import ../../errors
import ../../js
import ../../jsregex
import ../../text/entities
import db, lexer

const RE_LINE_BREAKS = jsre"/[\n\r]+/g"

func isInvalidXml(s: string): bool =
  ## RE_INVALID_XML.test(s): /[\x00-\x08\x0b\x0c\x0e-\x1f\ud800-\udfff\ufffe\uffff]/u. A
  ## scanner, as it must see a lone surrogate: a byte that is not valid UTF-8 counts as one.
  var i = 0
  while i < s.len:
    let (c, size) = codePointAt(s, i)
    if c == 0xFFFD and not s.continuesWith("�", i): return true
    if (c >= 0 and c <= 8) or c == 0x0b or c == 0x0c or (c >= 0x0e and c <= 0x1f) or
       c == 0xfffe or c == 0xffff: return true
    i += size

func isBlank(c: int): bool =
  if c == 10 or c == 13: return false
  if c < 128: return c == 32 or c == 9 or c == 11 or c == 12
  c == 0xa0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200a) or c == 0x2028 or c == 0x2029 or
    c == 0x202f or c == 0x205f or c == 0x3000 or c == 0xfeff

func blankAt(s: string, i: int): (bool, int) =
  ## Whether a blank starts at byte i, and its length.
  if i < 0 or i >= s.len: return (false, 0)
  let (c, size) = codePointAt(s, i)
  (isBlank(c), size)

func byteAt(s: string, i: int): int =
  if i >= 0 and i < s.len: ord(s[i]) else: -1

func trimRows(text: string, edits: var seq[Edit]): string =
  var stop = text.len
  while stop > 0:
    let k = prevRuneStart(text, stop)
    if not blankAt(text, k)[0]: break
    stop = k
  var kept = 0
  var quoted = false
  var i = 0
  while i < stop:
    let c = ord(text[i])
    if quoted:
      if c == 34:
        if byteAt(text, i + 1) == 34: inc i
        else: quoted = false
      inc i
    elif c == 34:
      quoted = true
      inc i
    else:
      let (blank, size) = blankAt(text, i)
      if blank:
        var j = i + size
        while true:
          let (more, len) = blankAt(text, j)
          if not more: break
          j += len
        let p = byteAt(text, i - 1)
        let q = byteAt(text, j)
        # Preserve blank first fields, which Mermaid accepts as empty names.
        if i == 0 or q == 10 or q == 13 or ((p == 10 or p == 13) and q != 44):
          result.add text[kept ..< i]
          edits.add (i, j, 0)
          kept = j
        i = j
      else:
        inc i
  if stop < text.len: edits.add (stop, text.len, 0)
  result.add text[kept ..< stop]

proc prepare(text: string, steps: var seq[seq[Edit]], track: bool): string =
  var edits: seq[Edit]
  let rows = trimRows(text, edits)
  let collapsed = rows.replace(RE_LINE_BREAKS, "\n")
  result = jsTrim(collapsed)
  if track:
    let lead = collapsed.len - jsTrimStart(collapsed).len
    steps.add edits
    steps.add replacements(rows, RE_LINE_BREAKS, 1)
    steps.add @[(0, lead, 0), (lead + result.len, collapsed.len, 0)]

proc prepareTextForParsing*(text: string): string =
  ## Unlike Mermaid's sankeyUtils, also trim row edges outside quoted fields.
  var steps: seq[seq[Edit]]
  prepare(text, steps, false)

func isFinite(x: float): bool = x.classify notin {fcNan, fcInf, fcNegInf}

proc parseSankey*(src: string, db: SankeyDb, source: string) =
  ## Report errors in `source`, the text before prepareTextForParsing.
  let toks = tokenize(src)
  let types = toks.types
  let texts = toks.texts
  let starts = toks.starts
  var i = 0

  proc error(at: int, detail: string): ref PeleError =
    var steps: seq[seq[Edit]]
    if source != src: discard prepare(source, steps, true)
    # Map EOF before the trimmed trailing blanks.
    var offset: int
    if at > 0 and at >= src.len:
      let last = prevRuneStart(src, src.len)
      offset = inputOffset(steps, last) + (src.len - last)
    else:
      offset = inputOffset(steps, at)
    syntaxError("sankey", source, offset, detail)

  proc fail(expected: string) =
    let t = types[i]
    let got = if t == T_STUCK: (if i > 0: TOKEN_NAMES[types[i - 1]] else: "undefined") else: TOKEN_NAMES[t]
    raise error(starts[i], "Expecting " & expected & ", got '" & got & "'")

  proc expect(kind: int, also = "") =
    if types[i] != kind: fail("'" & TOKEN_NAMES[kind] & "'" & also)
    inc i

  proc field(): string =
    if types[i] == T_NON_ESCAPED_TEXT:
      result = texts[i]
      inc i
      return
    if types[i] != T_DQUOTE: fail("'DQUOTE', 'NON_ESCAPED_TEXT'")
    inc i
    if types[i] != T_ESCAPED_TEXT: fail("'ESCAPED_TEXT'")
    result = texts[i]
    inc i
    expect(T_DQUOTE)

  proc name(): string =
    let start = starts[i]
    result = jsTrim(field()).replace("\"\"", "\"")
    # Entity codes can encode characters excluded by the lexer.
    if isInvalidXml(decodeEntities(result)):
      raise error(start, "Invalid XML character in node name")

  expect(T_SANKEY)
  expect(T_NEWLINE)
  while true:
    let fromName = name()
    expect(T_COMMA, ", 'NEWLINE', 'EOF'")
    let toName = name()
    expect(T_COMMA, ", 'NEWLINE', 'EOF'")
    let start = starts[i]
    # Keep Mermaid's numeric prefixes, but reject non-finite values.
    let value = jsParseFloat(field())
    if not value.isFinite: raise error(start, "Expecting a number")
    let s = db.findOrCreateNode(fromName)
    let t = db.findOrCreateNode(toName)
    db.addLink(s, t, value)
    if types[i] != T_NEWLINE: break
    inc i
  if types[i] == T_EOF: inc i
  if types[i] != T_END: fail("'NEWLINE', 'EOF'")
