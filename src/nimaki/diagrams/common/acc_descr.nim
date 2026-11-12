## port-of: src/diagrams/common/accDescr.ts
## port-status: draft
import std/strutils
import tokens
import ../../js

func headEnd(src: string, at: int): tuple[stop: int, braced: bool] =
  ## RE_HEAD: /[\t ]*accDescr(?:[\t ]*:(?:[^\n\r]*?(?=%%)|[^\n\r]*)|\s*({))/y, where it ends
  ## (-1 for no match), and whether it took the braced form.
  var i = at
  while i < src.len and src[i] in {'\t', ' '}: inc i
  if not src.continuesWith("accDescr", i): return (-1, false)
  i += 8
  var j = i
  while j < src.len and src[j] in {'\t', ' '}: inc j
  if j < src.len and src[j] == ':':
    var stop = j + 1
    while stop < src.len and src[stop] notin {'\n', '\r'}: inc stop
    let comment = src.find("%%", j + 1)
    return ((if comment != -1 and comment < stop: comment else: stop), false)
  while true:
    let n = spaceLenAt(src, i)
    if n == 0: break
    i += n
  if i < src.len and src[i] == '{': (i + 1, true) else: (-1, false)

proc scanner(): Scanner =
  ## The braced form scans for its closing brace. Once none is found there is none further on,
  ## so later braced descriptions fail without scanning the rest of the text again.
  var unclosed = false
  result = proc (src: string, at: int, previous: int): int =
    let (stop, braced) = headEnd(src, at)
    if stop < 0: return -1
    if not braced: return stop
    if unclosed: return -1
    let close = src.find('}', stop)
    unclosed = close == -1
    if close == -1: -1 else: close + 1

proc accDescr*(name = "ACC_DESCR"): TokenType =
  ## The common accDescr terminal for grammars where lexing goes on after an `accDescr {` that
  ## never closes, because `accDescr` is also a name there. Each one would otherwise read to the
  ## end of the text.
  result = TokenType()
  result[] = ACC_DESCR[]
  result.name = name
  result.scanner = scanner
