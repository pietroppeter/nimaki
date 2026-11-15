## jssize: how big nimaki's JavaScript build is, and what fills it.
##
##   nim r tools/jssize.nim                      every build, written to build/jssize/sizes.json
##   nim r tools/jssize.nim --out:FILE           the same, written to FILE (a post's data file)
##   nim r tools/jssize.nim --fast:1             only the build the pages ship (-d:danger)
##   nim r tools/jssize.nim --web                and the files the pages ship (tools/webbuild.nim,
##                                               read from build/web/), with one build of the four
##                                               types diagrammari writes (flowchart, sequence, pie,
##                                               timeline)
##
## It compiles `src/nimaki/web.nim` (the file the pages load as nimaki.js) with each set of flags
## (none, -d:release, -d:danger), minifies the -d:danger file with esbuild as Pele minifies its
## bundle (the esbuild of Pele's own lock file, installed into build/jstools), once as it is and
## once wrapped in a function so that its top-level names can be shortened too, and measures each
## file raw, gzipped and with brotli (Node's zlib, at the highest levels). Pele's bundle is
## measured the same way, for comparison.
##
## Then it reads the -d:danger file and says what fills it: indentation, Nim's long names,
## strings written as arrays of bytes, type information, number tables, and the code of each
## module. The first five overlap (an indented line can hold a long name); the modules do not.
##
## It prints one line per file and a summary last; a problem is an `ERROR` line.
import std/[os, osproc, strutils, json, tables, algorithm, parseopt, sequtils]
import common
import webbuild except main

const
  entry = repoDir / "src" / "nimaki" / "web.nim"
  work = buildDir / "jssize"

type
  Build = object
    name, flags, file: string

proc sh(cmd: string): string =
  let (output, code) = execCmdEx(cmd)
  if code != 0: quit "ERROR " & cmd & "\n" & output, 2
  output

proc sizes(file: string): JsonNode =
  ## Raw, gzip -9 and brotli (quality 11) bytes of a file, from Node's zlib.
  let js = "const z=require('zlib'),b=require('fs').readFileSync(process.argv[1]);" &
           "console.log(b.length,z.gzipSync(b,{level:9}).length," &
           "z.brotliCompressSync(b,{params:{[z.constants.BROTLI_PARAM_QUALITY]:11}}).length)"
  let n = sh("node -e " & quoteShell(js) & " " & quoteShell(file)).strip.splitWhitespace.mapIt(parseInt(it))
  %*{"raw": n[0], "gzip": n[1], "brotli": n[2]}

# ------------------------------------------------------------------------------ what fills it

func isIdentChar(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '$'}

func mangled(name: string): bool =
  ## A name Nim made: `render__nimaki_u12`, `result_6627004386`, `NTI1090519731`, `Temporary1`.
  if "__" in name: return true
  let us = name.rfind('_')
  if us >= 0 and us < name.high and name[us + 1 .. ^1].allCharsInSet(Digits): return true
  name.len > 6 and (name.startsWith("NTI") or name.startsWith("NNI")) and
    name[3 .. ^1].allCharsInSet(Digits)

func moduleOf(fn: string): string =
  ## The module a top-level function comes from: `dump__modeljson_u4573` is modeljson's, and
  ## `render__diagramsZflowchartZrender_u12` diagrams/flowchart/render's (Nim writes / as Z).
  let a = fn.find("__")
  if a < 0: return "(runtime)"
  var m = fn[a + 2 .. ^1]
  let u = m.rfind("_u")
  if u > 0: m = m[0 ..< u]
  m = m.replace("OOZOOZdepsZ", "deps/").replace('Z', '/')
  m

func area(module: string): string =
  ## Where a module sits: a diagram type, the shared core, the browser side, or the libraries.
  if module.startsWith("diagrams/"): return "diagram types"
  if module == "modeljson" or module.startsWith("diagrams") : return "models for parse"
  for p in ["layout/", "svg/", "text/", "util/"]:
    if module.startsWith(p): return "shared core"
  if module in ["jsregex", "js", "jsmath", "jsdate", "core", "detect", "preprocess", "errors",
                "model", "types", "fdlibm", "nimaki"]: return "shared core"
  if module in ["mount", "zoom", "window", "dom", "jsapi", "web"]: return "browser side"
  "Nim's library and the dependencies"

proc anatomy(file: string): JsonNode =
  let text = readFile(file)
  var indent, names, strings, typeInfo, tables = 0
  var modules = initTable[string, int]()
  var current = ""          # the top-level function being read
  var otherTop = 0          # top-level code outside functions
  for line in text.splitLines:
    let n = line.len + 1
    var i = 0
    while i < line.len and line[i] == ' ': inc i
    indent += i
    if i == 0 and line.len > 0 and line[0] notin {'}', ')', ']'}:
      current = ""
      if line.startsWith("function "):
        let stop = line.find('(')
        if stop > 9: current = line[9 ..< stop]
      let l = line.strip
      if l.startsWith("var NTI") or l.startsWith("var NNI") or l.startsWith("NTI") or l.startsWith("NNI"):
        typeInfo += n
    if current.len > 0: modules.mgetOrPut(moduleOf(current), 0) += n
    else: otherTop += n
    if "Array([" in line and (" = new Int" in line or " = new Uint" in line or " = new Float" in line):
      tables += n
    # names and byte arrays, by a scan of the line
    var k = i
    while k < line.len:
      let c = line[k]
      if c in {'a'..'z', 'A'..'Z', '_', '$'}:
        var e = k
        while e < line.len and isIdentChar(line[e]): inc e
        if mangled(line[k ..< e]): names += e - k
        k = e
      elif c == '[':
        # [104, 105, ...]: a Nim string literal is an array of its bytes
        var e = k + 1
        var count = 0
        var ok = true
        while e < line.len and line[e] != ']':
          if line[e] notin {'0'..'9', ',', ' '}: ok = false; break
          if line[e] == ',': inc count
          inc e
        if ok and e < line.len and count >= 2: strings += e - k + 1
        k = e + 1
      elif c == '"' or c == '\'':
        # skip a JavaScript string, so the names inside it are not counted
        var e = k + 1
        while e < line.len and line[e] != c:
          if line[e] == '\\': inc e
          inc e
        k = e + 1
      else: inc k
  var areas = initOrderedTable[string, int]()
  for m, b in modules: areas.mgetOrPut(area(m), 0) += b
  areas.mgetOrPut("top-level code (data, type information)", 0) += otherTop
  var top = toSeq(modules.pairs).sorted(proc (a, b: (string, int)): int = cmp(b[1], a[1]))
  result = %*{"total": text.len,
              "what": {"indentation": indent, "names": names, "strings": strings,
                       "typeInfo": typeInfo, "tables": tables},
              "areas": areas, "modules": newJObject()}
  for (m, b) in top[0 ..< min(40, top.len)]: result["modules"][m] = %b

# ------------------------------------------------------------------------------ main

proc main() =
  var outFile = work / "sizes.json"
  var fast = 0
  var web = false
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "out": outFile = absolutePath(val)
      of "fast": fast = parseInt(val)
      of "web": web = true
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: quit "ERROR unexpected argument " & key, 2
    of cmdEnd: discard
  createDir work
  var builds = @[Build(name: "debug", flags: ""), Build(name: "release", flags: "-d:release"),
                 Build(name: "danger", flags: "-d:danger")]
  if fast > 0: builds = @[builds[2]]
  let nimVersion = sh("nim --version").splitLines[0]
  var files = newJArray()
  proc report(name, flags, file: string) =
    let s = sizes(file)
    echo "jssize: ", alignLeft(name, 18), align($s["raw"].getInt, 10), " bytes, ",
         align($s["gzip"].getInt, 9), " gzip, ", align($s["brotli"].getInt, 9), " brotli"
    files.add %*{"name": name, "flags": flags, "raw": s["raw"], "gzip": s["gzip"], "brotli": s["brotli"]}
  for b in builds.mitems:
    b.file = work / ("nimaki-" & b.name & ".js")
    discard sh("nim js --hints:off --warnings:off " & b.flags & " -o:" & quoteShell(b.file) & " " &
               quoteShell(entry))
    report(b.name, b.flags, b.file)
  let danger = work / "nimaki-danger.js"
  let es = esbuild()
  if es.len == 0: quit "ERROR esbuild is needed to measure the minified files", 2
  # Pele's own minifier settings (scripts/browser-build.mjs), without bundling: the file is one
  # script already. As it is, esbuild keeps the top-level names (a page could use them); wrapped
  # in a function (--format=iife) they are local, and shortened too.
  let common = " --minify --target=es2021 --charset=utf8 --legal-comments=none --log-level=error"
  let min = work / "nimaki-danger.min.js"
  discard sh(quoteShell(es) & " " & quoteShell(danger) & common & " --outfile=" & quoteShell(min))
  report("danger, minified", "-d:danger + esbuild --minify", min)
  let iife = work / "nimaki-danger.iife.min.js"
  discard sh(quoteShell(es) & " " & quoteShell(danger) & common & " --format=iife --outfile=" & quoteShell(iife))
  report("danger, in a function, minified", "-d:danger + esbuild --minify --format=iife", iife)
  let peleBundle = defaultPackage / "dist" / "pele.global.js"
  let pele = sizes(peleBundle)
  echo "jssize: ", alignLeft("Pele's bundle", 18), align($pele["raw"].getInt, 10), " bytes, ",
       align($pele["gzip"].getInt, 9), " gzip, ", align($pele["brotli"].getInt, 9), " brotli"
  var result = %*{"nim": nimVersion, "esbuild": esbuildVersion(), "pele": pinOf(defaultPackage),
                  "files": files, "peleBundle": pele, "anatomy": anatomy(danger)}
  if web:
    # The files the pages ship, as tools/webbuild.nim made them.
    var shipped = newJArray()
    let dir = buildDir / "web"
    if not fileExists(dir / "nimaki-core.js"): quit "ERROR no build/web/nimaki-core.js: run nim r tools/webbuild.nim first", 2
    var names = @["nimaki.js", "nimaki-core.js"]
    for t in diagramTypes(): names.add "nimaki-" & t & ".js"
    for name in names:
      let s = sizes(dir / name)
      shipped.add %*{"name": name, "raw": s["raw"], "gzip": s["gzip"], "brotli": s["brotli"]}
    result["shipped"] = shipped
    echo "jssize: ", shipped.len, " files of build/web measured"
    # diagrammari's four builders, in one build, minified as the others
    let four = work / "nimaki-diagrammari.js"
    discard sh("nim js --hints:off --warnings:off -d:danger -d:nimakiTypes=flowchart,sequence,pie,timeline" &
               " --nimcache:" & quoteShell(buildDir / "nimcache-web" / "diagrammari") &
               " -o:" & quoteShell(four) & " " & quoteShell(entry))
    minify(es, four)
    report("flowchart, sequence, pie, timeline", "-d:danger -d:nimakiTypes=flowchart,sequence,pie,timeline + esbuild", four)
    result["diagrammari"] = files[^1]
  createDir outFile.parentDir
  writeFile(outFile, result.pretty & "\n")
  let d = files[if fast > 0: 0 else: 2]
  echo "jssize: nimaki.js (-d:danger) is ", formatFloat(d["gzip"].getInt / pele["gzip"].getInt, ffDecimal, 1),
       " times Pele's bundle gzipped; written to ", relativePath(outFile, repoDir)

main()
