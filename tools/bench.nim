## bench: how long nimaki takes to draw the corpus, per diagram type, in its C build and in its
## JavaScript build, next to Pele's own npm package. Build it with -d:release (the numbers of a
## debug build say little):
##
##   nim c -d:release -o:build/bench/bench tools/bench.nim && build/bench/bench
##   build/bench/bench pie flowchart        only these types
##   options:
##     --rounds:N         draw every type N times (default 5); a type's time is its fastest round
##     --engines:c,js,pele,wasm  which to time (default c,js,pele)
##     --out:FILE         also write every number to FILE as JSON (docs/data/bench.json, the
##                        numbers of the page *Benchmark*, or a post's data file)
##     --package:PATH     Pele's package (default $PELE_PACKAGE or reference/npm/package)
##
## Three engines draw the same cases (corpus/cases.json) with the same fixed `now`:
##
## - `c`: nimaki's `render`, compiled into this program (so with this program's flags);
## - `js`: `build/web/nimaki.js`, the file a page loads (built by tools/webbuild.nim when it is
##   missing: after changing `src/`, rebuild it with `nim r tools/webbuild.nim --only:all`), run in
##   Node by tools/bench.mjs;
## - `pele`: Pele's `dist/pele.js`, in the same Node process;
## - `wasm`: nimaki's C build compiled to WebAssembly, `build/wasm/nimaki.wasm` (built by
##   tools/wasm/build.sh when it is missing), in the same Node process.
##
## For each engine it measures the first pass over the whole corpus in a fresh process (cold:
## caches empty, and for JavaScript, code not yet compiled by the engine's JIT), then N rounds of
## each type (warm). In Node the rounds alternate the two engines. The SVGs drawn are counted in
## characters (UTF-16 units, as JavaScript counts them), as a check that the three drew the same
## thing; difftest checks the bytes.
##
## It prints one line per type (cases, then the fastest round of each engine in milliseconds) and
## the totals last; a problem is an `ERROR` line. The page *Benchmark* (docs/benchmark.nim) explains
## it all and shows the last run: change it with this file.
import std/[os, osproc, unicode, strutils, json, tables, parseopt, monotimes, times, algorithm, sequtils]
import common
import nimaki

const
  work = buildDir / "bench"
  webFile = buildDir / "web" / "nimaki.js"
  wasmFile = buildDir / "wasm" / "nimaki.wasm"
  fixedNow = 1_700_000_000_000.0

proc sh(cmd: string): string =
  let (output, code) = execCmdEx(cmd)
  if code != 0: quit "ERROR " & cmd & "\n" & output, 2
  output

proc utf16Len(s: string): int =
  ## The length JavaScript gives the same text (UTF-16 code units), to compare with Node's.
  for r in s.runes: result += (if r.int > 0xFFFF: 2 else: 1)

proc cPass(sources: seq[string]): tuple[ms: float, chars, errors: int] =
  let start = getMonoTime()
  for source in sources:
    try: result.chars += render(source, RenderOptions(now: some(fixedNow))).svg.len
    except CatchableError: inc result.errors
  result.ms = (getMonoTime() - start).inNanoseconds.float / 1e6

proc timeC(byType: OrderedTable[string, seq[string]], rounds: int): JsonNode =
  ## The C build, in this process: one cold pass over every type, then the rounds.
  var cold = 0.0
  for t, sources in byType: cold += cPass(sources).ms
  var types = newJObject()
  for t, sources in byType:
    var ms: seq[float]
    var last: tuple[ms: float, chars, errors: int]
    for r in 0 ..< rounds:
      last = cPass(sources)
      ms.add last.ms
    var chars = 0   # counted outside the timed rounds, as JavaScript counts them
    for source in sources:
      try: chars += render(source, RenderOptions(now: some(fixedNow))).svg.utf16Len
      except CatchableError: discard
    types[t] = %*{"cases": sources.len, "rounds": ms, "chars": chars, "errors": last.errors}
  %*{"load": 0.0, "cold": cold, "types": types}

proc node(args: string): JsonNode =
  let file = work / "node.json"
  discard sh("TZ=UTC node --no-warnings " & quoteShell(repoDir / "tools" / "bench.mjs") & " " &
    quoteShell(repoDir / "corpus" / "cases.json") & " " & quoteShell(file) & " " & args)
  parseFile(file)

proc fastest(e: JsonNode, t: string): float =
  result = Inf
  for x in e["types"][t]["rounds"]: result = min(result, x.getFloat)

proc ms(x: float): string = formatFloat(x, ffDecimal, 1)

proc main() =
  var rounds = 5
  var engines = @["c", "js", "pele"]
  var only: seq[string]
  var outFile, package = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "rounds": rounds = parseInt(val)
      of "engines": engines = val.split(',')
      of "out": outFile = val
      of "package": package = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: only.add key
    of cmdEnd: discard
  when not defined(release):
    echo "ERROR bench is a debug build: its C numbers say little (nim c -d:release)"
  createDir work
  var byType: OrderedTable[string, seq[string]]
  var all: seq[(string, string)]
  for c in parseFile(repoDir / "corpus" / "cases.json")["cases"]:
    let t = c["type"].getStr
    if only.len > 0 and t notin only: continue
    all.add (t, c["source"].getStr)
  all.sort(proc (a, b: (string, string)): int = cmp(a[0], b[0]))   # stable: the corpus order within a type
  for (t, s) in all: byType.mgetOrPut(t, @[]).add s

  var commit = ""
  try: commit = execProcess("git -C " & quoteShell(repoDir) & " rev-parse --short HEAD").strip
  except OSError: discard
  var result = %*{"date": now().utc.format("yyyy-MM-dd"), "commit": commit, "rounds": rounds, "cases": all.len, "types": byType.len,
    "nim": NimVersion, "flags": (when defined(danger): "-d:danger" elif defined(release): "-d:release" else: "debug"),
    "cpu": "", "cores": countProcessors(), "engines": {}}
  try:
    for line in lines("/proc/cpuinfo"):
      if line.startsWith("model name"):
        result["cpu"] = %line.split(':', 1)[1].strip
        break
  except IOError: discard

  if "c" in engines:
    result["engines"]["c"] = timeC(byType, rounds)
  let nodeEngines = engines.filterIt(it in ["js", "pele", "wasm"]).mapIt(if it == "js": "nimaki" else: it)
  if nodeEngines.len > 0:
    if "nimaki" in nodeEngines and not fileExists(webFile):
      echo "bench: no build/web/nimaki.js, building it (tools/webbuild.nim --only:all)"
      discard sh("nim r --hints:off " & quoteShell(repoDir / "tools" / "webbuild.nim") & " --only:all")
    if "wasm" in nodeEngines and not fileExists(wasmFile):
      echo "bench: no build/wasm/nimaki.wasm, building it (tools/wasm/build.sh)"
      discard sh("sh " & quoteShell(repoDir / "tools" / "wasm" / "build.sh"))
    let pkg = packageDirFrom(package)
    let common = " --pele:" & quoteShell(pkg) & " --nimaki:" & quoteShell(webFile) & " --wasm:" & quoteShell(wasmFile) &
      " " & only.join(" ")
    # Cold: each engine alone in a fresh Node, no rounds. Warm: both in one Node, alternating.
    var cold: Table[string, JsonNode]
    for e in nodeEngines:
      cold[e] = node("--rounds:0 --engines:" & e & common)["engines"][e]
    let warm = node("--rounds:" & $rounds & " --engines:" & nodeEngines.join(",") & common)
    result["node"] = warm["node"]
    # What Node takes to start and stop, before any script: a program that draws a few diagrams
    # in a fresh Node pays it on top of the load and the cold pass.
    var start = Inf
    for r in 0 ..< 5:
      let t0 = getMonoTime()
      discard sh("node -e 0")
      start = min(start, (getMonoTime() - t0).inNanoseconds.float / 1e6)
    result["nodeStart"] = %start
    for e in nodeEngines:
      var entry = warm["engines"][e]
      entry["load"] = cold[e]["load"]
      entry["cold"] = cold[e]["cold"]
      result["engines"][if e == "nimaki": "js" else: e] = entry

  let shown = ["c", "js", "wasm", "pele"].filterIt(result["engines"].hasKey(it))
  var totals = initTable[string, float]()
  var problems = 0
  for t, sources in byType:
    var line = "  " & t.alignLeft(14) & ($sources.len).align(5) & " cases"
    var chars = -1
    for e in shown:
      let f = fastest(result["engines"][e], t)
      totals[e] = totals.getOrDefault(e) + f
      line.add "  " & e & " " & ms(f).align(7)
      let c = result["engines"][e]["types"][t]["chars"].getInt
      if chars >= 0 and c != chars:
        echo "ERROR ", t, ": ", e, " drew ", c, " characters, not ", chars
        inc problems
      chars = c
    echo line
  if outFile.len > 0:
    writeFile(outFile, result.pretty & "\n")
  var summary = "bench: " & $all.len & " cases of " & $byType.len & " types, fastest of " & $rounds &
    " rounds (ms):"
  for e in shown:
    let x = result["engines"][e]
    summary.add " " & e & " " & ms(totals[e]) & " warm, " & ms(x["cold"].getFloat) & " cold"
    if e != "c": summary.add " + " & ms(x["load"].getFloat) & " load"
    summary.add ";"
  if problems > 0: summary.add " " & $problems & " problems"
  echo summary
  if problems > 0: quit 1

main()
