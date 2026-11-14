## followpele: is there a Pele newer than the pin, and what in nimaki would it touch?
##
## nimaki ports a snapshot of Pele (reference/PIN). When Pele moves on, the port follows it in a
## step of its own: move the pin, rebuild the corpus, port what changed. This tool does the first
## part of that step, the reading:
##
## - it asks GitHub for Pele's release tags and its main branch, and npm for the latest `pele`;
## - when a release is newer than the pin, it lists the commits since the pin and every file that
##   changed, and maps each file of Pele's `src/` to the Nim files that port it, from the port map
##   (docs/data/portmap.json, built from the `## port-of:` headers by tools/portmap.nim);
## - it writes the result in build/followpele/report.json and prints one line per file, and a
##   summary last.
##
##   nim r tools/followpele.nim                         # the latest release against the pin
##   nim r tools/followpele.nim --from:1.12.0 --to:1.13.0   # any two releases, to try it
##   nim r tools/followpele.nim --main                  # Pele's main branch, released or not
##   nim r tools/followpele.nim --fail                  # exit 1 when Pele is newer than the pin
##
## It reads Pele's history from a copy without file contents (`git clone --filter=blob:none`),
## in build/followpele/pele.git, and changes nothing else.
import std/[os, osproc, strutils, json, tables, algorithm, parseopt, sequtils]
import common

type
  Changed* = object
    path*: string        ## the file in Pele's repository
    added*, removed*: int
    kind*: string        ## ported, not ported, not in the port map, new, deleted, tests, outside src
    nim*: seq[string]    ## the Nim files that port it

proc run(cmd: string, dir = ""): string =
  let (output, code) = execCmdEx(cmd, workingDir = dir)
  if code != 0: quit "ERROR " & cmd & " failed:\n" & output.strip, 2
  output.strip

func versionKey*(tag: string): (int, int, int) =
  ## "1.13.0" as (1, 13, 0), to sort release tags; (-1, -1, -1) for a tag that is not a version.
  let parts = tag.split('.')
  try:
    if parts.len == 3: return (parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2]))
  except ValueError: discard
  (-1, -1, -1)

proc releaseTags(repo: string): seq[(string, string)] =
  ## Pele's release tags (those that are versions) and their commits, oldest first.
  for line in run("git ls-remote --tags " & quoteShell(repo)).splitLines:
    let parts = line.splitWhitespace
    if parts.len != 2 or parts[1].endsWith("^{}"): continue
    let tag = parts[1].replace("refs/tags/", "")
    if versionKey(tag)[0] >= 0: result.add (tag, parts[0])
  result.sort(proc (a, b: (string, string)): int = cmp(versionKey(a[0]), versionKey(b[0])))

func classify*(path, status: string, ported: Table[string, seq[string]],
               known: seq[string]): (string, seq[string]) =
  ## What a changed file of Pele means for the port.
  if path.startsWith("test"): return ("tests", @[])
  if not path.startsWith("src/"): return ("outside src", @[])
  if status == "A": return ("new", ported.getOrDefault(path))
  if status == "D": return ("deleted", ported.getOrDefault(path))
  if ported.getOrDefault(path).len > 0: return ("ported", ported[path])
  if path in known: return ("not ported", @[])
  ("not in the port map", @[])

proc main() =
  var fromArg, toArg: string
  var useMain, failWhenNewer = false
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "from": fromArg = val
      of "to": toArg = val
      of "main": useMain = true
      of "fail": failWhenNewer = true
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: quit "ERROR unexpected argument " & key, 2
    of cmdEnd: discard

  let pin = readPin()
  let repo = pin["REPO"]
  let tags = releaseTags(repo)
  if tags.len == 0: quit "ERROR no release tags found at " & repo, 2
  let latest = tags[^1][0]
  let npmLatest = execCmdEx("npm view pele version").output.strip
  let mainHead = run("git ls-remote " & quoteShell(repo) & " refs/heads/main").splitWhitespace[0]
  echo "pin ", pin["TAG"], " (", pin["COMMIT"][0 ..< 7], "); latest release ", latest,
    "; npm ", (if npmLatest.len > 0: npmLatest else: "not reached"), "; main at ", mainHead[0 ..< 7]

  let fromRef = if fromArg.len > 0: fromArg else: pin["TAG"]
  let toRef = if toArg.len > 0: toArg elif useMain: mainHead else: latest

  let work = repoDir / "build" / "followpele"
  createDir work
  let git = work / "pele.git"
  if dirExists(git): discard run("git fetch -q --tags --filter=blob:none origin '+refs/heads/*:refs/heads/*'", git)
  else: discard run("git clone -q --bare --filter=blob:none " & quoteShell(repo) & " " & quoteShell(git))

  let fromCommit = run("git rev-parse " & quoteShell(fromRef & "^{commit}"), git)
  let toC = run("git rev-parse " & quoteShell(toRef & "^{commit}"), git)
  if fromCommit == toC:
    echo "followpele: Pele at ", toRef, " is the pin's commit: nothing to follow"
    writeFile work / "report.json", (%*{"from": fromRef, "to": toRef, "latest": latest,
      "npm": npmLatest, "main": mainHead, "newer": false, "commits": [], "files": []}).pretty & "\n"
    return

  let commits = run("git log '--format=%h %s' " & fromCommit & ".." & toC, git).splitLines
  var stats: Table[string, (int, int)]
  for line in run("git diff --numstat " & fromCommit & " " & toC, git).splitLines:
    let p = line.split('\t')
    if p.len == 3:
      stats[p[2]] = ((if p[0] == "-": 0 else: parseInt(p[0])), (if p[1] == "-": 0 else: parseInt(p[1])))
  var ported: Table[string, seq[string]]
  var known: seq[string]
  for f in parseFile(repoDir / "docs" / "data" / "portmap.json")["files"]:
    known.add f["path"].getStr
    ported[f["path"].getStr] = f["nim"].getElems.mapIt(it.getStr)
  var files: seq[Changed]
  for line in run("git diff --name-status " & fromCommit & " " & toC, git).splitLines:
    let p = line.split('\t')
    if p.len < 2: continue
    let path = p[^1]
    let (kind, nim) = classify(path, p[0][0 .. 0], ported, known)
    let s = stats.getOrDefault(path)
    files.add Changed(path: path, added: s[0], removed: s[1], kind: kind, nim: nim)

  echo "commits ", fromRef, "..", toRef, ": ", commits.len
  for c in commits: echo "  ", c
  var byKind: CountTable[string]
  for f in files:
    byKind.inc f.kind
    if f.kind in ["outside src", "tests"]: continue
    echo "  ", f.kind.alignLeft(19), " ", f.path.alignLeft(42), (" +" & $f.added & " -" & $f.removed).alignLeft(10),
      (if f.nim.len > 0: "-> " & f.nim.join(", ") else: "")
  writeFile work / "report.json", (%*{"from": fromRef, "to": toRef, "latest": latest, "npm": npmLatest,
    "main": mainHead, "newer": true, "commits": commits, "files": files}).pretty & "\n"
  var parts: seq[string]
  for k in ["ported", "not ported", "not in the port map", "new", "deleted", "tests", "outside src"]:
    if byKind[k] > 0: parts.add $byKind[k] & " " & k
  echo "followpele: ", fromRef, " -> ", toRef, ", ", commits.len, " commits, ", files.len, " files changed (",
    parts.join(", "), "); report in build/followpele/report.json"
  if failWhenNewer and fromArg.len == 0: quit 1

when isMainModule:
  main()
