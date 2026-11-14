## devlog: 14 Nov 2026 I | Following Pele | Pele will keep moving after the pin: a tool that notices a new release each week and lists what it changes in the port, tried on the release before the pin.
## kind: tooling
import std/[strformat, strutils, json, osproc, os, sequtils]
import nimib
import ../blocks

nbInit
nb.usePost()

# The tool runs here, on the last release before the pin, so the page shows what it prints.
let pin = readFile(docsDir / ".." / "reference" / "PIN")
var pinTag = ""
for l in pin.splitLines:
  if l.startsWith("TAG="): pinTag = l[4 .. ^1]
let (now, nowCode) = execCmdEx("nim r --hints:off tools/followpele.nim", workingDir = docsDir / "..")
let (tried, triedCode) = execCmdEx("nim r --hints:off tools/followpele.nim --from:1.12.0 --to:1.13.0",
                                   workingDir = docsDir / "..")
doAssert nowCode == 0 and triedCode == 0, now & tried
let report = parseFile(docsDir / ".." / "build" / "followpele" / "report.json")
var ported, outside, tests = 0
for f in report["files"]:
  case f["kind"].getStr
  of "ported", "new": inc ported
  of "tests": inc tests
  else: inc outside
let upToDate = "nothing to follow" in now
let releases = parseJson(execCmdEx("npm view pele versions --json").output).len

nbText: &"""
## The findings, first

- **Pele has not moved since the pin.** Its latest release, its npm package and its main branch
  are all still {pinTag}, the snapshot nimaki ports. {(if upToDate: "Today there is nothing to follow." else: "")}
- **A tool for the day it does.** `tools/followpele.nim` asks GitHub and npm for Pele's latest
  release, and when it is newer than the pin, lists its commits and every file it changed, each
  with the Nim files that port it.
- **Tried on the release before.** Run from 1.12.0 to 1.13.0, it finds
  {report["commits"].len} commits and {report["files"].len} files: {ported} in Pele's `src/`, all
  with a Nim port, {tests} tests, and {outside} elsewhere (the website, CI).
- **Once a week, in CI.** The weekly run of the pages runs it with `--fail`, so a red weekly run
  is the sign that Pele released.

## Why a port has to follow

nimaki ports Pele as it was on one day: the pin, in `reference/PIN`, names a release and its
commit, and the referee compares nimaki with that release's npm package. That is what makes
"identical, byte for byte" a fixed target. But Pele is alive: npm holds {releases} versions of it
already, and diagrammari, nimaki's first user, will want what the next one brings.

So the pin has to move, now and then, and each move is a step: read what changed, port it, move
the pin and rebuild the corpus, until the referee says identical again. The first part, reading,
is the same every time, so it is a tool.

## What the tool does

It asks three places where Pele is, without downloading it: the release tags on GitHub
(`git ls-remote`), the latest version on npm (`npm view pele version`), and the head of Pele's
main branch. Today it says:
"""

nbCode:
  echo now

nbText: """
When a release is newer than the pin, it takes Pele's history without its files
(`git clone --filter=blob:none`, a few hundred kilobytes) and asks git two questions: which
commits are between the pin and the release, and which files changed, with how many lines. Then
it reads the port map (`docs/data/portmap.json`, which `tools/portmap.nim` builds from the
`## port-of:` line at the top of every Nim file) to find, for each TypeScript file, the Nim file
that ports it.

Each file gets a kind:

- **ported**: a Nim file ports it, and that is where the change goes;
- **new**: a file the release adds, which needs a port;
- **not ported** or **not in the port map**: a file nimaki has not ported (or does not know);
- **deleted**;
- **tests**: Pele's tests, from which the referee's corpus is built: the corpus is rebuilt
  when the pin moves;
- **outside src**: the website, CI, the package files.

## Tried on the release before the pin

To see what it prints on a real release, the tool is run from 1.12.0 to 1.13.0, the release
nimaki's pin is:
"""

nbCode:
  echo tried.strip.splitLines[^1].replace(" commits, ", " commits,\n").replace(" (", "\n(").replace("; report", ";\nreport")

var rows: seq[string]
for f in report["files"]:
  if f["kind"].getStr in ["tests", "outside src"]: continue
  let path = f["path"].getStr.replace("src/", "")
  let same = @["src/nimaki/" & path.changeFileExt("nim")]
  let nims = f["nim"].getElems.mapIt(it.getStr)
  let port = if nims == same: "`.nim`, same path" elif nims.len == 0: "none"
             else: nims.mapIt("`" & it & "`").join(", ")
  rows.add "| `" & path & "` | " & $f["added"].getInt & "/" & $f["removed"].getInt & " | " & port & " |"
nbText: &"""
The files of Pele's `src/` it changed, the lines added and removed, and their port in nimaki's
`src/nimaki/`:

| Pele | +/− | port |
|---|---|---|
{rows.join("\n")}
"""

nbFold "The commits of 1.13.0":
  nbText: "```\n" & report["commits"].getElems.mapIt(it.getStr).join("\n") & "\n```"

nbText: """
The *new* file, `src/svg/palette.ts`, already has a port, because nimaki started from 1.13.0: the
port map knows it. On a real new release a new file has none yet, and the line ends empty.
"""

nbNote """
- The tool lists and maps; it does not port. Moving the pin is a step of its own, with a post, as
  every step is.
- `--main` compares Pele's main branch instead of its latest release, to see what is coming.
""", nkNim, "In the port"

nbNote """
- Today: latest release, npm and main are all the pin (the output above, from this page's build).
- From 1.12.0 to 1.13.0: the files and commits above; each changed file of `src/` maps to the Nim
  file that ports it.
""", nkDone, "Checked"

nbNote """
- The roadmap's step *Following Pele* is done when the pin moves once. That waits for Pele's
  next release: the step stays open, with the tool ready.
- The weekly run has not run the tool yet; it will on its next Monday.
""", nkWarning, "Not checked yet"

nbText: """
## What this changes for the port

- The [Roadmap](../../roadmap/)'s *Following Pele* has its tool. When a weekly run turns red on
  *Pele newer than the pin*, the next step is to run `nim r tools/followpele.nim` and port what it
  lists.

## Sources

- The tool: [`tools/followpele.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/followpele.nim);
  the pin: [`reference/PIN`](https://github.com/pietroppeter/nimaki/blob/main/reference/PIN).
- Pele's releases: [github.com/obsidianmd/pele/tags](https://github.com/obsidianmd/pele/tags), and
  the package on npm: [npmjs.com/package/pele](https://www.npmjs.com/package/pele).
"""

nbSave
