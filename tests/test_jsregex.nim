## Checks src/nimaki/jsregex.nim against Node: every regex literal of Pele (corpus/regexes.json,
## built by tools/pele_regexes.mjs) on strings made from its own characters and from the
## characters where JavaScript and the regex package disagree (whitespace beyond ASCII, letters
## with two cases, line ends, an emoji). For each regex and string: `exec` (at 0, and at a later
## `lastIndex` for a `g` or `y` regex), `replace` with `$` patterns, `split`, and every match of a
## `g` regex. Results that hold half of an emoji in JavaScript (a lone surrogate, which a UTF-8
## string cannot hold) are counted apart: that difference is in docs/divergences.md. The patterns
## the port builds from pieces (`new RegExp` in Pele) are checked the same way, as the port builds them.
import std/[os, osproc, json, random, unittest, unicode, strutils, sets]
import ../src/nimaki/jsregex
import ../src/nimaki/text/label {.all.}
import ../src/nimaki/svg/theme {.all.}
import ../src/nimaki/preprocess {.all.}
import ../src/nimaki/diagrams/common/tokens
from ../src/nimaki/diagrams/railroad/common as railroad import nil

const pool = [" ", "  ", "\t", "\n", "\r", "\r\n", " ", " ", "﻿", "\u0085", "　",
              "é", "É", "K", "ſ", "ß", "😀", "日本", "a", "Z", "0", "42", "-1.5", "_", "-", ":",
              "%%", "{", "}", "(", ")", "[", "]", "\"", "'", ",", ";", "#", "<br/>", "&amp;", "x"]

func runesOf(pattern: string): seq[string] =
  ## The characters a pattern names literally, and its words (`title`, `graph`...).
  var word = ""
  var i = 0
  while i < pattern.len:
    let c = pattern[i]
    if c == '\\':
      if i + 1 < pattern.len and pattern[i + 1] notin {'s', 'S', 'w', 'W', 'd', 'D', 'b', 'B', 'n',
                                                       'r', 't', 'u', 'x', 'v', 'f'}:
        result.add $pattern[i + 1]
      i += 2
      continue
    let n = runeLenAt(pattern, i)
    let ch = pattern[i ..< i + n]
    if c in {'a'..'z', 'A'..'Z'}: word.add c
    else:
      if word.len > 1: result.add word
      word = ""
    if c notin {'^', '$', '|', '?', '*', '+', '(', ')', '.'}: result.add ch
    i += n
  if word.len > 1: result.add word

proc flipCase(r: var Rand, s: string): string =
  for c in s:
    result.add(if r.rand(3) == 0: (if c.isUpperAscii: c.toLowerAscii else: c.toUpperAscii) else: c)

func show(v: JsonNode): string = ($v)[0 .. min(($v).len, 160) - 1]

proc main() =
  let data = parseFile(currentSourcePath.parentDir.parentDir / "corpus/regexes.json")
  var r = initRand(14)
  var cases = newJArray()   # [pattern, flags, text, k]: k is the code point where lastIndex starts
  var compiled: seq[JsRegExp]
  var sources: seq[(string, string)]
  for lit in data["literals"]: sources.add (lit["pattern"].getStr, lit["flags"].getStr)
  # Built from pieces: label's CJK classes, the font family list, the line breaks of preprocess,
  # a keyword, the titles that must not split a longer name, a style property in an edge.
  for built in [RE_CJK, RE_HINT, RE_PIECE, RE_FAMILIES, RE_LINE_BREAK, keyword("pie").pattern,
                keyword("C4Context").pattern, titleBefore(r"[-./\w]*[-\w]").pattern,
                titleBefore(r"\w").pattern, railroad.title(r"[A-Za-z0-9-]").pattern,
                railroad.title(r"[\w-]").pattern, newRegExp("[\";]" & "stroke" & ":([^;\"]+);")]:
    sources.add (built.source, built.flags)
  for (pattern, flags) in sources:
    compiled.add check(newRegExp(pattern, flags))
    let own = runesOf(pattern)
    var seen = initHashSet[string]()
    for n in 0 ..< 24:
      var s = ""
      for k in 0 ..< r.rand(0 .. 9):
        let piece = if own.len > 0 and r.rand(1) == 0: own[r.rand(own.high)] else: pool[r.rand(pool.high)]
        s.add(if 'i' in flags: flipCase(r, piece) else: piece)
      if s in seen: continue
      seen.incl s
      cases.add %*[compiled.high, pattern, flags, s, r.rand(0 .. max(0, s.runeLen))]
  let script = """
const cases = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const pack = (s, m) => m && [s.slice(0, m.index), ...[...m].map((g) => g === undefined ? null : g)];
const out = cases.map(([, pattern, flags, s, k]) => {
  const re = new RegExp(pattern, flags);
  const at = [...s].slice(0, k).join('').length;
  const res = { exec: pack(s, re.exec(s)) };
  if (re.global || re.sticky) { re.lastIndex = at; res.at = pack(s, re.exec(s)); }
  re.lastIndex = 0;
  res.replace = s.replace(re, "<$&|$1|$$|$'>");
  res.split = s.split(re).map((g) => g === undefined ? null : g);
  if (re.global) res.all = [...s.matchAll(re)].map((m) => m[0]);
  const lone = (v) => typeof v === 'string' ? !v.isWellFormed() : Array.isArray(v) ? v.some(lone) : false;
  return Object.values(res).some(lone) ? { lone: true } : { ...res, lone: false };
});
process.stdout.write(JSON.stringify(out));
"""
  let dir = getTempDir() / "nimaki-test-jsregex"
  createDir dir
  writeFile dir / "check.js", script
  let (output, code) = execCmdEx("node " & quoteShell(dir / "check.js"), input = $cases)
  doAssert code == 0, output
  let want = parseJson(output)
  var bad, lone, checked = 0
  proc pack(s: string, m: JsMatch): JsonNode =
    if not m.found: return newJNull()
    result = %*[s[0 ..< m.index]]
    for g in 0 ..< m.groups.len:
      result.add(if m.has(g): %m[g] else: newJNull())
  for i in 0 ..< cases.len:
    let c = cases[i]
    let w = want[i]
    if w["lone"].getBool:
      inc lone
      continue
    let re = compiled[c[0].getInt]
    let s = c[3].getStr
    var at = 0
    for k in 0 ..< c[4].getInt: at += runeLenAt(s, at)
    var got = newJObject()
    got["exec"] = pack(s, re.exec(s))
    if re.global or re.sticky: got["at"] = pack(s, re.exec(s, at))
    got["replace"] = %s.replace(re, "<$&|$1|$$|$'>")
    var parts = newJArray()
    for p in s.split(re): parts.add %p
    got["split"] = parts
    if re.global: got["all"] = %s.match(re)
    inc checked
    for start in [0, at]:
      let e = re.exec(s, start)
      if re.matchEnd(s, start) != (if e.found: e.stop else: -1):
        inc bad
        echo "ERROR /", re.source, "/", re.flags, " matchEnd at ", start, " on ", escapeJson(s)
    for key, v in got:
      var wv = w[key]
      if key == "split":     # a group that did not take part: undefined in JavaScript, "" here
        for e in wv.mitems:
          if e.kind == JNull: e = %""
      if v != wv:
        inc bad
        if bad <= 25:
          echo "ERROR /", re.source, "/", re.flags, " ", key, " on ", escapeJson(s), ": node ",
            show(wv), ", nimaki ", show(v)
  test "Pele's regexes, literal and built, as in Node (" & $compiled.len & " regexes, " & $checked &
      " strings; " & $lone & " with half an emoji in JavaScript not compared)":
    check bad == 0

  test "jsre: a literal translated at compile time":
    let spaces = jsre"/\n\s+/g"
    check "a\n   b\n\tc".replace(spaces, "\n") == "a\nb\nc"
    let token = jsre"/[A-Za-z_][\w-]*/y"
    let m = token.exec("  ab-c d", 2)
    check m.found and m[0] == "ab-c" and m.stop == 6
    check not token.exec("  ab-c d", 1).found

main()
