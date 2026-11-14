## peletests: Pele's own test suites, run on nimaki.
##
##   nim r tools/peletests.nim [--check] [--jobs:N] [--fast:N] [--ref:PATH] [test files...]
##
## Pele's tests (tests/**/*.test.ts and *.spec.ts at the pin, run by vitest) call Pele's public
## API, `render(text, options)` from src/index.js. This tool runs them twice in a copy of Pele
## under build/peletests/: once as they are, and once with src/index.js replaced by nimaki's
## JavaScript build (tools/peletests/index.mjs over bridge.nim). Each test that passes on Pele is
## then sorted:
##
## - `passed`: it passes on nimaki too;
## - `api`: it calls what nimaki does not provide (`parse()`, `mount()`, zoom...);
## - `unported`: it draws a type nimaki does not draw yet;
## - `speed`: only a time bound of Pele's failed (stress tests; the JavaScript build is slower);
## - `canvas`: it tests Pele's canvas measurer, which nimaki does not port;
## - `known`: listed in tools/peletests/known.txt, with the reason (`skip` there: not even run);
## - `failed`: anything else, one `ERROR` line each: a difference to fix or to explain in
##   docs/divergences.md.
##
## A test file whose worker dies (a crash, no memory) is an `ERROR` too. The counts go to
## docs/data/peletests.json (with `--fast:N`, which runs one file in N, they do not). `--check`
## exits 1 when there is an ERROR. Detail: build/peletests/report.txt.
##
## Tests that call parts of Pele other than src/index.js (a parser, the layout) still run those
## parts in TypeScript: what they check is Pele, not the port, and they pass here as on Pele.
## The text measurer is Pele's metricsMeasurer on both sides, as in difftest.
import std/[os, osproc, strutils, json, tables, algorithm, parseopt, re, sets, sequtils]
import common

type
  Kind = enum kPassed = "passed", kApi = "api", kUnported = "unported", kSpeed = "speed",
              kCanvas = "canvas", kKnown = "known", kFailed = "failed"
  Known = object
    file, name, how, reason: string
  Outcome = object
    file, name, status, message, missing: string

const peleSkip = ["website", "node_modules", ".git"]

proc sh(cmd: string, dir = ""): int =
  let full = if dir.len > 0: "cd " & quoteShell(dir) & " && " & cmd else: cmd
  execShellCmd(full)

proc prepare(refDir, work: string): string =
  ## A copy of the Pele checkout with its dev dependencies, made once per pin.
  let pin = readPin()["COMMIT"]
  let pele = work / "pele"
  let marker = pele / ".nimaki-pin"
  if fileExists(marker) and readFile(marker) == pin and dirExists(pele / "node_modules"):
    return pele
  removeDir pele
  createDir pele
  for kind, path in walkDir(refDir):
    let name = path.extractFilename
    if name in peleSkip: continue
    if kind == pcDir: copyDir(path, pele / name) else: copyFile(path, pele / name)
  echo "peletests: installing Pele's dev dependencies (npm ci) in ", pele
  if sh("npm ci --ignore-scripts --no-audit --no-fund --loglevel=error", pele) != 0:
    quit "ERROR npm ci failed in " & pele, 2
  writeFile marker, pin
  pele

proc outcomes(path: string): seq[Outcome] =
  ## The tests of one vitest JSON report.
  let j = parseJson(readFile(path))
  for f in j["testResults"]:
    let file = f["name"].getStr.split("/pele/")[^1]
    for a in f["assertionResults"]:
      var o = Outcome(file: file, name: a["fullName"].getStr, status: a["status"].getStr)
      if a.hasKey("failureMessages") and a["failureMessages"].len > 0:
        o.message = a["failureMessages"][0].getStr
      if a{"meta"}{"nimakiMissing"} != nil: o.missing = a["meta"]["nimakiMissing"].getStr
      result.add o

let speedRe = re"expected [0-9.e+-]+ to be less than [0-9]+"

proc typeOf(file: string): string =
  ## The diagram type a test file is about, from its path ("" for none): tests/<type>/...,
  ## tests/compat/<type>/..., tests/render/<type>[-security].test.ts.
  let parts = file.split('/')
  if parts.len >= 3 and parts[1] == "compat": return parts[2].split('-')[0]
  if parts.len >= 3 and parts[1] == "render": return parts[2].split('.')[0].split('-')[0]
  if parts.len >= 3: return parts[1]
  ""

proc unportedTypes(): HashSet[string] =
  ## The types whose drawing is not done on the coverage map.
  for d in parseJson(readFile(dataDir / "coverage.json"))["diagrams"]:
    if d["render"]["status"].getStr != "done": result.incl d["id"].getStr.toLowerAscii

let unported = unportedTypes()

proc readKnown(): seq[Known] =
  for line in lines(repoDir / "tools" / "peletests" / "known.txt"):
    if line.len == 0 or line.startsWith("#"): continue
    let f = line.split('\t')
    if f.len < 4: quit "ERROR tools/peletests/known.txt: a line needs four fields: " & line, 2
    result.add Known(file: f[0], name: f[1], how: f[2], reason: f[3])

proc kindOf(o: Outcome, known: seq[Known]): Kind =
  if o.status == "passed": return kPassed
  for k in known:
    if k.file == o.file and k.name == o.name: return kKnown
  if o.missing.len > 0 or "NotInNimaki" in o.message: kApi
  elif "nimaki does not draw" in o.message or typeOf(o.file) in unported: kUnported
  elif o.file == "tests/util/measurer.test.ts" and o.name.startsWith("canvasMeasurer"): kCanvas
  elif o.message.split("\n    at ")[0].find(speedRe) >= 0: kSpeed
  else: kFailed

proc firstLine(s: string): string =
  for line in s.splitLines:
    if line.strip.len > 0: return line.strip
  ""

proc main() =
  var check = false
  var jobs = 4
  var fast = 0
  var refArg = ""
  var only: seq[string]
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "check": check = true
      of "jobs": jobs = parseInt(val)
      of "fast": fast = parseInt(val)
      of "ref": refArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: only.add key
    of cmdEnd: discard
  let refDir = refDirFrom(refArg)
  let work = buildDir / "peletests"
  createDir work
  let pele = prepare(refDir, work)
  copyFile(repoDir / "tools" / "peletests" / "vitest.config.mjs", pele / "vitest.nimaki.config.mjs")

  let bridge = work / "bridge.js"
  let compile = "nim js --hints:off --warnings:off -d:nodejs -d:release -o:" & quoteShell(bridge) & " " &
                quoteShell(repoDir / "tools" / "peletests" / "bridge.nim")
  if sh(compile) != 0: quit "ERROR nim js failed: " & compile, 2

  # Pele on its own tests, once per pin: what nimaki is compared with.
  let pin = readPin()["COMMIT"]
  let baseline = work / ("pele-" & pin[0 ..< 12] & ".json")
  if not fileExists(baseline):
    echo "peletests: running Pele's suites on Pele (once per pin)"
    discard sh("TZ=UTC npx vitest run --exclude 'tests/website/**' --reporter=json --outputFile=" &
               quoteShell(baseline) & " > " & quoteShell(work / "pele.log") & " 2>&1", pele)
    if not fileExists(baseline): quit "ERROR vitest wrote no report; see " & work / "pele.log", 2
  var onPele = initTable[(string, string), string]()
  var files: seq[string]
  for o in outcomes(baseline):
    onPele[(o.file, o.name)] = o.status
    if o.file notin files: files.add o.file
  files.sort
  if only.len > 0: files = files.filterIt(it in only)
  if fast > 1:
    var kept: seq[string]
    for i, f in files:
      if i mod fast == 0: kept.add f
    files = kept

  # nimaki, one vitest per file, so that a worker that dies takes one file with it.
  let outDir = work / "out"
  removeDir outDir
  createDir outDir
  let env = "TZ=UTC NIMAKI_SHIM=" & quoteShell(repoDir / "tools" / "peletests" / "index.mjs") &
            " NIMAKI_SETUP=" & quoteShell(repoDir / "tools" / "peletests" / "setup.mjs") &
            " NIMAKI_BRIDGE=" & quoteShell(bridge)
  let known = readKnown()
  var cmds: seq[string]
  for f in files:
    let stem = f.replace('/', '_')
    # Tests to skip: vitest runs the names that match -t, so the pattern refuses them.
    var refuse: seq[string]
    for k in known:
      if k.file == f and k.how == "skip": refuse.add "^" & escapeRe(k.name) & "$"
    let filter = if refuse.len > 0: " -t " & quoteShell("^(?!(?:" & refuse.join("|") & ")).*") else: ""
    cmds.add "cd " & quoteShell(pele) & " && " & env & " npx vitest run -c vitest.nimaki.config.mjs " &
             quoteShell(f) & filter & " --reporter=json --outputFile=" & quoteShell(outDir / stem & ".json") &
             " > " & quoteShell(outDir / stem & ".log") & " 2>&1"
  echo "peletests: ", files.len, " test files on nimaki, ", jobs, " at a time"
  discard execProcesses(cmds, n = jobs, options = {poEvalCommand})

  var counts: array[Kind, int]
  var report = ""
  var errors = 0
  var perFile = newJObject()
  var failures = newJArray()
  for f in files:
    let path = outDir / f.replace('/', '_') & ".json"
    var mine: seq[Outcome]
    if fileExists(path): mine = outcomes(path)
    var seen = initHashSet[string]()
    var fileCounts: array[Kind, int]
    for o in mine:
      seen.incl o.name
      if onPele.getOrDefault((o.file, o.name)) != "passed": continue
      let k = kindOf(o, known)
      inc counts[k]
      inc fileCounts[k]
      if k != kPassed:
        report.add $k & "\t" & o.file & "\t" & o.name & "\t" & firstLine(o.message) & "\n"
        if k == kFailed:
          inc errors
          echo "ERROR ", o.file, " > ", o.name, ": ", firstLine(o.message)[0 ..< min(160, firstLine(o.message).len)]
        failures.add %*{"file": o.file, "test": o.name, "kind": $k,
                        "message": firstLine(o.message)[0 ..< min(200, firstLine(o.message).len)]}
    var lost = 0
    for (key, status) in onPele.pairs:
      if key[0] == f and status == "passed" and key[1] notin seen:
        var skipped = false
        for k in known:
          if k.file == f and k.name == key[1] and k.how == "skip": skipped = true
        if skipped:
          inc counts[kKnown]
          inc fileCounts[kKnown]
        else: inc lost
    if lost > 0:
      inc errors
      counts[kFailed] += lost
      fileCounts[kFailed] += lost
      echo "ERROR ", f, ": ", lost, " tests gave no result (the worker died; see ",
           outDir / f.replace('/', '_') & ".log", ")"
      failures.add %*{"file": f, "test": "(" & $lost & " tests: the worker died)", "kind": "failed", "message": ""}
    var fc = newJObject()
    for k in Kind: fc[$k] = %fileCounts[k]
    perFile[f] = fc
  writeFile work / "report.txt", report

  var total = 0
  for k in Kind: total += counts[k]
  if fast <= 1 and only.len == 0:
    var c = newJObject()
    for k in Kind: c[$k] = %counts[k]
    let data = %*{"pele": pinOf(refDir), "commit": pin, "files": files.len, "tests": total,
                  "counts": c, "byFile": perFile, "notPassed": failures}
    writeFile dataDir / "peletests.json", data.pretty & "\n"
  var parts: seq[string]
  for k in Kind: parts.add $counts[k] & " " & $k
  echo "peletests: pele ", pinOf(refDir), ", ", files.len, " test files, ", total,
       " tests that pass on Pele: ", parts.join(", ")
  if check and errors > 0: quit 1

main()
