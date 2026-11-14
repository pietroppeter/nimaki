## The port map: every TypeScript file of Pele's `src/`, how big it is, which part of Pele it
## belongs to, and which Nim file ports it. Written to docs/data/portmap.json.
##
##   nim r tools/portmap.nim            write the map, print the totals
##   nim r tools/portmap.nim todo       the files nobody ported yet, smallest first
##   nim r tools/portmap.nim check      fail when a Nim file names a TypeScript file that does not exist
##   options: --ref:PATH (a Pele checkout; default reference/pele or $PELE_REF)
##
## A Nim file says what it ports in its first lines, and that is the only bookkeeping:
##
##   ## port-of: src/diagrams/pie/parser.ts
##   ## port-status: draft
##
## `port-of` may be repeated (a Nim file that ports two TypeScript files); `port-part-of` names
## a file ported in pieces. The status is `draft` (translated), `verified` (read against the
## TypeScript by a second pass, no longer required) or `conformant` (difftest and the fuzzer find
## its part identical to Pele, and Pele's tests that reach it pass on the port; decision 0014). A file ported by several Nim files takes the lowest of their
## statuses. Files that will not be ported are listed, with the reason, in
## docs/data/portmap_skip.txt (`path-prefix<TAB>reason`).
import std/[os, strutils, json, tables, algorithm, parseopt]
import common

type
  Status = enum sTodo = "todo", sDraft = "draft", sVerified = "verified", sConformant = "conformant",
                sSkip = "skip"
  TsFile = object
    path, component: string
    lines, code: int
    nim: seq[string]
    status: Status
    reason: string

proc measure*(src: string): tuple[lines, code: int] =
  ## Lines, and lines of code: not blank, not only a comment.
  var inBlock = false
  for raw in src.splitLines:
    inc result.lines
    let line = raw.strip
    if inBlock:
      if "*/" in line: inBlock = false
      continue
    if line.len == 0 or line.startsWith("//"): continue
    if line.startsWith("/*"):
      if "*/" notin line: inBlock = true
      continue
    inc result.code

proc componentOf*(path: string): string =
  ## `src/diagrams/pie/parser.ts` is `diagrams/pie`; `src/layout/layered.ts` is `layout`;
  ## a file directly in `src/` is `api`.
  let parts = path.split('/')
  if parts.len >= 4 and parts[1] == "diagrams": "diagrams/" & parts[2]
  elif parts.len >= 3: parts[1]
  else: "api"

proc tsFiles*(refDir: string): seq[string] =
  ## Every `.ts` file under `src/`, relative to the checkout, sorted.
  for path in walkDirRec(refDir / "src", relative = true):
    if path.endsWith(".ts") and not path.endsWith(".d.ts"):
      result.add ("src/" & path).unixPath
  result.sort

proc nimHeaders(): Table[string, seq[tuple[nim: string, status: Status]]] =
  ## What the Nim files of this repository say they port.
  for folder in ["src", "tests"]:
    if not dirExists(repoDir / folder): continue
    for path in walkDirRec(repoDir / folder, relative = true):
      if not path.endsWith(".nim"): continue
      var origins: seq[string]
      var status = sDraft
      var n = 0
      for line in lines(repoDir / folder / path):
        inc n
        if n > 30: break
        let text = line.strip(chars = {'#', ' '})
        if text.startsWith("port-of:"):
          origins.add text[8 .. ^1].strip.split(' ')[0]
        elif text.startsWith("port-part-of:"):
          origins.add text[13 .. ^1].strip.split(' ')[0]
        elif text.startsWith("port-status:"):
          try: status = parseEnum[Status](text[12 .. ^1].strip.split(' ')[0])
          except ValueError: quit "ERROR " & folder / path & ": unknown port-status in `" & line & "`", 1
      for origin in origins:
        result.mgetOrPut(origin, @[]).add (nim: (folder / path).unixPath, status: status)

proc skips(): seq[tuple[prefix, reason: string]] =
  let path = dataDir / "portmap_skip.txt"
  if fileExists(path):
    for line in lines(path):
      if line.strip.len > 0 and not line.startsWith("#"):
        let parts = line.split('\t', maxsplit = 1)
        result.add (parts[0].strip, if parts.len > 1: parts[1].strip else: "")

proc build(refDir: string): tuple[files: seq[TsFile], unknown: seq[string]] =
  let headers = nimHeaders()
  let skipList = skips()
  var known: seq[string]
  for path in tsFiles(refDir):
    known.add path
    let m = measure(readFile(refDir / path))
    var file = TsFile(path: path, component: componentOf(path), lines: m.lines, code: m.code)
    for (prefix, reason) in skipList:
      if path.startsWith(prefix):
        file.status = sSkip
        file.reason = reason
    if path in headers:
      file.status = sConformant
      for (nim, status) in headers[path]:
        file.nim.add nim
        if status < file.status: file.status = status
    result.files.add file
  for origin in headers.keys:
    if origin notin known: result.unknown.add origin

proc main() =
  var refArg: string
  var args: seq[string]
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      if key == "ref": refArg = val
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: args.add key
    of cmdEnd: discard
  let refDir = refDirFrom(refArg)
  let (files, unknown) = build(refDir)
  for origin in unknown:
    echo "ERROR a Nim file has `port-of: ", origin, "` but Pele has no such file"
  if args.len > 0 and args[0] == "check":
    echo "portmap check: ", (if unknown.len > 0: $unknown.len & " unknown origins" else: "every port-of names a file of Pele")
    quit(if unknown.len > 0: 1 else: 0)
  if args.len > 0 and args[0] == "todo":
    var todo: seq[TsFile]
    for f in files:
      if f.status == sTodo: todo.add f
    todo.sort(proc (a, b: TsFile): int = cmp(a.code, b.code))
    for f in todo: echo align($f.code, 6), "  ", f.path
    echo todo.len, " TypeScript files to port, smallest first"
    return
  var total: array[Status, tuple[files, code: int]]
  var components: OrderedTable[string, array[Status, int]]
  var list = newJArray()
  for f in files:
    inc total[f.status].files
    total[f.status].code += f.code
    if f.component notin components: components[f.component] = default(array[Status, int])
    components[f.component][f.status] += f.code
    var row = %*{"path": f.path, "component": f.component, "lines": f.lines, "code": f.code,
                 "status": $f.status, "nim": f.nim}
    if f.reason.len > 0: row["reason"] = %f.reason
    list.add row
  var totals = newJObject()
  var all = 0
  for s in Status:
    totals[$s] = %*{"files": total[s].files, "code": total[s].code}
    all += total[s].code
  var rows = newJArray()
  for name, by in components:
    var row = %*{"component": name}
    for s in Status: row[$s] = %by[s]
    rows.add row
  createDir dataDir
  writeFile dataDir / "portmap.json", (%*{"pin": pinOf(refDir), "code": all, "totals": totals,
    "components": rows, "files": list}).pretty & "\n"
  let started = all - total[sTodo].code - total[sSkip].code
  echo "portmap: pele ", pinOf(refDir), ", ", files.len, " TypeScript files, ", all, " lines of code to port"
  for s in Status:
    if total[s].files > 0:
      echo "  ", ($s).alignLeft(11), align($total[s].files, 4), " files", align($total[s].code, 8), " lines  ",
        formatFloat(100 * total[s].code / max(all, 1), ffDecimal, 1), "%"
  echo "  ported so far (draft or better): ", started, " lines"
  echo "wrote docs/data/portmap.json"
  if unknown.len > 0: quit 1

when isMainModule:
  main()
