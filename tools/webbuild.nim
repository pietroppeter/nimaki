## webbuild: the files a page loads to draw with nimaki, as the pages ship them.
##
##   nim r tools/webbuild.nim                    every file, minified, into build/web/
##   nim r tools/webbuild.nim --out:DIR          into DIR (the pages: docs/assets/)
##   nim r tools/webbuild.nim --only:all         only nimaki.js (or --only:core, --only:pie,...)
##   nim r tools/webbuild.nim --no-minify        as `nim js` writes them
##
## `src/nimaki/web.nim` compiled with `nim js -d:danger`, once per file (post *Why nimaki.js is
## big*):
##
## - `nimaki.js`: every diagram type, as Pele's `pele.global.js`;
## - `nimaki-<type>.js`, one per diagram type (`-d:nimakiTypes=<type>`): the shared core and that
##   type, as Pele's `dist/esm/diagrams/<type>.js` with its chunks;
## - `nimaki-core.js` (`-d:nimakiTypes=none`): the shared core and no type, for a page that loads
##   its types when it meets them (`nimaki.load`, `renderAsync`, `mountAsync`).
##
## Each file is complete: it draws its types alone, and joins the others on the same page. Then
## each is minified as Pele minifies its bundle, by the esbuild of Pele's own lock file (installed
## into build/jstools with npm), wrapped in a function so that its names are shortened too. Without
## npm or the network the files stay as `nim js` wrote them, and a line says so.
##
## It compiles four files at a time, prints one line per file and a summary last.
import std/[os, osproc, strutils, json, parseopt, sequtils, times]
import common

const
  entry = repoDir / "src" / "nimaki" / "web.nim"
  tools = buildDir / "jstools"

proc diagramTypes*(): seq[string] =
  ## Pele's diagram types, read from the detectors of `src/nimaki/detect.nim`, in their order.
  for line in lines(repoDir / "src" / "nimaki" / "detect.nim"):
    let l = line.strip
    if l.startsWith("(\"") and "jsre\"" in l:
      let t = l[2 ..< l.find('"', 2)]
      if t notin result: result.add t

proc esbuildVersion*(): string =
  ## The esbuild that Pele's lock file pins: Pele minifies its bundle with it.
  parseFile(defaultRef / "package-lock.json")["packages"]["node_modules/esbuild"]["version"].getStr

proc esbuild*(): string =
  ## The path of that esbuild, installed into build/jstools when it is not there; "" without it.
  let version = esbuildVersion()
  result = tools / "node_modules" / ".bin" / "esbuild"
  if fileExists(result):
    let (v, code) = execCmdEx(quoteShell(result) & " --version")
    if code == 0 and v.strip == version: return
  createDir tools
  let (output, code) = execCmdEx("npm install --prefix " & quoteShell(tools) & " --no-save --no-audit " &
                                 "--no-fund --loglevel=error esbuild@" & version)
  if code != 0 or not fileExists(result):
    echo "webbuild: esbuild ", version, " could not be installed (", output.strip.splitLines[^1], ")"
    result = ""

proc minify*(es, file: string) =
  ## Minifies a file in place, with Pele's settings (scripts/browser-build.mjs) and --format=iife:
  ## nimaki's file is one script already, so there is nothing to bundle.
  let tmp = file & ".min"
  let cmd = quoteShell(es) & " " & quoteShell(file) & " --minify --format=iife --target=es2021 " &
            "--charset=utf8 --legal-comments=none --log-level=error --outfile=" & quoteShell(tmp)
  let (output, code) = execCmdEx(cmd)
  if code != 0: quit "ERROR esbuild failed on " & file & ":\n" & output, 2
  moveFile(tmp, file)

proc main() =
  var outDir = buildDir / "web"
  var only: seq[string]
  var minified = true
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "out": outDir = absolutePath(val)
      of "only": only = val.split(',')
      of "no-minify": minified = false
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: quit "ERROR unexpected argument " & key, 2
    of cmdEnd: discard
  createDir outDir
  # (file name, the types it draws)
  var files = @[("nimaki.js", "all"), ("nimaki-core.js", "none")]
  for t in diagramTypes(): files.add ("nimaki-" & t & ".js", t)
  if only.len > 0:
    files = files.filterIt(it[1] in only)
    if files.len == 0: quit "ERROR --only names no file: " & only.join(","), 2
  let started = epochTime()
  var cmds: seq[string]
  for (name, types) in files:
    # one nimcache per file: the same main module with other defines must not share one
    cmds.add "nim js --hints:off --warnings:off -d:danger -d:nimakiTypes=" & types &
             " --nimcache:" & quoteShell(buildDir / "nimcache-web" / types) &
             " -o:" & quoteShell(outDir / name) & " " & quoteShell(entry)
  let failed = execProcesses(cmds, n = 4, options = {poStdErrToStdOut, poUsePath, poEvalCommand})
  if failed != 0: quit "ERROR nim js failed for one of the files: run one of these alone to see why:\n" & cmds.join("\n"), 2
  var es = ""
  if minified:
    es = esbuild()
    if es.len == 0: echo "webbuild: the files are not minified"
  var total = 0
  for (name, types) in files:
    let file = outDir / name
    let before = getFileSize(file)
    if es.len > 0: minify(es, file)
    let after = getFileSize(file)
    total += int(after)
    echo "webbuild: ", alignLeft(name, 28), align($after, 9), " bytes", (if es.len > 0: " (" & $before & " before minifying)" else: "")
  echo "webbuild: ", files.len, " files, ", total, " bytes, in ", relativePath(outDir, repoDir),
       (if es.len > 0: ", minified with esbuild " & esbuildVersion() else: ", not minified"),
       ", ", int(epochTime() - started), " s"

when isMainModule: main()
