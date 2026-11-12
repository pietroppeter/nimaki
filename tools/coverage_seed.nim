## Seeds docs/data/coverage.json, the coverage map, from a Pele checkout: the shared core part by
## part, and every diagram type split in its three stages (parse, layout, render), with the
## lines of TypeScript of each, the lines of its tests and the cases of its corpus.
##
##   nim r tools/coverage_seed.nim [--ref:PATH]
##
## Safe to rerun when the pin moves: it recounts the TypeScript and keeps what people wrote
## (status, nim, post, notes, owner) for the rows it already has.
##
## The split of a type's files into stages goes by file name, since Pele has no layout file for
## most types (their layout lives in `render.ts` or `graph.ts`): it is a guide to the size of
## each stage, not a promise of where its code is.
import std/[os, strutils, json, tables, algorithm, parseopt]
import common, portmap

const
  parseFiles = ["lexer", "parser", "tokens", "db", "model", "types", "builder", "abnf", "ebnf", "peg",
                "ir", "json", "members", "dates", "format", "diagnostics", "index", "common"]
  layoutFiles = ["layout", "graph", "route", "boundaries", "ticks", "axis", "actors"]
  core = [
    ("text", "measuring text without a browser: font metrics, labels, entities", @["src/text/"]),
    ("svg", "writing SVG: the builder, shapes, edges, clusters, the palette and the theme", @["src/svg/"]),
    ("layout", "the shared layouts: layered (Sugiyama), compound, lanes, components", @["src/layout/"]),
    ("util", "Unicode, URLs, a small YAML reader for front matter", @["src/util/"]),
    ("common", "what several diagram types share: fitting text, scanning, icons", @["src/diagrams/common/"]),
    ("api", "detecting the type, preprocessing, render(), errors, the registry",
     @["src/core.ts", "src/detect.ts", "src/errors.ts", "src/preprocess.ts", "src/types.ts", "src/models.ts",
       "src/index.ts", "src/diagrams/registry.ts"]),
    ("browser", "what only a browser needs: mount, zoom, lazy loading, window, entry points",
     @["src/mount.ts", "src/zoom.ts", "src/lazy.ts", "src/window.ts", "src/entries/"])]
  keep = ["status", "nim", "post", "notes", "owner"]

proc stageOf(file: string): string =
  let name = file.splitFile.name
  if name in layoutFiles: "layout"
  elif name in parseFiles: "parse"
  else: "render"

proc linesUnder(dir: string, prefix = ""): int =
  ## Lines of code of the .ts files under `dir` (whose name starts with `prefix`).
  if not dirExists(dir): return
  for path in walkDirRec(dir):
    if path.endsWith(".ts") and path.extractFilename.startsWith(prefix):
      result += measure(readFile(path)).code

proc corpusCases(refDir, kind: string): int =
  for path in walkFiles(refDir / "tests" / "corpus" / kind & "-*.json"):
    result += parseFile(path).len

proc main() =
  var refArg: string
  for kind, key, val in getopt():
    if kind in {cmdLongOption, cmdShortOption}:
      if key == "ref": refArg = val
      else: quit "ERROR unknown option --" & key, 2
  let refDir = refDirFrom(refArg)
  let pin = readPin()
  let path = dataDir / "coverage.json"
  let old = if fileExists(path): parseFile(path) else: newJObject()

  proc kept(section, key: string, row: JsonNode, fields: openArray[string]) =
    ## Copy what people wrote from the old row with the same key.
    for o in old{section}.getElems:
      if o{"id"}.getStr == key:
        for f in fields:
          if o.hasKey(f): row[f] = o[f]
        for stage in ["parse", "layout", "render"]:
          if o.hasKey(stage) and row.hasKey(stage):
            for f in fields:
              if o[stage].hasKey(f): row[stage][f] = o[stage][f]

  let files = tsFiles(refDir)
  var coreRows = newJArray()
  for (id, what, prefixes) in core:
    var code = 0
    for f in files:
      for p in prefixes:
        if f.startsWith(p): code += measure(readFile(refDir / f)).code
    let row = %*{"id": id, "what": what, "code": code, "status": "planned", "nim": "", "post": "", "notes": ""}
    kept("core", id, row, keep)
    coreRows.add row

  var byType: OrderedTable[string, array[3, int]]
  for f in files:
    let parts = f.split('/')
    if parts.len < 4 or parts[1] != "diagrams" or parts[2] == "common": continue
    let t = parts[2]
    if t notin byType: byType[t] = [0, 0, 0]
    let i = ["parse", "layout", "render"].find(stageOf(f))
    byType[t][i] += measure(readFile(refDir / f)).code
  var types: seq[string]
  for t in byType.keys: types.add t
  types.sort(proc (a, b: string): int =
    let sa = byType[a][0] + byType[a][1] + byType[a][2]
    let sb = byType[b][0] + byType[b][1] + byType[b][2]
    cmp((sa, a), (sb, b)))
  var diagramRows = newJArray()
  for t in types:
    let c = byType[t]
    let tests = linesUnder(refDir / "tests" / "compat" / t) + linesUnder(refDir / "tests" / t) +
                linesUnder(refDir / "tests" / "render", t)
    let row = %*{"id": t, "code": c[0] + c[1] + c[2], "tests": tests, "corpus": corpusCases(refDir, t),
                 "parse": {"code": c[0], "status": "planned"},
                 "layout": {"code": c[1], "status": "planned"},
                 "render": {"code": c[2], "status": "planned"},
                 "nim": "", "post": "", "notes": ""}
    kept("diagrams", t, row, keep)
    diagramRows.add row

  let doc = %*{
    "about": "The coverage map. Seeded by tools/coverage_seed.nim from the Pele checkout (lines of TypeScript, tests, corpus cases); status, nim, post and notes are written by the pull request that ports a part. A status is planned, started, blocked or done; done means difftest finds the Nim output identical to Pele's, byte for byte, on that part's corpus.",
    "pin": {"repo": pin["REPO"], "tag": pin["TAG"], "commit": pin["COMMIT"], "date": pin["DATE"],
            "mermaid": pin["MERMAID"]},
    "stages": [
      {"id": "parse", "name": "Parse", "what": "Mermaid text to a model of the diagram"},
      {"id": "layout", "name": "Layout", "what": "the model to positions and sizes"},
      {"id": "render", "name": "Render", "what": "positions to SVG text"}],
    "core": coreRows, "diagrams": diagramRows}
  writeFile path, doc.pretty & "\n"
  var total = 0
  for r in coreRows: total += r["code"].getInt
  for r in diagramRows: total += r["code"].getInt
  echo "coverage_seed: pele ", pinOf(refDir), ", ", coreRows.len, " core parts and ", diagramRows.len,
    " diagram types, ", total, " lines of TypeScript"
  echo "wrote docs/data/coverage.json"

when isMainModule:
  main()
