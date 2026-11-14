## Builds src/nimaki/util/idna_data.nim: the tables that `new URL()` in the oracle's Node uses to
## write a host outside ASCII (IDNA, UTS #46). Node parses URLs with ada (MIT, Copyright 2023
## Yagiz Nizipli and Daniel Lemire); its IDNA code and tables are one C++ file, `src/ada_idna.cpp`.
## This reads the tables from that file, at the version of ada that the oracle's Node reports
## (`node -p process.versions.ada`):
##
##   nim r tools/idna_data.nim            (fetches ada_idna.cpp into build/ada/ with curl)
##   nim r tools/idna_data.nim FILE       (reads FILE instead)
##
## Run it again only when the oracle's Node moves to another ada.
import std/[os, osproc, strutils, strformat, sequtils]

const AdaVersion = "2.9.2"

let repo = currentSourcePath().parentDir.parentDir
var source = if paramCount() >= 1: paramStr(1) else: repo / "build/ada/ada_idna.cpp"
if paramCount() == 0 and not fileExists(source):
  createDir(source.parentDir)
  let url = &"https://raw.githubusercontent.com/ada-url/ada/v{AdaVersion}/src/ada_idna.cpp"
  let (output, code) = execCmdEx(&"curl -sSfL -o {quoteShell(source)} {url}")
  if code != 0: quit "ERROR could not fetch " & url & ": " & output.strip, 1
let cpp = readFile(source)

proc body(start: string): string =
  ## The text between the braces of the declaration that starts with `start`.
  let at = cpp.find(start)
  if at < 0: quit "ERROR ada_idna.cpp has no `" & start & "`", 1
  let open = cpp.find('{', at)
  var depth = 0
  for i in open ..< cpp.len:
    if cpp[i] == '{': inc depth
    elif cpp[i] == '}':
      dec depth
      if depth == 0: return cpp[open + 1 ..< i]
  quit "ERROR unclosed `" & start & "`", 1

proc parseInt(s: string): int =
  if s.startsWith("0x") or s.startsWith("0X"): strutils.parseHexInt(s) else: strutils.parseInt(s)

proc numbers(text: string): seq[int] =
  var i = 0
  while i < text.len:
    if text[i] in Digits:
      var j = i
      while j < text.len and text[j] in HexDigits + {'x', 'X'}: inc j
      result.add parseInt(text[i ..< j])
      i = j
    else: inc i

proc wrap(items: seq[string]): string =
  var line = "  "
  var lines: seq[string]
  for it in items:
    if line.len + it.len + 2 > 100:
      lines.add line.strip(leading = false)
      line = "  "
    line.add it & ", "
  if line.strip != "": lines.add line.strip(leading = false).strip(chars = {','}, leading = false)
  lines.join("\n")

let ident = cpp.find("// IDNA ")
let unicode = if ident >= 0: cpp[ident + 8 ..< cpp.find('\n', ident)].strip else: "?"
var text = &"""## The tables of IDNA (UTS #46, Unicode {unicode}) as ada {AdaVersion} has them, the URL parser of
## the oracle's Node (MIT, Copyright 2023 Yagiz Nizipli and Daniel Lemire). Written by
## tools/idna_data.nim from ada's src/ada_idna.cpp: do not edit. `idna.nim` reads them.

type IdnaDirection* = enum
"""
# The directions, in the order of ada's enum (their numbers do not matter here).
let dirs = body("enum direction").split(',')
var dirNames: seq[string]
for d in dirs:
  let n = d.strip
  if n != "": dirNames.add n
text.add wrap(dirNames.mapIt("d" & it)) & "\n"

let mappings = numbers(body("const uint32_t mappings["))
text.add &"\nconst idnaMappings*: array[{mappings.len}, int32] = [\n"
text.add wrap(mappings.mapIt($it)) & "]\n"

# Flat arrays rather than arrays of tuples: nim js writes a tuple as an object with named fields,
# which would make these tables three times as large in the JavaScript build.
let tableNums = numbers(body("const uint32_t table["))
var starts, descriptors: seq[string]
for i in countup(0, tableNums.len - 1, 2):
  starts.add $tableNums[i]
  descriptors.add $tableNums[i + 1]
text.add "\n## The ranges of code points, by their first one, and what each range does (its descriptor):\n"
text.add "## the low byte is 0 ignored, 1 valid, 2 disallowed, or else a mapping,\n"
text.add "## `count shl 24 or index shl 8` into idnaMappings.\n"
text.add &"const idnaStarts*: array[{starts.len}, int32] = [\n" & wrap(starts) & "]\n"
text.add &"const idnaDescriptors*: array[{descriptors.len}, uint32] = [\n" & wrap(descriptors) & "]\n"

let dirBody = body("static directions dir_table[]")
var firsts, lasts, kinds: seq[string]
for entry in dirBody.split('}'):
  let e = entry.strip(chars = Whitespace + {',', '{'})
  if e == "": continue
  let parts = e.split(',')
  firsts.add $parseInt(parts[0].strip)
  lasts.add $parseInt(parts[1].strip)
  kinds.add "d" & parts[2].strip.replace("direction::", "")
text.add "\n## The writing direction (Bidi class) of ranges of code points: first, last, direction.\n"
text.add &"const idnaDirFirst*: array[{firsts.len}, int32] = [\n" & wrap(firsts) & "]\n"
text.add &"const idnaDirLast*: array[{lasts.len}, int32] = [\n" & wrap(lasts) & "]\n"
text.add &"const idnaDirKind*: array[{kinds.len}, IdnaDirection] = [\n" & wrap(kinds) & "]\n"

for (name, decl) in [("idnaCombining", "constexpr static uint32_t combining[]"),
                     ("idnaVirama", "constexpr static uint32_t virama[]"),
                     ("idnaJoiningR", "constexpr static uint32_t R[]"),
                     ("idnaJoiningL", "constexpr static uint32_t L[]"),
                     ("idnaJoiningD", "constexpr static uint32_t D[]")]:
  let ns = numbers(body(decl))
  text.add &"\nconst {name}*: array[{ns.len}, int32] = [\n" & wrap(ns.mapIt($it & "")) & "]\n"

let target = repo / "src/nimaki/util/idna_data.nim"
writeFile(target, text)
echo &"idna_data: ada {AdaVersion}, IDNA {unicode}: {starts.len} ranges, {mappings.len} mapped code points, {firsts.len} directions -> {target}"
