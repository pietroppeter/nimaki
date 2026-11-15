## devlog: 15 Nov 2026 K | A faster CI | Three of the five proposals of Twelve minutes of checks, as Pietro chose them: the checks and the pages run side by side, a pull request of prose skips the checks, and the fuzzers use all four cores. The times before and after, from the first run.
## kind: tooling
import std/[algorithm, json, sequtils, strformat, strutils, tables, times]
import nimib
import tabelline, tabelline/nimib
import ../blocks

nbInit
nb.usePost()

# Before: the runs of Twelve minutes of checks (docs/devlog/data/ci_history/), green builds since
# the workflow last changed before this step. After: the first run of the new workflow, on the
# pull request of this step (docs/devlog/data/a_faster_ci/, by tools/cihistory.nim).
let
  before = parseFile(docsDir / "devlog" / "data" / "ci_history" / "runs.json").getElems
  after = parseFile(docsDir / "devlog" / "data" / "a_faster_ci" / "runs.json").getElems

proc at(s: string): DateTime = parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
proc secs(a, b: string): int = (if a.len == 0 or b.len == 0: -1 else: int((at(b) - at(a)).inSeconds))
proc median(xs: seq[int]): int =
  var s = xs.filterIt(it >= 0)
  if s.len == 0: return 0
  s.sort
  s[s.len div 2]
proc mmss(s: int): string = &"{s div 60}:{s mod 60:02}"
proc job(r: JsonNode, name: string): JsonNode =
  for j in r["jobs"]:
    if j["name"].getStr == name: return j
  nil
proc jobSecs(r: JsonNode, name: string): int =
  let j = r.job(name)
  if j.isNil: -1 else: secs(j["started"].getStr, j["completed"].getStr)
proc stepSecs(r: JsonNode, jobName, step: string): int =
  let j = r.job(jobName)
  if j.isNil: return -1
  for s in j["steps"]:
    if s[0].getStr == step: return s[2].getInt
  -1

# before: the green runs since the last workflow change of Twelve minutes of checks (#82, 15 Nov 06:10 UTC)
let old = before.filterIt(it["conclusion"].getStr == "success" and it["created"].getStr >= "2026-11-15T06:10:32Z" and
                          not it.job("build").isNil)
let oldBuild = median(old.mapIt(it.jobSecs("build")))
let oldFuzz = median(old.mapIt(it.stepSecs("build", "Fuzz")))
let oldMutate = median(old.mapIt(it.stepSecs("build", "Mutate")))
let oldSuites = median(old.mapIt(it.stepSecs("build", "Pele's test suites")))
# after: the first run with a checks job
let first = after.filterIt(not it.job("checks").isNil and it["conclusion"].getStr == "success")[0]
let newChecks = first.jobSecs("checks")
let newPages = first.jobSecs("pages")
let newFuzz = first.stepSecs("checks", "Fuzz")
let newMutate = first.stepSecs("checks", "Mutate")
let newBuildFuzzers = first.stepSecs("checks", "Build the fuzzers")
let newSuites = first.stepSecs("checks", "Pele's test suites")

nbText: &"""
## The findings, first

Pietro picked three of the five proposals of [Twelve minutes of checks](../twelve-minutes-of-checks/)
(proposals 1, 3 and 4), with proposal 2 to follow. They are in the workflow now, and the first run on
them, the run of this very pull request (run {first["number"].getInt}), compares with the
{old.len} green runs before it like this:

| | before | after |
| --- | --- | --- |
| a pull request that changes code | {mmss(oldBuild)} | {mmss(max(newChecks, newPages))} |
| a pull request of prose (a claim, a post) | {mmss(oldBuild)} | about {mmss(newPages)} |
| the 34 fuzzers | {mmss(oldFuzz)} | {mmss(newFuzz)} (+ {mmss(newBuildFuzzers)} to build them) |
| the odd-character fuzzer, 14 rounds | {mmss(oldMutate)} | {mmss(newMutate)} |
| Pele's test suites | {mmss(oldSuites)} | {mmss(newSuites)} |

- **Two jobs side by side.** The old *build* job is now *checks* (the referee, the fuzzers,
  Pele's suites, the tests, the C library) and *pages* (the site, its links, the drift check).
  Each gets its own machine, and they start together.
- **A pull request of prose skips the checks.** When every file a pull request changes is a
  post, a decision, the roadmap, a page or a Markdown file, the checks job stops after its first
  step. The pages are still built, and every diagram of the site is still drawn by nimaki and by
  Pele and compared. A claim takes the time of the pages job; the row above is that job's time in
  this run, not yet a measured claim.
- **The fuzzers use the four cores, optimised.** They are built with `-d:release` and run four at
  a time; so are the odd-character rounds. Building them costs {mmss(newBuildFuzzers)} the first
  time, less when the cache holds most of it.
- **Merges stop queueing.** On `main`, each commit has its own run, and the deploy waits for the
  pages job only. A merge should reach the site in about the time of the pages job; that is
  measured after the first merge, not yet here.
- **Pele's suites got faster too**, but not from this step: the JavaScript build itself became
  faster that morning ([Copies on the way out](../copies-on-the-way-out/)).
- **Pele's suites are now most of a run**: {mmss(newSuites)} of {mmss(newChecks)}. They are the next
  step (proposal 2): their own job, split in two.
"""

nbText: """
## What changed, file by file

- `.github/workflows/pages.yml`: the two jobs; the step *What changed*; the fuzzers and the
  odd-character rounds built once and run with `xargs -P4`; one concurrency group per commit on
  `main`; the deploy checks that its commit is still `main`'s newest before it deploys, because
  runs no longer wait for each other and an older one could finish last.
- `tools/fuzz.nim`: `--no-data`, so four fuzzers at once do not all write `docs/data/fuzz.json`.
- `tools/mutate.nim`: the JavaScript build's files are named by seed, so seven rounds can run at
  once.
- `tools/answers.nim`: with `NIMAKI_JSRUNNER_BUILT=1` the JavaScript runner is not built again; the
  first round builds it, the others use it.

Before the change, all 34 fuzzers ran with `-d:release` four at a time in the sandbox, and the
odd-character fuzzer ran its seven seeds in both builds the same way: no difference with Pele.
`-d:release` keeps Nim's runtime checks, and the referee itself still runs the default build, so
both builds are checked.
"""

nbText: """
## What this changes for the port

- A thread that claims a step waits for the pages job only, not for every check.
- The fuzzer lines stay in the workflow, one per type, in the step *Fuzz*: a port that adds a type
  adds its line there, as before.
- The roadmap step *A faster CI* stays open for proposal 2, Pele's suites in jobs of their own.

## Sources

- The runs: GitHub's Actions API, read by `tools/cihistory.nim` into
  `docs/devlog/data/ci_history/` (before) and `docs/devlog/data/a_faster_ci/` (after).
- The workflow: [`.github/workflows/pages.yml`](https://github.com/pietroppeter/nimaki/blob/main/.github/workflows/pages.yml).
- The proposals: [Twelve minutes of checks](../twelve-minutes-of-checks/), and
  [decision 0021](../../decisions/#0021-posts-record-the-answers-to-their-questions) for why that
  post now shows Pietro's answer.
"""

nbSave
