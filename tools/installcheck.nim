## installcheck: nimaki as another project gets it, checked against Pele (decision 0020).
##
##   nim r tools/installcheck.nim [--package:PATH] [--fast:N]
##
## 1. `nimble install` puts this checkout into a nimble directory of its own, in the system's
##    temporary folder, with the dependencies nimaki.nimble asks for, fetched as nimble fetches
##    them (from GitHub, through nimble's package list).
## 2. A small program outside the repository, compiled with only that package on its path (no
##    nim.cfg of nimaki's: Nim's default hashes, no deps/), draws every case of the corpus.
## 3. Pele, run in Node by tools/oracle.mjs, draws the same cases, and the two are compared byte
##    for byte: the same SVG, or the same error code.
## 4. The JavaScript entry point and the C ABI of the installed package are compiled too.
##
## One `ERROR ...` line per problem, a summary last; exits 1 when anything differs or fails.
## A full run writes docs/data/installcheck.json.
## With --fast:N, one case in N (difftest's sampling is by percent; here it is a stride).
import std/[os, osproc, json, strutils, parseopt, tables]
import common

const fixedNow = 1767225600000.0   # 2026-01-01T00:00:00Z, as tools/difftest.nim

const consumer = """
## Not part of nimaki: a project that imports the installed package.
import std/[json, options, os]
import nimaki
var opts = RenderOptions()
opts.now = some(1767225600000.0)
var answers = ""
for line in lines(paramStr(1)):
  if line.len == 0: continue
  let c = parseJson(line)
  var a = %*{"id": c["id"]}
  try:
    a["ok"] = %true
    a["svg"] = %render(c["source"].getStr, opts).svg
  except PeleError as e:
    a = %*{"id": c["id"], "ok": false, "code": e.code}
  answers.add $a & "\n"
writeFile paramStr(2), answers
echo nimakiVersion, " ", peleVersion
"""

proc run(cmd: string): bool =
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    echo "ERROR failed: ", cmd
    for line in output.strip.splitLines[^min(10, output.strip.splitLines.len) .. ^1]: echo "  ", line
  code == 0

var packageArg = ""
var stride = 1
for kind, key, val in getopt():
  if kind in {cmdLongOption, cmdShortOption}:
    case key
    of "package": packageArg = val
    of "fast": stride = max(1, parseInt(val))
    else: quit "ERROR unknown option --" & key, 2
let packageDir = packageDirFrom(packageArg)

let work = getTempDir() / "nimaki-installcheck"
removeDir work
createDir work
let nimbleDir = work / "nimble"

# 1. install
if not run("nimble -y --nimbleDir:" & quoteShell(nimbleDir) & " install"):
  quit "ERROR nimble install failed", 1
var paths, installed: seq[string]
var nimakiDir = ""
for kind, path in walkDir(nimbleDir / "pkgs2"):
  if kind == pcDir:
    paths.add "--path:" & quoteShell(path)
    installed.add path.extractFilename.rsplit('-', 1)[0]   # name-version, without the checksum
    if path.extractFilename.startsWith("nimaki-"): nimakiDir = path
if nimakiDir.len == 0: quit "ERROR nimble installed no nimaki", 1
echo "installcheck: installed ", installed.join(", ")

let flags = "--hints:off --warnings:off --noNimblePath --skipParentCfg " & paths.join(" ")

# 2. the cases, and nimaki's answers from the installed package
var inputs = ""
var count = 0
var i = 0
for path in [repoDir / "corpus" / "cases.json", repoDir / "corpus" / "diagrammari.json"]:
  if not fileExists(path): continue
  for c in parseFile(path)["cases"]:
    if i mod stride == 0:
      inputs.add $(%*{"id": c["id"], "source": c["source"], "options": {"now": fixedNow}}) & "\n"
      inc count
    inc i
writeFile work / "cases.jsonl", inputs
writeFile work / "consumer.nim", consumer
if not run("nim c -d:release " & flags & " -o:" & quoteShell(work / "consumer") & " " &
           quoteShell(work / "consumer.nim")):
  quit "ERROR the program that imports nimaki did not compile", 1
if not run("TZ=UTC " & quoteShell(work / "consumer") & " " & quoteShell(work / "cases.jsonl") & " " &
           quoteShell(work / "nimaki.jsonl")):
  quit "ERROR the program that imports nimaki failed", 1

# 3. Pele's answers, and the comparison
if findExe("node").len == 0: quit "ERROR node not found: install Node 20 or later (the oracle runs in it)", 2
if not run("TZ=UTC node " & quoteShell(repoDir / "tools" / "oracle.mjs") & " " & quoteShell(packageDir) &
           " < " & quoteShell(work / "cases.jsonl") & " > " & quoteShell(work / "pele.jsonl")):
  quit "ERROR the oracle failed", 2

proc load(path: string): Table[string, JsonNode] =
  for line in lines(path):
    if line.len > 0:
      let j = parseJson(line)
      result[j["id"].getStr] = j

func same(a, b: JsonNode): bool =
  a["ok"].getBool == b["ok"].getBool and
    (if a["ok"].getBool: a["svg"].getStr == b["svg"].getStr else: a{"code"}.getStr == b{"code"}.getStr)

let pele = load(work / "pele.jsonl")
let nimaki = load(work / "nimaki.jsonl")
var identical, different = 0
for id, want in pele:
  if id in nimaki and same(want, nimaki[id]): inc identical
  else:
    inc different
    if different <= 10: echo "ERROR different: ", id

# 4. the other two entry points
var builds: seq[string]
if run("nim js -d:danger " & flags & " -o:" & quoteShell(work / "nimaki.js") & " " &
       quoteShell(nimakiDir / "nimaki" / "web.nim")):
  builds.add "nim js of web.nim"
if run("nim c --app:lib -d:release --mm:orc --threads:on -d:useMalloc " & flags & " -o:" &
       quoteShell(work / (DynlibFormat % "nimaki")) & " " &
       quoteShell(nimakiDir / "nimaki" / "capi.nim")):
  builds.add "the C ABI"

let ok = different == 0 and identical == count and builds.len == 2
if stride == 1:
  let nimVersion = execProcess("nim --version").splitLines[0]
  let nimbleText = readFile(repoDir / "nimaki.nimble")
  var version = ""
  for line in nimbleText.splitLines:
    if line.startsWith("version"): version = line.split('"')[1]
  writeFile dataDir / "installcheck.json", pretty(%*{
    "about": "Written by tools/installcheck.nim on a full run: nimaki installed by nimble and drawn from a program outside the repository, against Pele. Do not edit by hand.",
    "nimaki": version, "pele": readPin()["TAG"], "nim": nimVersion, "installed": installed,
    "cases": count, "identical": identical, "different": different, "builds": builds}) & "\n"
echo "installcheck: pele ", readPin()["TAG"], ", ", count, " cases drawn by the installed package: ",
  identical, " identical, ", different, " different; built ", builds.join(" and "),
  (if ok: " (ok)" else: " (FAILED)")
quit(if ok: 0 else: 1)
