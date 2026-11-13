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
##     --corpus:NAME     only one corpus: `pele` or `diagrammari` (default both)
##     --js              compare Pele with nimaki compiled to JavaScript (tools/jsrunner.nim, in
##                       Node) instead of nimaki compiled to C; a full run writes its summary in
##                       docs/data/js.json instead of difftest.json
##
## A case is identical when both sides draw the same bytes, or both throw the same error code with
## the same message. `unsupported` is what nimaki raises for a type it does not draw yet. Both
## sides get `now` = 2026-01-01T00:00:00Z, and the oracle runs with TZ=UTC: gantt reads both.
## The inputs are corpus/cases.json (built by tools/corpus.mjs from Pele at the pin) and
## corpus/diagrammari.json (the Mermaid text of diagrammari, tools/corpus_diagrammari.nim). The
## summary counts the two apart: a type's `cases` are Pele's, its `diagrammari` are the others,
## and --check-done wants both identical. The oracle's
## answers are cached in build/oracle/; the full report is build/difftest/report.json, and a run
## over the whole corpus writes the summary the pages show, docs/data/difftest.json.
import std/[os, osproc, strutils, json, tables, algorithm, parseopt, hashes, random, sets]
import common, verdict, answers
import nimaki

const
  fixedNow = 1767225600000.0                 ## 2026-01-01T00:00:00Z
  casesPath = repoDir / "corpus" / "cases.json"
  diagrammariPath = repoDir / "corpus" / "diagrammari.json"
  coverageNames = {"gitGraph": "git", "quadrantChart": "quadrant", "treeView": "treeview"}.toTable
    ## Pele's type names where the coverage map (Pele's folder names) differs

type
  Case = object
    id, diagramType, source: string
    corpus: string   ## `pele` or `diagrammari`

func coverageName*(peleType: string): string = coverageNames.getOrDefault(peleType, peleType)

proc loadCases(): seq[Case] =
  if not fileExists(casesPath): quit "ERROR no corpus at " & casesPath & " (run: node tools/corpus.mjs)", 2
  for (corpus, path) in [("pele", casesPath), ("diagrammari", diagrammariPath)]:
    if not fileExists(path): continue
    for c in parseFile(path)["cases"]:
      result.add Case(id: c["id"].getStr, diagramType: c["type"].getStr, source: c["source"].getStr, corpus: corpus)

proc corpusText(): string =
  ## The inputs, for the oracle's cache key.
  result = readFile(casesPath)
  if fileExists(diagrammariPath): result.add readFile(diagrammariPath)

proc input(c: Case): JsonNode =
  ## A case as the oracle and the JavaScript build read it.
  %*{"id": c.id, "source": c.source, "options": {"now": fixedNow}}

proc oracle(cases: seq[Case], packageDir: string): Table[string, Answer] =
  ## Pele's answers for every case, from the cache when the corpus, the package and `now` match.
  let key = $hash(corpusText() & readFile(packageDir / "dist" / "pele.js") & $fixedNow)
  let dir = buildDir / "oracle"
  let cached = dir / ("answers-" & key.replace("-", "m") & ".jsonl")
  if not fileExists(cached):
    if findExe("node").len == 0: quit "ERROR node not found: install Node 20 or later (the oracle runs in it)", 2
    createDir dir
    var text = ""
    for c in cases:
      text.add $input(c) & "\n"
    let inPath = dir / "cases.jsonl"
    writeFile inPath, text
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
  var onlyCorpus = ""
  var js = false
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
      of "js": js = true
      of "corpus":
        if val notin ["pele", "diagrammari"]: quit "ERROR --corpus is pele or diagrammari, not " & val, 2
        onlyCorpus = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: only.add key
    of cmdEnd: discard
  let packageDir = packageDirFrom(packageArg)
  let all = loadCases()
  let peles = oracle(all, packageDir)

  var cases: seq[Case]
  var rng = initRand(seed)
  for c in all:
    if onlyCorpus.len > 0 and c.corpus != onlyCorpus: continue
    if only.len > 0 and c.diagramType notin only and c.diagramType.coverageName notin only: continue
    if fast < 100 and rng.rand(99) >= fast: continue
    if c.id notin peles: quit "ERROR the oracle has no answer for " & c.id & " (delete build/oracle/ and rerun)", 2
    cases.add c
  if cases.len == 0: quit "ERROR no case matches " & only.join(" "), 2

  if selfTest:
    var same, flippedDifferent = 0
    for c in cases:
      let want = peles[c.id]
      if compare(c.id, c.diagramType, want, want).verdict == vIdentical: inc same
      if compare(c.id, c.diagramType, want, want.flipped).verdict == vDifferent: inc flippedDifferent
    if same != cases.len: echo "ERROR self test: Pele against itself is identical on only ", same, " of ", cases.len, " cases"
    if flippedDifferent != cases.len: echo "ERROR self test: a one-byte change is caught on only ", flippedDifferent, " of ", cases.len, " cases"
    let ok = same == cases.len and flippedDifferent == cases.len
    echo "difftest self test: ", cases.len, " cases; Pele against itself: ", same, " identical; ",
      "with one byte changed: ", flippedDifferent, " different", (if ok: " (ok)" else: " (FAILED)")
    quit(if ok: 0 else: 1)

  var outcomes: seq[Outcome]
  if js:
    var inputs: seq[JsonNode]
    for c in cases: inputs.add c.input
    let got = jsAnswers(inputs, "difftest")
    for c in cases: outcomes.add compare(c.id, c.diagramType, peles[c.id], got[c.id])
  else:
    for c in cases: outcomes.add compare(c.id, c.diagramType, peles[c.id], nimakiAnswer(c.source, c.input["options"]))

  type Tally = array[Verdict, int]
  func count(t: Tally): int = t[vIdentical] + t[vDifferent] + t[vUnsupported]
  func toJson(t: Tally): JsonNode =
    %*{"cases": t.count, "identical": t[vIdentical], "different": t[vDifferent], "unsupported": t[vUnsupported]}
  var byType, byTypeD: OrderedTable[string, Tally]   # Pele's corpus, diagrammari's
  var types: seq[string]
  for i, o in outcomes:
    if o.diagramType notin types: types.add o.diagramType
    if cases[i].corpus == "pele": inc byType.mgetOrPut(o.diagramType, default(Tally))[o.verdict]
    else: inc byTypeD.mgetOrPut(o.diagramType, default(Tally))[o.verdict]
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
    var tally: Tally
    for v in Verdict: tally[v] = byType.getOrDefault(t)[v] + byTypeD.getOrDefault(t)[v]
    if t.coverageName in done and tally[vIdentical] != tally.count:
      regressions.add t
      echo "ERROR ", t, " is done on the coverage map, but only ", tally[vIdentical], " of ",
        tally.count, " cases are identical"

  # the report, and on a full run the summary the pages show
  createDir buildDir / "difftest"
  var report = newJArray()
  for i, o in outcomes:
    report.add %*{"id": o.id, "type": o.diagramType, "corpus": cases[i].corpus, "verdict": $o.verdict, "detail": o.detail}
  writeFile buildDir / "difftest" / "report.json", report.pretty & "\n"
  var total, totalD: Tally
  var rows = newJArray()
  for t in types:
    let tally = byType.getOrDefault(t)
    let tallyD = byTypeD.getOrDefault(t)
    for v in Verdict:
      total[v] += tally[v]
      totalD[v] += tallyD[v]
    var row = %*{"type": t, "coverage": t.coverageName}
    for k, v in tally.toJson: row[k] = v
    if tallyD.count > 0: row["diagrammari"] = tallyD.toJson
    rows.add row
  if only.len == 0 and fast == 100 and onlyCorpus.len == 0 and js:
    var summary = %*{"pin": pinOf(packageDir)}
    for k, v in total.toJson: summary[k] = v
    summary["diagrammari"] = totalD.toJson
    updateJsData("difftest", "", summary)
  if only.len == 0 and fast == 100 and onlyCorpus.len == 0 and not js:
    var summary = %*{"about": "Written by tools/difftest.nim on a run over the whole corpus. Do not edit by hand. " &
      "`cases` and the counts beside it are Pele's corpus; `diagrammari` counts diagrammari's.",
      "pin": pinOf(packageDir)}
    for k, v in total.toJson: summary[k] = v
    summary["diagrammari"] = totalD.toJson
    summary["types"] = rows
    writeFile dataDir / "difftest.json", summary.pretty & "\n"

  for t in types:
    var tally: Tally
    for v in Verdict: tally[v] = byType.getOrDefault(t)[v] + byTypeD.getOrDefault(t)[v]
    if tally[vIdentical] + tally[vDifferent] > 0:
      echo "  ", t.alignLeft(14), align($tally[vIdentical], 5), " identical", align($tally[vDifferent], 5), " different",
        align($tally[vUnsupported], 5), " unsupported"
  var sum: Tally
  for v in Verdict: sum[v] = total[v] + totalD[v]
  echo "difftest: pele ", pinOf(packageDir), (if js: " against nimaki in JavaScript" else: ""), ", ", outcomes.len, " cases of ", types.len, " types",
    (if totalD.count > 0: " (" & $totalD.count & " of them diagrammari's)" else: ""),
    (if fast < 100: " (sample of " & $fast & "%, seed " & $seed & ")" else: ""), ": ",
    sum[vIdentical], " identical, ", sum[vDifferent], " different, ", sum[vUnsupported], " unsupported"
  if regressions.len > 0 and checkDone: quit 1
  if strict and sum[vIdentical] != outcomes.len: quit 1

when isMainModule:
  main()
