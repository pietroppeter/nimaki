## devlog: 15 Nov 2026 M | Two machines for Pele's suites | The last proposal of Twelve minutes of checks: Pele's test suites leave the checks job and run in two halves on two machines of their own. The times before and after, from the first run.
## kind: tooling
import std/[json, sequtils, strformat, strutils, times]
import nimib
import ../blocks

nbInit
nb.usePost()

# Before: the first run of A faster CI (docs/devlog/data/a_faster_ci/). After: the first run of
# this step's workflow, on its pull request (docs/devlog/data/two_machines_for_peles_suites/, by
# tools/cihistory.nim).
let
  before = parseFile(docsDir / "devlog" / "data" / "a_faster_ci" / "runs.json").getElems
  after = parseFile(docsDir / "devlog" / "data" / "two_machines_for_peles_suites" / "runs.json").getElems

proc at(s: string): DateTime = parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
proc secs(a, b: string): int = (if a.len == 0 or b.len == 0: -1 else: int((at(b) - at(a)).inSeconds))
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
proc runSecs(r: JsonNode): int =
  ## From the first job's start to the last job's end, deploy aside.
  var first, last = ""
  for j in r["jobs"]:
    if j["name"].getStr == "deploy": continue
    if first.len == 0 or j["started"].getStr < first: first = j["started"].getStr
    if j["completed"].getStr > last: last = j["completed"].getStr
  secs(first, last)

let old = before.filterIt(not it.job("checks").isNil and it["conclusion"].getStr == "success")[0]
let oldChecks = old.jobSecs("checks")
let oldSuites = old.stepSecs("checks", "Pele's test suites")
let oldRun = old.runSecs

let first = after.filterIt(not it.job("suites (1)").isNil and it["conclusion"].getStr == "success")[0]
let newChecks = first.jobSecs("checks")
let newRun = first.runSecs
let part1 = first.jobSecs("suites (1)")
let part2 = first.jobSecs("suites (2)")
let suites1 = first.stepSecs("suites (1)", "Pele's test suites, part 1 of 2")
let suites2 = first.stepSecs("suites (2)", "Pele's test suites, part 2 of 2")
let changesJob = first.jobSecs("changes")
let suiteFiles = parseFile(docsDir / "data" / "peletests.json")["files"].getInt
# The first merge on the workflow of A faster CI (PR #95): from the push to the end of the deploy.
let merge = after.filterIt(it["event"].getStr == "push" and it["sha"].getStr.startsWith("d392637"))[0]
let mergeLive = secs(merge["created"].getStr, merge.job("deploy")["completed"].getStr)

nbText: &"""
## The findings, first

[Twelve minutes of checks](../twelve-minutes-of-checks/) made five proposals, and Pietro chose
1, 3 and 4 first, then 2. [A faster CI](../a-faster-ci/) did the first three. This step does
proposal 2: Pele's test suites, which were most of what was left, now run in a job of their
own, in two halves, on two machines. The first run on it, the run of this very pull request (run
{first["number"].getInt}), compares with the first run of *A faster CI* (run {old["number"].getInt})
like this:

| | before | after |
| --- | --- | --- |
| a pull request that changes code, start to end | {mmss(oldRun)} | {mmss(newRun)} |
| the checks job | {mmss(oldChecks)} | {mmss(newChecks)} |
| Pele's test suites | {mmss(oldSuites)}, inside the checks | {mmss(suites1)} and {mmss(suites2)}, side by side |
| a suites job, setup included | | {mmss(part1)} and {mmss(part2)} |

- **Four jobs where there were two.** *changes* looks at what a pull request changes and says
  whether the code needs checking ({mmss(changesJob)}); *checks* runs the referee, the fuzzers,
  the tests and the C library; *suites* runs Pele's suites in two parts; *pages* builds the site.
  The last three start together.
- **A pull request of prose still skips the checks**, now as two skipped jobs: *checks* and both
  *suites* wait for *changes* and do not run when it says no code changed.
- **The halves are balanced by time, not by count.** Pele's suites are {suiteFiles} test files,
  and some take much longer than others. `tools/peletests.nim --shard:K/N` sorts the files by
  the time each takes on Pele, longest first, and gives each file to the half with the least time
  so far. The same pin always gives the same halves.
- **Half the files did not take half the time**: {mmss(suites1)} and {mmss(suites2)}, against
  {mmss(oldSuites)} for all of them. Why was not measured here: the runs do not keep each file's
  time. Two likely reasons: the halves are balanced by Pele's times, but the slow files on nimaki
  are its stress tests, where the JavaScript build is slower than Pele; and each file starts its
  own vitest, a cost that does not shrink with the half. Recording each file's time on nimaki is
  the next thing to try, to balance on that.
- **The checks job fell from {mmss(oldChecks)} to {mmss(newChecks)}**, more than the suites it
  lost: run {old["number"].getInt} was the first with the job's new cache, and compiled its tools
  from nothing.
- **A merge reaches the site in {mmss(mergeLive)}.** *A faster CI* left this to measure after its
  first merge: its own merge (run {merge["number"].getInt}) went from the push to the end of the
  deploy in {mmss(mergeLive)}, where the morning's merges had waited for every check and for each other
  ([Twelve minutes of checks](../twelve-minutes-of-checks/) has their median).
- **What a pull request costs now is its slowest job**: {mmss(max([newChecks, part1, part2]))} of
  {mmss(newRun)}, a suites half. Setting up a job is quick with the caches ({mmss(part1 - suites1)}
  of the first half), so a third part would help, once the parts are balanced on nimaki's times.
"""

nbText: """
## What changed, file by file

- `.github/workflows/pages.yml`: the job *changes*, with the step *What changed* that was the
  first step of *checks*; *checks* and *suites* wait for it and run only when it says the code
  changed; *suites* is one job run twice (a *matrix*, GitHub's word for one job with a list of
  values: here the parts 1 and 2), each with its own setup and its own Nim cache.
- `tools/peletests.nim`: `--shard:K/N`, the K-th of N parts. A part does not write
  `docs/data/peletests.json`: the counts of all the suites come from a run of them all, on a
  laptop or in a sandbox, as before.

## What this changes for the port

- A thread waits for the slowest of three jobs instead of one long one.
- A test file added to Pele's suites (when the pin moves) goes to a half by its time on Pele, with
  nothing to change here.
- The roadmap step *A faster CI* is done: the five proposals were chosen or declined, and the
  chosen ones are in the workflow. Auto-merge (proposal 5) was not chosen.

## Sources

- The runs: GitHub's Actions API, read by `tools/cihistory.nim` into
  `docs/devlog/data/a_faster_ci/` (before) and `docs/devlog/data/two_machines_for_peles_suites/`
  (after).
- The workflow: [`.github/workflows/pages.yml`](https://github.com/pietroppeter/nimaki/blob/main/.github/workflows/pages.yml).
- The proposals: [Twelve minutes of checks](../twelve-minutes-of-checks/).
"""

nbSave
