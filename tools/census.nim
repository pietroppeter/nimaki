## The census of nimaki's own code: how big each part of `src/` is beside the TypeScript it
## ports, which shared modules the diagram types use, how the parts import each other, and the
## regular expressions the port wrote by hand more than once. The articles on the code read it;
## each freezes one census under its data folder, so its numbers stay the ones it was written
## with.
##
##   nim r tools/census.nim                   print the summary, write build/census.json
##   nim r tools/census.nim --out:PATH        write the census to PATH instead
##   options: --ref:PATH (a Pele checkout; default reference/pele or $PELE_REF)
##
## A line of code is a line that is not blank and not only a comment, in Nim as the port map
## counts it in TypeScript. An import is followed only to files of `src/`. A regex helper is a
## proc whose first doc line quotes a JavaScript regular expression literal, `/.../flags`, as
## the porting guide asks a hand-written scanner to do; for a pattern written more than once, the
## census also counts the files of Pele that hold it literally.
import std/[os, strutils, tables, sets, json, algorithm, parseopt, osproc, times, sequtils]
import common
import portmap except main

const srcRoot = repoDir / "src"

type
  NimFile = object
    path: string           ## relative to src/nimaki (or `nimaki.nim`)
    area: string           ## `core`, `util`, `text`, `svg`, `layout`, `diagrams/common`, `diagrams/<type>`
    code: int
    origins: seq[string]
    status: string
    imports: seq[string]   ## other files of src/, same form as `path`

func nimCode(text: string): int =
  for raw in text.splitLines:
    let line = raw.strip
    if line.len > 0 and not line.startsWith("#"): inc result

func areaOf(path: string): string =
  let parts = path.split('/')
  if parts.len == 1: "core"
  elif parts[0] == "diagrams": "diagrams/" & parts[1]
  else: parts[0]

proc relOf(abs: string): string =
  let base = srcRoot / "nimaki"
  if abs.startsWith(base & DirSep): abs[base.len + 1 .. ^1].unixPath
  else: abs.extractFilename

proc importsOf(abs, text: string): seq[string] =
  ## The files of src/ this file imports: `import a, b/[c, d] as e`, `from a import b`.
  let dir = abs.parentDir
  for raw in text.splitLines:
    var line = raw.strip
    if line.startsWith("from "):
      line = line[5 .. ^1]
      let i = line.find(" import ")
      if i >= 0: line = line[0 ..< i]
    elif line.startsWith("import "):
      line = line[7 .. ^1]
    else: continue
    let hash = line.find('#')
    if hash >= 0: line = line[0 ..< hash]
    # split on commas outside brackets
    var items: seq[string]
    var depth = 0
    var cur = ""
    for c in line:
      if c == '[': inc depth
      elif c == ']': dec depth
      if c == ',' and depth == 0:
        items.add cur.strip
        cur = ""
      else: cur.add c
    if cur.strip.len > 0: items.add cur.strip
    for item in items:
      var names: seq[string]
      let open = item.find('[')
      if open >= 0:
        let base = item[0 ..< open].strip(chars = {'/', ' '})
        let close = item.find(']')
        for n in item[open + 1 ..< close].split(','):
          let name = n.strip.split(' ')[0]
          names.add(if base.len > 0: base & "/" & name else: name)
      else:
        names.add item.split(' ')[0]
      for name in names:
        if name.startsWith("std/") or name.len == 0: continue
        for candidate in [dir / name & ".nim", srcRoot / name & ".nim"]:
          let full = candidate.normalizedPath
          if fileExists(full) and full.startsWith(srcRoot):
            result.add relOf(full)
            break

func regexIn(doc: string): tuple[found: bool, pattern, flags: string] =
  ## The first JavaScript regex literal in a doc line: a `/` not after a letter, digit or `/`,
  ## not followed by a space; up to the next `/` outside a character class; then its flags.
  var i = 0
  while i < doc.len:
    if doc[i] == '/' and (i == 0 or doc[i - 1] notin {'a'..'z', 'A'..'Z', '0'..'9', '/', '.', '_'}) and
       i + 1 < doc.len and doc[i + 1] notin {' ', '/'}:
      var j = i + 1
      var inClass = false
      while j < doc.len:
        let c = doc[j]
        if c == '\\': j += 2; continue
        if c == '[': inClass = true
        elif c == ']': inClass = false
        elif c == '/' and not inClass: break
        inc j
      if j < doc.len:
        var k = j + 1
        while k < doc.len and doc[k] in {'d', 'g', 'i', 'm', 's', 'u', 'v', 'y'}: inc k
        if k >= doc.len or doc[k] notin {'a'..'z', 'A'..'Z', '0'..'9'}:
          return (true, doc[i + 1 ..< j], doc[j + 1 ..< k])
      i = j
    inc i

proc lexers(files: seq[NimFile]): JsonNode =
  ## How each diagram type reads its text: `table` (the shared tokenizer of
  ## diagrams/common/tokens.nim, driven by a table of token types), `jison` (a lexer.nim of its
  ## own, Jison's compiled rules written by hand), `outline` (the indentation reader of
  ## diagrams/common/outline.nim), or `borrowed` (another type's parser). For each: the lines of
  ## code of its lexer.nim and tokens.nim, and the start conditions its lexer declares (`S_...`).
  result = newJArray()
  var types: OrderedTable[string, seq[NimFile]]
  for f in files:
    if f.area.startsWith("diagrams/") and f.area != "diagrams/common":
      types.mgetOrPut(f.area.split('/')[1], @[]).add f
  var names = toSeq(types.keys)
  names.sort
  for t in names:
    var family = "borrowed"
    var code, states = 0
    for f in types[t]:
      let base = f.path.split('/')[^1]
      if base in ["lexer.nim", "tokens.nim"]: code += f.code
      if base == "lexer.nim":
        family = "jison"
        for line in readFile(srcRoot / "nimaki" / f.path).splitLines:
          let l = line.strip
          if l.startsWith("S_") and " = " in l and l.split(" = ")[1].strip.allCharsInSet(Digits): inc states
    if family != "jison":
      for f in types[t]:
        for d in f.imports:
          if d == "diagrams/common/tokens.nim": family = "table"
          elif d == "diagrams/common/outline.nim" and family != "table": family = "outline"
    result.add %*{"type": t, "family": family, "code": code, "states": states}

proc census(refDir: string): JsonNode =
  var files: seq[NimFile]
  for abs in walkDirRec(srcRoot):
    if not abs.endsWith(".nim"): continue
    let text = readFile(abs)
    let rel = relOf(abs)
    var f = NimFile(path: rel, area: areaOf(rel), code: nimCode(text), status: "")
    var n = 0
    for line in text.splitLines:
      inc n
      if n > 30: break
      let t = line.strip(chars = {'#', ' '})
      for key in ["port-of:", "port-part-of:"]:
        if t.startsWith(key): f.origins.add t[key.len .. ^1].strip.split(' ')[0]
      if t.startsWith("port-status:"): f.status = t[12 .. ^1].strip.split(' ')[0]
    f.imports = importsOf(abs, text)
    files.add f
  files.sort(proc (a, b: NimFile): int = cmp(a.path, b.path))

  # TypeScript lines of code, by file, as the port map counts them
  var ts: Table[string, int]
  for path in tsFiles(refDir): ts[path] = measure(readFile(refDir / path)).code

  # areas: Nim code, TypeScript code of the files they port (each counted once), files without origin
  var areaNim, areaPorted, areaFiles: OrderedTable[string, int]
  var areaTs: Table[string, HashSet[string]]
  var noOrigin = newJArray()
  var statuses: CountTable[string]
  for f in files:
    areaNim.mgetOrPut(f.area, 0) += f.code
    areaFiles.mgetOrPut(f.area, 0) += 1
    areaPorted.mgetOrPut(f.area, 0) += (if f.origins.len > 0: f.code else: 0)
    for o in f.origins: areaTs.mgetOrPut(f.area, initHashSet[string]()).incl o
    if f.origins.len == 0: noOrigin.add %*{"path": f.path, "code": f.code}
    else: statuses.inc(if f.status.len > 0: f.status else: "none")
  var areas = newJArray()
  var names = toSeq(areaNim.keys)
  names.sort
  for a in names:
    var t = 0
    for o in areaTs.getOrDefault(a): t += ts.getOrDefault(o)
    areas.add %*{"area": a, "files": areaFiles[a], "nim": areaNim[a], "ported": areaPorted[a], "ts": t}

  # imports: which areas use which shared modules, and imports between diagram types
  var fanIn: Table[string, HashSet[string]]
  var between: CountTable[string]
  var upward = newJArray()
  for f in files:
    for d in f.imports:
      let to = areaOf(d)
      if to == f.area: continue
      let isType = f.area.startsWith("diagrams/") and f.area != "diagrams/common"
      if isType and (not to.startsWith("diagrams/") or to == "diagrams/common"):
        fanIn.mgetOrPut(d, initHashSet[string]()).incl f.area
      if f.area.startsWith("diagrams/") and to.startsWith("diagrams/") and to != "diagrams/common":
        between.inc(f.area & " -> " & to)
      if not f.area.startsWith("diagrams/") and f.area != "core" and to.startsWith("diagrams/"):
        upward.add %*{"from": f.path, "to": d}
  var shared = newJArray()
  var mods = toSeq(fanIn.keys)
  mods.sort(proc (a, b: string): int =
    result = cmp(fanIn[b].len, fanIn[a].len)
    if result == 0: result = cmp(a, b))
  for m in mods:
    var users = toSeq(fanIn[m])
    users.sort
    shared.add %*{"module": m, "types": users}
  var crossing = newJArray()
  var pairs = toSeq(between.keys)
  pairs.sort
  for p in pairs:
    let parts = p.split(" -> ")
    crossing.add %*{"from": parts[0], "to": parts[1], "imports": between[p]}

  # regex helpers: the same JavaScript regex, written as a scanner in several places
  var helpers: OrderedTable[string, seq[JsonNode]]
  for f in files:
    let lines = readFile(srcRoot / (if f.path == "nimaki.nim": f.path else: "nimaki" / f.path)).splitLines
    for i, line in lines:
      if not (line.startsWith("proc ") or line.startsWith("func ")) or i + 1 >= lines.len: continue
      let doc = lines[i + 1].strip
      if not doc.startsWith("#"): continue
      let r = regexIn(doc)
      if not r.found: continue
      var name = line.split(' ')[1]
      for stop in ['*', '(', '[', ':', '=']:
        let k = name.find(stop)
        if k >= 0: name = name[0 ..< k]
      helpers.mgetOrPut("/" & r.pattern & "/" & r.flags, @[]).add %*{"file": f.path, "proc": name}
  var regexes = newJArray()
  var keys = toSeq(helpers.keys)
  keys.sort(proc (a, b: string): int =
    result = cmp(helpers[b].len, helpers[a].len)
    if result == 0: result = cmp(a, b))
  var helperCount = 0
  var sources: seq[string]
  for path in tsFiles(refDir): sources.add readFile(refDir / path)
  for k in keys:
    helperCount += helpers[k].len
    var inPele = 0    # TypeScript files of Pele with this literal in them
    if helpers[k].len > 1:
      for text in sources:
        if k in text: inc inPele
    regexes.add %*{"regex": k, "helpers": helpers[k], "peleFiles": inPele}

  # tests: their files and lines of code
  var testFiles, testCode = 0
  for abs in walkDirRec(repoDir / "tests"):
    if abs.endsWith(".nim"):
      inc testFiles
      testCode += nimCode(readFile(abs))

  var statusJson = newJObject()
  for s, n in statuses: statusJson[s] = %n
  let commit = execProcess("git", args = ["-C", repoDir, "rev-parse", "HEAD"], options = {poUsePath}).strip
  %*{"commit": commit, "date": now().utc.format("yyyy-MM-dd"), "pin": pinOf(refDir),
     "files": files.len, "statuses": statusJson, "areas": areas, "withoutOrigin": noOrigin,
     "shared": shared, "betweenTypes": crossing, "upward": upward,
     "regexHelpers": helperCount, "regexes": regexes,
     "tests": {"files": testFiles, "code": testCode}, "lexers": lexers(files)}

proc main() =
  var refArg, outArg: string
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "ref": refArg = val
      of "out": outArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: quit "ERROR unexpected argument " & key, 2
    of cmdEnd: discard
  let c = census(refDirFrom(refArg))
  let path = if outArg.len > 0: outArg else: buildDir / "census.json"
  createDir path.parentDir
  writeFile path, c.pretty & "\n"
  var nim, tsc = 0
  for a in c["areas"]:
    nim += a["ported"].getInt
    tsc += a["ts"].getInt
  for u in c["upward"]: echo "ERROR shared code imports a diagram type: ", u["from"].getStr, " -> ", u["to"].getStr
  echo "census: ", c["files"].getInt, " Nim files; the ported ones are ", nim, " lines of code for ", tsc, " of TypeScript"
  echo "  ", c["withoutOrigin"].len, " files port no file of Pele; ", c["regexes"].len, " regexes written as ",
    c["regexHelpers"].getInt, " helpers"
  echo "wrote ", path.relativePath(repoDir)

when isMainModule:
  main()
