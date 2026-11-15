## The module pages, docs/modules/<id>/index.html: one page for each island of the coverage map
## (a part of the shared core, or a diagram type). What it does, how far it is ported, its files
## in Pele and in nimaki, what checks it, and the posts that tell its story. Kept up to date: every
## page is written from docs/data/ (coverage.json, portmap.json, difftest.json, fuzz.json,
## peletests.json, roadmap.json) when the pages are built.
import std/[json, strformat, strutils, sequtils, tables, os]
import nimib
import blocks, site

let
  coverage = parseFile(docsDir / "data" / "coverage.json")
  portmap = parseFile(docsDir / "data" / "portmap.json")
  difftest = parseFile(docsDir / "data" / "difftest.json")
  fuzz = parseFile(docsDir / "data" / "fuzz.json")["types"]
  pele = parseFile(docsDir / "data" / "peletests.json")
  roadmap = parseFile(docsDir / "data" / "roadmap.json")
  posts = devlogPosts()

# Pele's browser side lives among the files of the api component in the port map.
const browserFiles = ["src/mount.ts", "src/zoom.ts", "src/window.ts", "src/lazy.ts"]

proc filesOf(id: string, core: bool): seq[JsonNode] =
  ## The files of Pele that make up a module, as the port map lists them.
  for f in portmap["files"]:
    let path = f["path"].getStr
    let component = f["component"].getStr
    let inModule =
      if not core: component == "diagrams/" & id
      else:
        case id
        of "common": component == "diagrams/common"
        of "browser": path in browserFiles or component == "entries"
        of "api": component in ["api", "diagrams"] and path notin browserFiles
        else: component == id
    if inModule: result.add f

proc postTitle(slug: string): string =
  for p in posts:
    if p.slug == slug: return p.title

proc relatedPosts(id, first: string, core: bool, files: seq[JsonNode]): seq[string] =
  ## The slugs of the posts about a module: the one the coverage map names, the roadmap step's,
  ## then the posts whose source names one of its Nim files (or, for a type, its folder), newest
  ## first, eight at most.
  var candidates = @[first]
  for phase in roadmap["phases"]:
    for step in phase["steps"]:
      if step["id"].getStr == id: candidates.add step{"post"}.getStr
  var keys: seq[string]
  if not core: keys.add "diagrams/" & id & "/"
  for f in files:
    for n in f["nim"]: keys.add n.getStr.replace("src/nimaki/", "")
  for p in posts:
    if candidates.len >= 8: break
    let text = readFile(p.file)
    if keys.anyIt(text.contains(it)): candidates.add p.slug
  for slug in candidates:
    if slug.len > 0 and slug notin result and postTitle(slug).len > 0: result.add slug

proc peleTests(prefix: string): (int, int) =
  ## Pele's tests in the files under `prefix`: how many pass on nimaki, of how many.
  for file, c in pele["byFile"]:
    if file.startsWith(prefix):
      for kind, n in c: result[1] += n.getInt
      result[0] += c["passed"].getInt

proc filesTable(files: seq[JsonNode]): string =
  result = "| Pele's file | Lines | Status | In nimaki |\n| --- | ---: | --- | --- |\n"
  for f in files:
    let path = f["path"].getStr
    # The names alone, to fit a phone: each links to the whole path.
    let pele = &"[`{path.extractFilename}`]({pin.repo}/blob/{pin.commit}/{path})"
    var nim: seq[string]
    for n in f["nim"]:
      let p = n.getStr
      nim.add &"[`{p.extractFilename}`]({repoUrl}/blob/main/{p})"
    let st = f["status"].getStr
    let where = if nim.len > 0: nim.join(", ") elif st == "skip": "*not ported:* " & f{"reason"}.getStr else: ""
    result.add &"| {pele} | {f[\"code\"].getInt} | {portStatus(st)} | {where} |\n"

proc countLine(files: seq[JsonNode]): string =
  var byStatus: OrderedTable[string, (int, int)]
  for st in ["conformant", "verified", "draft", "todo", "skip"]: byStatus[st] = (0, 0)
  for f in files:
    let st = f["status"].getStr
    byStatus[st] = (byStatus[st][0] + 1, byStatus[st][1] + f["code"].getInt)
  var parts: seq[string]
  for st, (n, code) in byStatus:
    if n > 0:
      let word = if st == "skip": "not ported on purpose" else: st
      parts.add &"{n} {word} ({code} lines)"
  &"{files.len} files of Pele: " & parts.join(", ") & "."

var shown: seq[string]   # every file put on a page, to check that each is on exactly one

proc modulePage(id, what, nimDir, firstPost, notes: string, st: Status, core: bool, extra: string) =
  nbInit
  nb.doc.filename = docsDir / "modules" / id / "index.html"
  let kind = if core: "Shared core" else: "Diagram type"
  nb.usePage(section = "Modules", cadence = "kept up to date", title = &"{id} · nimaki",
             homeHref = "../../coverage/", backLabel = "Coverage map", reviewPage = "modules/" & id,
             description = &"{kind}: {id}. What it does, how far it is ported, its files in Pele and in nimaki.")
  nbTitle &"{kind} · kept up to date", id, (if what.len > 0: what.capitalizeAscii & "." else: "")
  let files = filesOf(id, core)
  for f in files: shown.add f["path"].getStr
  var lead = &"Status: {status(st)}. " & countLine(files)
  if nimDir.len > 0:
    let kindOfLink = if nimDir.endsWith(".nim"): "blob" else: "tree"
    lead.add &" In nimaki: [`{nimDir}`]({repoUrl}/{kindOfLink}/main/{nimDir})."
  nbText: lead
  if notes.len > 0: nbText: notes
  if extra.len > 0: nbText: extra
  nbText: "## Its files\n\nEach file of Pele at the pin, and the Nim that ports it; a name links to the file. *Conformant* is proven equal to Pele by the referee, the fuzzers and Pele's own tests ([decision 0014](../../decisions/#0014-tests-and-fuzzing-make-a-file-conformant-without-a-second-reading)).\n\n" & filesTable(files)
  let related = relatedPosts(id, firstPost, core, files)
  if related.len > 0:
    nbText: "## In the devlog\n\n" & related.mapIt(&"- [{postTitle(it)}](../../devlog/{it}/)").join("\n")
  nbText: "## See also\n\n- The [coverage map](../../coverage/), every module at a glance.\n- The [porting guide](../../porting/), how Pele's TypeScript is written in Nim here."
  nbSave

for c in coverage["core"]:
  let id = c["id"].getStr
  let nimDir = c{"nim"}.getStr.strip(chars = {'/'}, leading = false)
  var extra = ""
  let (passed, total) = peleTests("tests/" & id & "/")
  if total > 0: extra = &"Pele's tests in `tests/{id}/`: **{passed}** of {total} pass on nimaki."
  modulePage(id, c["what"].getStr, nimDir, c{"post"}.getStr, c{"notes"}.getStr,
             toStatus(c{"status"}.getStr), core = true, extra)

for d in coverage["diagrams"]:
  let id = d["id"].getStr
  var checks: seq[string]
  for t in difftest["types"]:
    if t["coverage"].getStr == id:
      checks.add &"the referee: **{t[\"identical\"].getInt}** of {t[\"cases\"].getInt} drawings of Pele's corpus identical, byte for byte"
      if t.hasKey("diagrammari"):
        checks.add &"**{t[\"diagrammari\"][\"identical\"].getInt}** of {t[\"diagrammari\"][\"cases\"].getInt} of diagrammari's"
  if fuzz.hasKey(id):
    checks.add &"the fuzzer: **{fuzz[id][\"identical\"].getInt}** of {fuzz[id][\"cases\"].getInt} generated diagrams identical"
  let (passed, total) = peleTests("tests/" & id & "/")
  if total > 0: checks.add &"Pele's own tests in `tests/{id}/`: **{passed}** of {total} pass"
  var stages = "| Stage | Lines of Pele | Status |\n| --- | ---: | --- |\n"
  for stage in ["parse", "layout", "render"]:
    stages.add &"| {stage} | {d[stage][\"code\"].getInt} | {status(toStatus(d[stage][\"status\"].getStr))} |\n"
  let extra = (if checks.len > 0: "What checks it: " & checks.join("; ") & ".\n\n" else: "") & stages
  let overall = if ["parse", "layout", "render"].allIt(d[it]["status"].getStr == "done"): stDone else: stStarted
  modulePage(id, "", d{"nim"}.getStr.strip(chars = {'/'}, leading = false), d{"post"}.getStr,
             d{"notes"}.getStr, overall, core = false, extra)

doAssert shown.len == portmap["files"].len and shown.deduplicate.len == shown.len,
  "modules.nim: every file of the port map must be on exactly one module page"
