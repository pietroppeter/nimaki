## difftest, the referee: renders every case of the corpus with Pele (the pinned npm package, in
## Node, through tools/oracle.mjs) and with nimaki, and compares the two SVGs byte for byte.
##
##   nim r tools/difftest.nim                 every case, every type
##   nim r tools/difftest.nim pie timeline    only these types (Pele's names or the coverage map's)
##   options:
##     --fast:N          a deterministic sample of N percent of the cases (--seed:S for another)
##     --show:N          print at most N differences as ERROR lines (default 10; all in the report)
##     --strict          fail when any case is not identical (unsupported counts as a failure)
##     --check-done      fail when a type the coverage map marks done is not identical on every case
##     --self-test       prove the referee can fail: compare Pele with itself (all identical), then
##                       with itself with one byte changed (all different)
##     --package:PATH    the oracle package (default reference/npm/package or $PELE_PACKAGE)
##
## A case is identical when both sides draw the same bytes, or both throw the same error code with
## the same message. `unsupported` is what nimaki raises for a type it does not draw yet. Both
## sides get `now` = 2026-01-01T00:00:00Z, and the oracle runs with TZ=UTC: gantt reads both.
## The inputs are corpus/cases.json (built by tools/corpus.mjs from Pele at the pin). The oracle's
## answers are cached in build/oracle/; the full report is build/difftest/report.json, and a run
## over the whole corpus writes the summary the pages show, docs/data/difftest.json.
import std/[os, osproc, strutils, json, tables, algorithm, parseopt, hashes, random, sets]
import common, verdict
import nimaki

const
  fixedNow = 1767225600000.0                 ## 2026-01-01T00:00:00Z
  casesPath = repoDir / "corpus" / "cases.json"
  coverageNames = {"gitGraph": "git", "quadrantChart": "quadrant", "treeView": "treeview"}.toTable
    ## Pele's type names where the coverage map (Pele's folder names) differs

type
  Case = object
    id, diagramType, source: string

func coverageName*(peleType: string): string = coverageNames.getOrDefault(peleType, peleType)

proc loadCases(): seq[Case] =
  if not fileExists(casesPath): quit "ERROR no corpus at " & casesPath & " (run: node tools/corpus.mjs)", 2
  for c in parseFile(casesPath)["cases"]:
    result.add Case(id: c["id"].getStr, diagramType: c["type"].getStr, source: c["source"].getStr)

proc toAnswer(j: JsonNode): Answer =
  if j["ok"].getBool: Answer(ok: true, svg: j["svg"].getStr)
  else: Answer(ok: false, code: j["code"].getStr, message: j["message"].getStr)

proc oracle(cases: seq[Case], packageDir: string): Table[string, Answer] =
  ## Pele's answers for every case, from the cache when the corpus, the package and `now` match.
  let key = $hash(readFile(casesPath) & readFile(packageDir / "dist" / "pele.js") & $fixedNow)
  let dir = buildDir / "oracle"
  let cached = dir / ("answers-" & key.replace("-", "m") & ".jsonl")
  if not fileExists(cached):
    if findExe("node").len == 0: quit "ERROR node not found: install Node 20 or later (the oracle runs in it)", 2
    createDir dir
    var input = ""
    for c in cases:
      input.add $(%*{"id": c.id, "source": c.source, "options": {"now": fixedNow}}) & "\n"
    let inPath = dir / "cases.jsonl"
    writeFile inPath, input
    let cmd = "TZ=UTC node " & quoteShell(repoDir / "tools" / "oracle.mjs") & " " & quoteShell(packageDir) &
              " < " & quoteShell(inPath) & " > " & quoteShell(cached & ".tmp")
    if execShellCmd(cmd) != 0:
      removeFile cached & ".tmp"
      quit "ERROR the oracle failed: " & cmd, 2
    moveFile cached & ".tmp", cached
  for line in lines(cached):
    if line.len > 0:
      let j = parseJson(line)
      result[j["id"].getStr] = toAnswer(j)

proc nimakiAnswer(c: Case): Answer =
  try:
    let r = render(c.source, RenderOptions(now: fixedNow))
    Answer(ok: true, svg: r.svg)
  except PeleError as e:
    Answer(ok: false, code: e.code, message: e.msg)

proc doneTypes(): HashSet[string] =
  ## The diagram types the coverage map says are done (all three stages).
  let path = dataDir / "coverage.json"
  if fileExists(path):
    for d in parseFile(path)["diagrams"]:
      if d["parse"]["status"].getStr == "done" and d["layout"]["status"].getStr == "done" and
         d["render"]["status"].getStr == "done":
        result.incl d["id"].getStr

proc main() =
  var packageArg: string
  var only: seq[string]
  var fast = 100
  var seed = 1
  var show = 10
  var strict, checkDone, selfTest = false
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "package": packageArg = val
      of "fast": fast = parseInt(val)
      of "seed": seed = parseInt(val)
      of "show": show = parseInt(val)
      of "strict": strict = true
      of "check-done": checkDone = true
      of "self-test": selfTest = true
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: only.add key
    of cmdEnd: discard
  let packageDir = packageDirFrom(packageArg)
  let all = loadCases()
  let answers = oracle(all, packageDir)

  var cases: seq[Case]
  var rng = initRand(seed)
  for c in all:
    if only.len > 0 and c.diagramType notin only and c.diagramType.coverageName notin only: continue
    if fast < 100 and rng.rand(99) >= fast: continue
    if c.id notin answers: quit "ERROR the oracle has no answer for " & c.id & " (delete build/oracle/ and rerun)", 2
    cases.add c
  if cases.len == 0: quit "ERROR no case matches " & only.join(" "), 2

  if selfTest:
    var same, flippedDifferent = 0
    for c in cases:
      let want = answers[c.id]
      if compare(c.id, c.diagramType, want, want).verdict == vIdentical: inc same
      if compare(c.id, c.diagramType, want, want.flipped).verdict == vDifferent: inc flippedDifferent
    if same != cases.len: echo "ERROR self test: Pele against itself is identical on only ", same, " of ", cases.len, " cases"
    if flippedDifferent != cases.len: echo "ERROR self test: a one-byte change is caught on only ", flippedDifferent, " of ", cases.len, " cases"
    let ok = same == cases.len and flippedDifferent == cases.len
    echo "difftest self test: ", cases.len, " cases; Pele against itself: ", same, " identical; ",
      "with one byte changed: ", flippedDifferent, " different", (if ok: " (ok)" else: " (FAILED)")
    quit(if ok: 0 else: 1)

  var outcomes: seq[Outcome]
  for c in cases:
    outcomes.add compare(c.id, c.diagramType, answers[c.id], nimakiAnswer(c))

  type Tally = array[Verdict, int]
  var byType: OrderedTable[string, Tally]
  var types: seq[string]
  for o in outcomes:
    if o.diagramType notin byType:
      byType[o.diagramType] = default(Tally)
      types.add o.diagramType
  for o in outcomes: inc byType[o.diagramType][o.verdict]
  types.sort

  var shown = 0
  var different = 0
  for o in outcomes:
    if o.verdict == vDifferent:
      inc different
      if shown < show:
        echo "ERROR ", o.id, " (", o.diagramType, "): ", o.detail
        inc shown
  if different > shown: echo "ERROR … and ", different - shown, " more differences (build/difftest/report.json)"

  let done = doneTypes()
  var regressions: seq[string]
  for t in types:
    let tally = byType[t]
    if t.coverageName in done and tally[vIdentical] != tally[vIdentical] + tally[vDifferent] + tally[vUnsupported]:
      regressions.add t
      echo "ERROR ", t, " is done on the coverage map, but only ", tally[vIdentical], " of ",
        tally[vIdentical] + tally[vDifferent] + tally[vUnsupported], " cases are identical"

  # the report, and on a full run the summary the pages show
  createDir buildDir / "difftest"
  var report = newJArray()
  for o in outcomes:
    report.add %*{"id": o.id, "type": o.diagramType, "verdict": $o.verdict, "detail": o.detail}
  writeFile buildDir / "difftest" / "report.json", report.pretty & "\n"
  var total: Tally
  var rows = newJArray()
  for t in types:
    let tally = byType[t]
    for v in Verdict: total[v] += tally[v]
    rows.add %*{"type": t, "coverage": t.coverageName, "cases": tally[vIdentical] + tally[vDifferent] + tally[vUnsupported],
                "identical": tally[vIdentical], "different": tally[vDifferent], "unsupported": tally[vUnsupported]}
  if only.len == 0 and fast == 100:
    writeFile dataDir / "difftest.json", (%*{"about": "Written by tools/difftest.nim on a run over the whole corpus. Do not edit by hand.",
      "pin": pinOf(packageDir), "cases": outcomes.len, "identical": total[vIdentical], "different": total[vDifferent],
      "unsupported": total[vUnsupported], "types": rows}).pretty & "\n"

  for t in types:
    let tally = byType[t]
    if tally[vIdentical] + tally[vDifferent] > 0:
      echo "  ", t.alignLeft(14), align($tally[vIdentical], 5), " identical", align($tally[vDifferent], 5), " different",
        align($tally[vUnsupported], 5), " unsupported"
  echo "difftest: pele ", pinOf(packageDir), ", ", outcomes.len, " cases of ", types.len, " types",
    (if fast < 100: " (sample of " & $fast & "%, seed " & $seed & ")" else: ""), ": ",
    total[vIdentical], " identical, ", total[vDifferent], " different, ", total[vUnsupported], " unsupported"
  if regressions.len > 0 and checkDone: quit 1
  if strict and total[vIdentical] != outcomes.len: quit 1

when isMainModule:
  main()
