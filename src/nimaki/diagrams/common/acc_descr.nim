## port-of: src/diagrams/common/accDescr.ts
## port-status: conformant
import std/strutils
import tokens
import ../../jsregex

const RE_HEAD = jsre"/[\t ]*accDescr(?:[\t ]*:(?:[^\n\r]*?(?=%%)|[^\n\r]*)|\s*({))/y"

proc scanner(): Scanner =
  ## The braced form scans for its closing brace. Once none is found there is none further on,
  ## so later braced descriptions fail without scanning the rest of the text again.
  var unclosed = false
  result = proc (src: string, at: int, previous: int): int =
    let m = RE_HEAD.exec(src, at)
    if not m.found: return -1
    let stop = m.stop
    if not m.has(1): return stop
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
