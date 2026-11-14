## parsediff: the referee for models. Pele's `parse(text)` returns the diagram's model, an object
## its tests read (`parse(text).nodes.get("A").label`); nimaki's `parse` returns the same model,
## as a Nim object. This tool writes both out as JSON and compares them, case by case, on the
## corpus:
##
## - Pele's side: tools/oracle.mjs with `"parse": true` (`canonical`: a Map is `{"$map": ...}`,
##   a Set `{"$set": [...]}`, undefined is left out);
## - nimaki's side: `dumpModel` of tools/models.nim, which walks the Nim object field by field (`fieldPairs`): a
##   table is a `$map`, a set a `$set`, a `ref` met again inside itself `"$cycle"`;
## - then both are normalized the same way (`normal`): a key whose value is null, "" or NaN is
##   dropped (nimaki writes "" or NaN where Pele leaves a field undefined), and so is an empty
##   list or table (nimaki's are never missing), numbers are compared as
##   numbers, a Map and an object with the same entries are the same, a set's elements are
##   sorted, and the model's own `type` and `mermaidType` are compared apart. Of nimaki's names,
##   a field named after a Nim keyword (`kind` for `type`, `stop` for `end`) and an enum's prefix
##   (`skState` for `"state"`) are read as Pele's.
##
## A model is the same when the two JSON values are equal: the same keys, the same values. The
## names of nimaki's fields are Pele's, except where Nim forbids them; a field named otherwise,
## an enum written as a name where Pele has a string or a number, a field Pele has and nimaki
## does not, all show as differences, and the first one of each case is printed.
##
##   nim r tools/parsediff.nim                every case of every ported type
##   nim r tools/parsediff.nim pie timeline   only these types
##   options:
##     --show:N        print at most N differences as ERROR lines (default 10)
##     --all           write every difference of a case in the report, not only the first
##     --package:PATH  the oracle package (default reference/npm/package or $PELE_PACKAGE)
##
## It writes its summary in docs/data/parsediff.json, and every difference in
## build/parsediff/report.json.
import std/[os, osproc, json, tables, sets, strutils, algorithm, parseopt, options, strtabs, typetraits]
import common
import nimaki
import models

const fixedNow = 1767225600000.0   ## as in tools/difftest.nim

proc firstDifference*(a, b: JsonNode, at = "model"): string =
  ## Where two JSON values first differ, and how ("" when they are equal). `a` is Pele's.
  if a == b: return ""
  if a.kind != b.kind:
    return at & ": Pele has " & ($a)[0 ..< min(60, ($a).len)] & ", nimaki " & ($b)[0 ..< min(60, ($b).len)]
  case a.kind
  of JObject:
    var keys: seq[string]
    for k, _ in a: keys.add k
    for k, _ in b:
      if k notin keys: keys.add k
    for k in keys:
      if not b.hasKey(k): return at & "." & k & ": only Pele has it"
      if not a.hasKey(k): return at & "." & k & ": only nimaki has it"
      let d = firstDifference(a[k], b[k], at & "." & k)
      if d.len > 0: return d
  of JArray:
    if a.len != b.len: return at & ": Pele has " & $a.len & " items, nimaki " & $b.len
    for i in 0 ..< a.len:
      let d = firstDifference(a[i], b[i], at & "[" & $i & "]")
      if d.len > 0: return d
  else: discard
  at & ": Pele has " & ($a)[0 ..< min(60, ($a).len)] & ", nimaki " & ($b)[0 ..< min(60, ($b).len)]

proc differences*(a, b: JsonNode, at = "model", into: var seq[string]) =
  ## Every place where two JSON values differ, as `firstDifference` names them.
  if a == b: return
  if a.kind == b.kind and a.kind == JObject:
    for k, v in a:
      if not b.hasKey(k): into.add at & "." & k & ": only Pele has it"
      else: differences(v, b[k], at & "." & k, into)
    for k, _ in b:
      if not a.hasKey(k): into.add at & "." & k & ": only nimaki has it"
  elif a.kind == b.kind and a.kind == JArray and a.len == b.len:
    for i in 0 ..< a.len: differences(a[i], b[i], at & "[" & $i & "]", into)
  else: into.add firstDifference(a, b, at)

# ------------------------------------------------------------------------------------- main

type Outcome = object
  id, diagramType, verdict, detail: string   ## verdict: same, different, error, unsupported
  all: seq[string]                            ## every difference, with --all

proc main() =
  var only: seq[string]
  var show = 10
  var everyDifference = false
  var packageArg = ""
  for kind, key, val in getopt():
    case kind
    of cmdArgument: only.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "show": show = parseInt(val)
      of "package": packageArg = val
      of "all": everyDifference = true
      else: quit "ERROR unknown option --" & key, 2
    of cmdEnd: discard
  let pkg = packageDirFrom(packageArg)
  var cases: seq[JsonNode]
  for c in parseFile(repoDir / "corpus" / "cases.json")["cases"]:
    if only.len == 0 or c["type"].getStr in only: cases.add c

  # Pele's models, in one run of the oracle.
  var input = ""
  for c in cases:
    input.add $(%*{"id": c["id"], "source": c["source"], "parse": true, "options": {"now": fixedNow}}) & "\n"
  let (output, code) = execCmdEx("node " & quoteShell(repoDir / "tools" / "oracle.mjs") & " " & quoteShell(pkg),
                                 env = newStringTable({"TZ": "UTC", "PATH": getEnv("PATH")}), input = input)
  if code != 0: quit "ERROR the oracle failed:\n" & output, 2
  var pele: Table[string, JsonNode]
  for line in output.splitLines:
    if line.len > 0:
      let j = parseJson(line)
      pele[j["id"].getStr] = j

  var outcomes: seq[Outcome]
  for c in cases:
    let id = c["id"].getStr
    let p = pele[id]
    var o = Outcome(id: id, diagramType: c["type"].getStr)
    try:
      let m = parse(c["source"].getStr, RenderOptions(now: some(fixedNow)))
      if not p["ok"].getBool:
        o.verdict = "different"
        o.detail = "Pele throws " & p["code"].getStr & ", nimaki parses"
      else:
        var theirs = normal(p["model"])
        var ours = normal(dumpModel(m))
        if theirs.kind == JObject:
          theirs.delete("type")
          if theirs.hasKey("mermaidType"): theirs.delete("mermaidType")
        if ours.kind == JObject and ours.hasKey("type"): ours.delete("type")
        if p["model"]{"mermaidType"}.getStr != m.mermaidType:
          o.verdict = "different"
          o.detail = "mermaidType " & p["model"]{"mermaidType"}.getStr & ", nimaki " & m.mermaidType
        else:
          o.detail = firstDifference(theirs, ours)
          o.verdict = if o.detail.len == 0: "same" else: "different"
          if everyDifference: differences(theirs, ours, "model", o.all)
    except PeleError as e:
      if e.code == "unsupported": o.verdict = "unsupported"
      elif not p["ok"].getBool and p["code"].getStr == e.code: o.verdict = "error"   # both throw
      else:
        o.verdict = "different"
        o.detail = "nimaki throws " & e.code & (if p["ok"].getBool: ", Pele parses" else: ", Pele " & p["code"].getStr)
    outcomes.add o

  var byType: OrderedTable[string, CountTable[string]]
  var shown = 0
  for o in outcomes:
    byType.mgetOrPut(o.diagramType, initCountTable[string]()).inc o.verdict
    if o.verdict == "different" and shown < show:
      echo "ERROR ", o.id, ": ", o.detail
      inc shown
  byType.sort(proc (a, b: (string, CountTable[string])): int = cmp(a[0], b[0]))
  var types = newJArray()
  var total: CountTable[string]
  for t, counts in byType:
    echo "  ", t.alignLeft(15), align($counts["same"], 5), " same", align($counts["different"], 5), " different",
      align($counts["error"], 5), " both throw", align($counts["unsupported"], 5), " not ported"
    types.add %*{"type": t, "same": counts["same"], "different": counts["different"],
                 "error": counts["error"], "unsupported": counts["unsupported"]}
    for k, n in counts: total.inc(k, n)
  if only.len == 0:
    writeFile repoDir / "docs" / "data" / "parsediff.json", (%*{
      "about": "Pele's parse() against nimaki's, on corpus/cases.json, by tools/parsediff.nim. Do not edit by hand.",
      "pin": readPin()["TAG"], "cases": outcomes.len, "same": total["same"], "different": total["different"],
      "error": total["error"], "unsupported": total["unsupported"], "types": types}).pretty & "\n"
  createDir repoDir / "build" / "parsediff"
  var report = newJArray()
  for o in outcomes:
    if o.verdict == "different":
      report.add %*{"id": o.id, "type": o.diagramType, "detail": o.detail}
      if everyDifference: report[^1]["all"] = %o.all
  writeFile repoDir / "build" / "parsediff" / "report.json", report.pretty & "\n"
  echo "parsediff: pele ", readPin()["TAG"], ", ", outcomes.len, " cases of ", byType.len, " types: ",
    total["same"], " same model, ", total["different"], " different, ", total["error"], " both throw, ",
    total["unsupported"], " not ported"

when isMainModule:
  main()
