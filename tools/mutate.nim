## mutate: the referee on the corpus with one odd character slipped in. Each case of the corpus
## whose type nimaki draws is copied a few times, each copy with one character inserted at a
## seeded random place (between two characters, never inside one). Pele (in Node, through
## tools/oracle.mjs) and nimaki answer every copy, and the answers are compared byte for byte,
## errors included. The corpus is written by people, in ASCII mostly; this asks what happens to
## the same text with a character a reader's eye skips: a no-break space, a line separator, a
## byte order mark, a letter outside the Basic Multilingual Plane.
##
##   nim r tools/mutate.nim                 3 copies of every ported case, seed 7
##   options:
##     --copies:N        copies of each case (default 3)
##     --seed:S          the seed (default 7)
##     --show:N          print at most N differences as ERROR lines (default 10)
##     --out:PATH        write the summary and every difference as JSON (default build/mutate.json)
##     --package:PATH    the oracle package (default reference/npm/package or $PELE_PACKAGE)
import std/[os, osproc, strutils, json, random, parseopt, tables, strtabs, sequtils, unicode]
import common, verdict, answers
import nimaki

const inserts* = [
  (" ", "no-break space"), (" ", "line separator"), ("﻿", "byte order mark"),
  ("​", "zero-width space"), ("　", "ideographic space"), ("é", "é"), ("Ω", "Ω"),
  ("𝐀", "mathematical bold A (outside the BMP)"), ("😀", "emoji (outside the BMP)")]
const fixedNow = 1767225600000.0   ## 2026-01-01T00:00:00Z, as in tools/difftest.nim

func wellFormed(line: string): string =
  ## Pele's messages can hold half of a character: V8 quotes the first UTF-16 unit of the token
  ## it stopped at, and JSON.stringify writes it as a lone `\uD835`. Nim's JSON reader refuses a
  ## lone surrogate, so each is written as the bytes nimaki uses for one (WTF-8: the surrogate
  ## encoded as if it were a character), which the reader passes through.
  func surrogate(s: string, i: int): int =
    if i + 6 > s.len or s[i] != '\\' or s[i + 1] != 'u': return 0
    try:
      let v = parseHexInt(s[i + 2 ..< i + 6])
      if v >= 0xD800 and v <= 0xDBFF: 1 elif v >= 0xDC00 and v <= 0xDFFF: 2 else: 0
    except ValueError: 0
  var i = 0
  while i < line.len:
    if line[i] == '\\' and i + 1 < line.len and line[i + 1] != 'u':
      result.add line[i .. i + 1]
      i += 2
      continue
    let k = surrogate(line, i)
    if k == 1 and surrogate(line, i + 6) == 2:
      result.add line[i ..< i + 12]
      i += 12
    elif k != 0:
      let v = parseHexInt(line[i + 2 ..< i + 6])
      result.add char(0xE0 or (v shr 12))
      result.add char(0x80 or ((v shr 6) and 0x3F))
      result.add char(0x80 or (v and 0x3F))
      i += 6
    else:
      result.add line[i]
      inc i

func validUtf8(s: string): string =
  ## `s` with each byte that does not belong to a whole UTF-8 character replaced by U+FFFD: the
  ## excerpts of a verdict are cut at bytes, which can split a character.
  var i = 0
  while i < s.len:
    var bad = validateUtf8(s[i .. ^1])
    # a surrogate written as a character (0xED 0xA0..0xBF) is not UTF-8 either
    var j = i
    while j + 1 < s.len and (bad == -1 or j < i + bad):
      if s[j] == '\xED' and ord(s[j + 1]) >= 0xA0:
        bad = j - i
        break
      inc j
    if bad == -1:
      result.add s[i .. ^1]
      break
    result.add s[i ..< i + bad]
    result.add "\uFFFD"
    i += bad + (if s[i + bad] == '\xED' and i + bad + 2 < s.len: 3 else: 1)

proc main() =
  var copies = 3
  var seed = 7
  var show = 10
  var outPath = buildDir / "mutate.json"
  var packageArg = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "copies": copies = parseInt(val)
      of "seed": seed = parseInt(val)
      of "show": show = parseInt(val)
      of "out": outPath = val
      of "package": packageArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: quit "ERROR unexpected argument " & key, 2
    of cmdEnd: discard
  let package = packageDirFrom(packageArg)
  var r = initRand(seed)
  var cases: seq[JsonNode]
  var types: seq[string]
  var inserted: seq[int]
  for c in parseFile(repoDir / "corpus" / "cases.json")["cases"]:
    let src = c["source"].getStr
    if not supports(src): continue
    for k in 0 ..< copies:
      var p = r.rand(src.len)
      while p < src.len and (ord(src[p]) and 0xC0) == 0x80: inc p   # not inside a character
      let which = r.rand(inserts.high)
      cases.add %*{"id": c["id"].getStr & "#" & $k, "source": src[0 ..< p] & inserts[which][0] & src[p .. ^1],
                   "options": {"now": fixedNow}}
      types.add c["type"].getStr
      inserted.add which
  var input = ""
  for c in cases: input.add $c & "\n"
  let (output, code) = execCmdEx("node " & quoteShell(repoDir / "tools" / "oracle.mjs") & " " & quoteShell(package),
                                 env = {"TZ": "UTC", "PATH": getEnv("PATH")}.newStringTable, input = input)
  if code != 0: quit "ERROR the oracle failed:\n" & output[max(0, output.len - 2000) .. ^1], 2
  var pele: Table[string, Answer]
  for line in output.split('\n'):
    if line.len > 0:
      let j = parseJson(wellFormed(line))
      pele[j["id"].getStr] = toAnswer(j)
  var byType: OrderedTable[string, tuple[identical, different: int]]
  var differences = newJArray()
  var shown = 0
  for i, c in cases:
    let id = c["id"].getStr
    let o = compare(id, types[i], pele[id], nimakiAnswer(c["source"].getStr, c["options"]))
    if types[i] notin byType: byType[types[i]] = (0, 0)
    if o.verdict == vDifferent:
      inc byType[types[i]].different
      differences.add %*{"id": id, "type": types[i], "inserted": inserts[inserted[i]][1],
                         "source": c["source"].getStr, "detail": validUtf8(o.detail)}
      if shown < show:
        inc shown
        echo "ERROR ", id, " (", inserts[inserted[i]][1], "): ", o.detail
    else: inc byType[types[i]].identical
  byType.sort(proc (a, b: (string, tuple[identical, different: int])): int = cmp(a[0], b[0]))
  var rows = newJArray()
  var same, diff = 0
  for t, n in byType:
    rows.add %*{"type": t, "identical": n.identical, "different": n.different}
    same += n.identical
    diff += n.different
  createDir outPath.parentDir
  writeFile outPath, (%*{"pin": pinOf(package), "seed": seed, "copies": copies, "cases": cases.len,
    "identical": same, "different": diff, "inserts": inserts.mapIt(it[1]), "types": rows,
    "differences": differences}).pretty & "\n"
  echo "mutate: ", cases.len, " cases (", copies, " copies of each ported case, seed ", seed, "): ",
    same, " identical, ", diff, " different"
  echo "wrote ", outPath.relativePath(repoDir)
  if diff > 0: quit 1

when isMainModule:
  main()
