## devlog: 15 Nov 2026 F | Twelve minutes of checks | Every pull request of nimaki runs every check of the port: the referee in C and in JavaScript, 34 fuzzers, Pele's own test suites, every page. In three days a run grew from half a minute to twelve. Where the time goes, what CI caught, and how a small pull request could be green in two minutes.
## kind: tooling
import std/[algorithm, json, math, sequtils, strformat, strutils, tables, times]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site, ../pele

nbInit
nb.usePost()

# ---------------------------------------------------------------------------------------------
# The data: tools/cihistory.nim read GitHub Actions and git, and wrote these three files.
const here = docsDir / "devlog" / "data" / "ci_history"
let
  runs = parseFile(here / "runs.json").getElems
  history = parseFile(here / "workflow.json").getElems
  bench = parseFile(here / "bench.json")
  peleTests = parseFile(docsDir / "data" / "peletests.json")
  corpusCases = parseFile(docsDir / "data" / "difftest.json")["cases"].getInt

proc at(s: string): DateTime = parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
proc secs(a, b: string): int =
  ## The seconds from a to b, or -1 when one is missing (a job that never started).
  if a.len == 0 or b.len == 0: -1 else: int((at(b) - at(a)).inSeconds)
proc utc(s: string): DateTime = parse(s, "yyyy-MM-dd'T'HH:mm:sszzz").utc
  ## a time as git writes it (with its offset), in UTC
proc median(xs: seq[int]): int =
  if xs.len == 0: return 0
  var s = xs
  s.sort
  s[s.len div 2]
proc minutes(s: int): string = &"{s / 60:.1f}"
proc r0(x: float): int = int(round(x))
proc mmss(s: int): string = &"{s div 60}:{s mod 60:02}"

proc job(r: JsonNode, name: string): JsonNode =
  for j in r["jobs"]:
    if j["name"].getStr == name: return j
  nil
proc buildSecs(r: JsonNode): int =
  let j = r.job("build")
  if j.isNil: -1 else: secs(j["started"].getStr, j["completed"].getStr)

let
  finished = runs.filterIt(it["status"].getStr == "completed")
  green = finished.filterIt(it["conclusion"].getStr == "success")
  failed = finished.filterIt(it["conclusion"].getStr == "failure")
  cancelled = finished.filterIt(it["conclusion"].getStr == "cancelled")
  prRuns = finished.filterIt(it["event"].getStr == "pull_request")
  pushRuns = finished.filterIt(it["event"].getStr == "push")
  first = at(runs[0]["created"].getStr)
  last = at(runs[^1]["created"].getStr)
  greenBuilds = green.mapIt(it.buildSecs).filterIt(it >= 0)

# Runner time: every job that ran, start to end.
var runnerSecs, cancelledSecs = 0
for r in finished:
  for j in r["jobs"]:
    let s = secs(j["started"].getStr, j["completed"].getStr)
    if s > 0:
      runnerSecs += s
      if r["conclusion"].getStr == "cancelled": cancelledSecs += s

let
  seqDebug = bench["sequential"]["debug"].getFloat
  seqRelease = bench["sequential"]["release"].getFloat
  parDebug = bench["parallel4"]["debug"].getFloat
  parRelease = bench["parallel4"]["release"].getFloat

# The workflow as it is now: the last change on main, and the runs since.
let lastChange = history[^1]
let since = green.filterIt(at(it["created"].getStr) >= utc(lastChange["date"].getStr))
var stepSecs = initOrderedTable[string, seq[int]]()
for r in since:
  let j = r.job("build")
  if j.isNil: continue
  for s in j["steps"]:
    let name = s[0].getStr
    if s[2].getInt < 0 or name.startsWith("Post ") or name in ["Set up job", "Complete job"]: continue
    stepSecs.mgetOrPut(name, @[]).add s[2].getInt
let nowBuild = median(since.mapIt(it.buildSecs))
proc stepMedian(name: string): int = median(stepSecs.getOrDefault(name))
let
  peleSuites = stepMedian("Pele's test suites")
  fuzzSecs = stepMedian("Fuzz")
  mutateSecs = stepMedian("Mutate")
  bigThree = peleSuites + fuzzSecs + mutateSecs

# Runs on main wait for the one before: the build job is created only when it may start.
var mainWait: seq[int]
var latency: seq[int]     # a merge, to its pages deployed
var latencyToday: seq[int]
for r in pushRuns:
  let b = r.job("build")
  if not b.isNil and b["created"].getStr.len > 0:
    mainWait.add secs(r["created"].getStr, b["created"].getStr)
  let d = r.job("deploy")
  if r["conclusion"].getStr == "success" and not d.isNil and d["completed"].getStr.len > 0:
    let s = secs(r["created"].getStr, d["completed"].getStr)
    latency.add s
    if r["created"].getStr >= "2026-11-15": latencyToday.add s
let waited = mainWait.filterIt(it > 60)
let cancelledMain = cancelled.filterIt(it["event"].getStr == "push")
let cancelledPr = cancelled.filterIt(it["event"].getStr == "pull_request")

# Pull requests that only claim a step: their title starts with Claim (or "Roadmap: claim").
let claims = prRuns.filterIt(it["title"].getStr.startsWith("Claim") or
                             it["title"].getStr.toLowerAscii.startsWith("roadmap: claim"))

# PR #80: green at night, merged in the morning (its last pull-request run and the push after it).
let pr80run = finished.filterIt(it["event"].getStr == "pull_request" and
                                it["title"].getStr.startsWith("Odd characters"))[^1]
let pr80merge = pushRuns.filterIt(it["title"].getStr.startsWith("Merge pull request #80"))[0]
let pr80green = pr80run.job("build")["completed"].getStr
let pr80idle = secs(pr80green, pr80merge["created"].getStr)

# The eras: a workflow change that added a check starts one; each era's median green build.
type Era = object
  date, pr, added: string
  fuzzers, runs, median: int
var eras: seq[Era]
for i, h in history:
  let added = h["added"].getElems.mapIt(it.getStr).filterIt(not it.startsWith("uses ") and not it.startsWith("run "))
  if i > 0 and added.len == 0: continue
  eras.add Era(date: h["date"].getStr, pr: h["pr"].getStr,
               added: (if i == 0: "the first workflow" else: added.join(", ")),
               fuzzers: h["fuzz"].len)
# A run belongs to the era of the last change to main before it was created (in UTC).
for i in 0 ..< eras.len:
  let start = utc(eras[i].date)
  let stop = if i + 1 < eras.len: utc(eras[i + 1].date) else: dateTime(2100, mJan, 1, zone = utc())
  let inEra = green.filterIt(at(it["created"].getStr) >= start and at(it["created"].getStr) < stop)
  eras[i].runs = inEra.len
  eras[i].median = median(inEra.mapIt(it.buildSecs).filterIt(it >= 0))
  # the most fuzzers the era reached (each port added its fuzzer without a new step)
  for h in history:
    if utc(h["date"].getStr) >= start and utc(h["date"].getStr) < stop:
      eras[i].fuzzers = max(eras[i].fuzzers, h["fuzz"].len)

let biggestEra = block:
  var best = 1
  for i in 1 ..< eras.len:
    if eras[i].median - eras[i - 1].median > eras[best].median - eras[best - 1].median: best = i
  best
let claimNow = median(claims.filterIt(at(it["created"].getStr) >= utc(eras[biggestEra].date)).mapIt(it.buildSecs).filterIt(it > 0))
doAssert eras[biggestEra].added == "Pele's test suites", "the text says the suites cost the most: " & eras[biggestEra].added

# ---------------------------------------------------------------------------------------------

nbText: &"""
## The findings, first

- **One workflow checks everything, on every pull request.** In {(last - first).inHours} hours
  (12 to 15 November) it ran **{runs.len} times**: {prRuns.len} for pull requests,
  {pushRuns.len} after a merge to `main`. {green.len} were green, {failed.len} failed and
  {cancelled.len} were cancelled, almost all of them on purpose. Together they kept GitHub's
  machines busy for **{runnerSecs div 3600} hours**.
- **A run went from {eras[0].median} seconds to {minutes(nowBuild)} minutes.** Each port added a
  fuzzer, and five new checks joined: the JavaScript build, labels with icons and math, the C
  library, the odd-character fuzzer and, the most expensive by far, Pele's own test suites.
- **Three checks take {bigThree * 100 div nowBuild}% of a run today**: Pele's test suites
  ({mmss(peleSuites)}), the 34 fuzzers ({mmss(fuzzSecs)}) and the odd-character fuzzer
  ({mmss(mutateSecs)}). Everything else, setup and the pages included, is
  {mmss(nowBuild - bigThree)}.
- **Merges wait for each other.** Runs on `main` go one at a time. When threads merge close
  together, a merge waits for the run before it: {waited.len} of {mainWait.len} runs on main waited
  more than a minute, the longest {mmss(max(mainWait))}. Today a merge took a median of
  {minutes(median(latencyToday))} minutes to reach the site.
- **CI caught real bugs.** None of the {failed.len} failures was CI's own fault. Three groups came
  from CI running an older Nim than the sandbox; the others were a gantt chart that read "time
  zero" as "no time", a regular-expression change that broke gantt in the JavaScript build, and a
  page that did not compile.
- **Ten minutes is too much for a small pull request.** A roadmap claim changes one line of JSON
  and waits the full run. Four changes, none of which drop a check, would bring a claim to about
  two minutes and a pull request of code to about five. One of them is easy and measured: the
  fuzzers run {r0(seqDebug / parRelease)} times faster built with `-d:release` and four at a time.
  They are proposals at the end, for Pietro to choose from: this post changes nothing in the workflow.
"""

nbText: """
## CI, from scratch

*CI* stands for *continuous integration*: every change is checked by a machine before it joins
the main line of the code, so that the main line always works. nimaki uses GitHub's service for
it, GitHub Actions. A few words come back in this post:

| Word | What it means here |
| --- | --- |
| workflow | a file in `.github/workflows/` that says what to run and when; nimaki has one, `pages.yml` |
| run | one execution of the workflow, for one commit |
| job | a part of a run that gets a machine of its own; nimaki's runs have two jobs, *build* and *deploy* |
| step | one command inside a job; the steps of a job run one after another |
| runner | the machine a job runs on: a fresh virtual computer with 4 processor cores, thrown away after the job |
| trigger | what starts a run: a push to `main`, a pull request, a weekly timer, or a click |
| cache | files saved at the end of one run and restored at the start of the next, so they are not built again |
| concurrency group | a name shared by runs that must not overlap; GitHub makes one wait for, or cancel, the other |
| green, red | a run that passed, a run that failed |

Two jobs: **build** runs all the checks and builds the pages; **deploy**, only on `main`, puts
the pages on the site. Deploy starts when build is green, so a page goes live only when every
check has passed.
"""

nbText: &"""
## What a run checks

The build job's steps, in order, with their median time over the {since.len} green runs since
the workflow last changed ({lastChange["subject"].getStr.split(':')[0]}, pull request #{lastChange["pr"].getStr}).
"""

block:
  type Row = object
    step, checks: string
    seconds: int
  let what = {
    "Run actions/checkout@v4": "gets the code, with its whole history (a page's version counts the commits that changed it)",
    "No committed HTML": "no generated page was committed by mistake",
    "Run jiro4989/setup-nim-action@v2": "installs Nim 2.2.14 (decision 0015)",
    "Run actions/setup-node@v4": "installs Node 22, which runs Pele",
    "Run sh tools/setup.sh": "the same setup as a laptop or a sandbox: dependencies, the pinned Pele",
    "Port map": "every port-of header names a file of Pele at the pin",
    "Corpus matches the pin": "the " & corpusCases.thousands & " test inputs are the ones Pele's repository gives",
    "Difftest self test": "the referee can fail: it notices a one-byte difference",
    "Difftest": "the referee: every input, nimaki's SVG against Pele's, byte for byte",
    "Difftest with icons and math": "the same, with a host's icons and math typesetter",
    "Difftest of the JavaScript build": "the same, with nimaki compiled to JavaScript",
    "Fuzz": "34 fuzzers: thousands of generated inputs per type, against Pele",
    "Mutate": "the corpus with one odd character slipped in, 7 seeds, both builds",
    "Pele's test suites": "Pele's own " & peleTests["tests"].getInt.thousands & " tests, run on nimaki's JavaScript build",
    "Tests": "nimaki's own tests, all in one program",
    "C ABI": "nimaki as a C library, called from Python, against Pele",
    "Compile the pages": "compiles the site, one program for every page",
    "Build the pages": "builds every page; each diagram is drawn by nimaki and by Pele, and must match",
    "Links": "every link of the site leads to a page, an anchor or a file",
    "Pele newer than the pin": "weekly only: has Pele released past the pin?",
    "No HTML, styles or colours in the pages": "the pages are made of blocks (the drift check)",
    "Assemble site": "puts the pages, fonts and images together",
    "Run actions/upload-pages-artifact@v3": "hands the site to the deploy job"}.toTable
  var rows: seq[Row]
  var shown = 0
  for name, xs in stepSecs:
    if name notin what: continue
    rows.add Row(step: name.replace("Run ", "").replace("@v4", "").replace("@v3", "").replace("@v2", ""),
                 checks: what[name], seconds: median(xs))
    shown += median(xs)
  let t = tabella(rows, rownameCol = "step"):
    tabHeader "One run, step by step", "median seconds over the green runs since the last change to the workflow"
    optCssTheme()
  nbTable t

nbText: &"""
The steps above add up to about {minutes(nowBuild - 30)} minutes; the rest is the runner starting
up and saving the caches. Three steps are most of it. Here is the same run as a timeline, drawn by
nimaki (and checked against Pele, like every diagram of this site): each bar starts when the step
before it ends.
"""

block:
  # a gantt chart of the median run: one bar a group of steps, in seconds (dateFormat X)
  var groups: seq[(string, int)]
  var rest = 0
  for name, xs in stepSecs:
    let s = median(xs)
    case name
    of "Pele's test suites": groups.add ("Pele's suites", s)
    of "Fuzz": groups.add ("34 fuzzers", s)
    of "Mutate": groups.add ("Odd characters", s)
    of "Difftest", "Difftest with icons and math", "Difftest of the JavaScript build", "Difftest self test":
      if groups.len == 0 or groups[^1][0] != "Referee": groups.add ("Referee", s)
      else: groups[^1][1] += s
    of "Compile the pages", "Build the pages", "Links", "No HTML, styles or colours in the pages", "Assemble site":
      if groups.len == 0 or groups[^1][0] != "Pages": groups.add ("Pages", s)
      else: groups[^1][1] += s
    of "Tests", "C ABI":
      if groups.len == 0 or groups[^1][0] != "Tests, C library": groups.add ("Tests, C library", s)
      else: groups[^1][1] += s
    else:
      if groups.len == 0: rest += s
      elif groups[^1][0] != "Setup": rest += s
  groups.insert(("Setup", rest), 0)
  var text = "gantt\n    dateFormat X\n    axisFormat %M:%S\n    section One run\n"
  var t = 0
  for (label, s) in groups:
    text.add &"    {label} : {t}, {max(s, 1)}s\n"
    t += s
  nbMermaid text, "A run of the build job, median step times (minutes:seconds)", %*{"maxWidth": 390, "now": 0}

nbText: """
## How it grew

The workflow was written with the foundation of the project and has changed in almost every
pull request that ported a diagram type, because each port added its fuzzer to the list. The
table counts a new *era* at each change that added a check, and gives the median green build of
the era.
"""

block:
  type Row = object
    since, check: string
    fuzzers, runs: int
    minutes: string
  var rows: seq[Row]
  for e in eras:
    let d = utc(e.date)
    rows.add Row(since: d.format("d MMM HH:mm") & (if e.pr.len > 0: " (#" & e.pr & ")" else: ""),
                 check: e.added, fuzzers: e.fuzzers, runs: e.runs, minutes: minutes(e.median))
  let t = tabella(rows, rownameCol = "since"):
    tabHeader "Every check that joined, and what a run took after it", "times in UTC; runs: green runs of the era; minutes: their median build"
    optCssTheme()
  nbTable t

block:
  var labels, values: seq[string]
  for e in eras:
    labels.add "\"#" & e.pr & "\""
    values.add minutes(e.median)
  let top = int(ceil(max(eras.mapIt(it.median)) / 60)) + 1
  let text = "xychart-beta\n    title \"Median build, minutes\"\n    x-axis [" & labels.join(", ") &
             "]\n    y-axis \"minutes\" 0 --> " & $top & "\n    bar [" & values.join(", ") & "]\n"
  nbMermaid text, "The median green build after each pull request that added a check", %*{"maxWidth": 390}

nbText: &"""
Two jumps stand out. The fuzzers came one by one, one for each type ported, up to 34, and a run
grew with them, a few seconds each: by the time the C library joined, a run took
{minutes(eras[^4].median)} minutes. Then **Pele's own suites** joined (pull request #64,
[Pele's tests on nimaki](../pele-tests-on-nimaki/)): {peleTests["tests"].getInt.thousands} tests in {peleTests["files"].getInt} files, written by
Pele's authors, run on nimaki's JavaScript build four files at a time. They are worth it, they
found six bugs on the first day, but they took a run from {minutes(eras[biggestEra - 1].median)} to
{minutes(eras[biggestEra].median)} minutes at once.

The suites became faster since, as the JavaScript build did
([Faster in JavaScript](../faster-in-javascript/),
[JavaScript's own regular expressions](../javascripts-own-regular-expressions/)): a slow test
is a slow run.
"""

nbText: &"""
## What failed, and what it caught

{failed.len} runs failed. Every one was a real difference that CI saw and the sandbox, where the
code was written, did not:

| Runs | Pull request | What failed | Why |
| --- | --- | --- | --- |
| 104 | c4 and block | the referee, before running | the c4 layout did not compile: a kind of closure that Nim 2.2.4, CI's Nim then, cannot build, and the sandbox's newer Nim can |
| 106, 108 | nimaki in JavaScript | the JavaScript build | cynefin's curves differed: CI ran Nim 2.2.4 and the sandbox a newer Nim, which compute one multiplication differently in JavaScript ([the post](../nimaki-in-javascript/)) |
| 202 | Pele's tests | Pele's suites | 44 tests ran out of stack, again only with Nim 2.2.4; CI moved to Nim 2.2.14 ([decision 0015](../../decisions/#0015-ci-builds-with-the-latest-nim-2-2-release)) |
| 208 to 217 | regular expressions | the JavaScript build | gantt crashed in JavaScript with the new regular-expression library, four times while it was fixed |
| 221 | regular expressions | compiling the pages | an example in the porting guide (a pattern written `/.../`) that Nim read as code |
| 229, 230 | two branches, just after #64 | Pele's suites | a gantt test passes `now: 0`; nimaki read 0 as "no time given" and used the clock, as Pele does not; fixed in the next commit |

Three of the six rows are the same lesson: CI and the sandbox ran different versions of Nim, and
the difference showed only in CI. Since decision 0015 both run the latest Nim 2.2, and the porting
guide says which.

**{cancelled.len} runs were cancelled**, and that is mostly by design. When a branch gets a new
commit, its old run is cancelled: {cancelledPr.len} runs of pull requests ended so, most of them in
the first seconds ({cancelledSecs div 60} minutes of machine time in all). The other
{cancelledMain.len} were runs on `main`, cancelled while they waited, for a reason the next section
explains. Their changes were not lost: the run after them built and deployed them.
"""

nbText: &"""
## Where the time goes

**The checks themselves.** {bigThree * 100 div nowBuild}% of a run is three steps, and each one
runs one thing at a time on a machine with four cores:

- the 34 fuzzers run one after another, each with one process of nimaki and one of Node;
- the odd-character fuzzer runs its 14 rounds (7 seeds, two builds) one after another;
- Pele's suites run four test files at a time, which uses the four cores, but they are {peleTests["files"].getInt} files.

**Every check, for every change.** A pull request that changes one line of the roadmap runs the
same {minutes(nowBuild)} minutes as one that rewrites the layout. There were {claims.len} runs for
claim pull requests; since Pele's suites joined, a claim waits a median {minutes(claimNow)}
minutes; the rule that a claim is
merged before the work starts (AGENTS.md) means that each step starts with that wait.

**Merges in a queue.** All runs on `main` share one concurrency group, so a run waits for the one
before it to finish. GitHub keeps only one run waiting in a group: when a third merge comes, the
run that was waiting is cancelled and the newest takes its place. That is where the
{cancelledMain.len} cancelled runs on `main` come from. On the morning of 15 November four merges
came within half an hour, and the last of them reached the site after
{minutes(max(latencyToday))} minutes.

**Every check, twice.** A pull request is rebased on `main` before it merges (decision 0009), so
the run on `main` after the merge checks, most of the time, the very same code its pull request
just checked. Deploying the pages waits for that second run.

**Green, then waiting.** A run cannot merge its own pull request: a thread has to come back and
do it. Pull request #80 went green at {at(pr80green).format("HH:mm")} on 14 November and was
merged {pr80idle div 3600} hours later, when its thread woke again.
"""

nbText: """
## What nanuq and tabelline already do

nimaki's workflow was copied from tabelline's on the first day, and the two are still close.
nanuq, Pietro's Nim wrapper of Polars, went further when its CI reached fifteen minutes
([CI in two minutes](https://pietroppeter.github.io/nanuq/blog/2026-11-02-two-minute-ci.html)):

| Idea | nanuq | tabelline | nimaki |
| --- | --- | --- | --- |
| one program for all tests, one for all pages | yes | yes | yes (`tests/all.nim`, `docs/all.nim`) |
| links to other sites checked weekly, not on every run | | yes | yes |
| compile and run the pages as two steps, to see which is slow | | yes | yes |
| skip CI when only prose changed (path filters) | yes | | no |
| several jobs side by side, sharing what one built | yes | | no |
| optimised build of the pages (`-d:release`) | | yes | no |
| a faster linker (lld) | yes | | not needed: nimaki links no big library |

The first three rows are in nimaki already. The next three are the easy wins Pietro guessed were
missing, and the proposals below start from them; the last one does not apply.
"""

nbText: &"""
## Two measurements

Before proposing, two of the ideas were timed in the sandbox (4 cores, like a runner), on the
34 fuzzers exactly as CI runs them ({bench["cases"].getInt.thousands} cases in all), with the
script in `docs/devlog/data/ci_history/bench.sh`:

| The 34 fuzzers | seconds |
| --- | --- |
| one after another, as CI runs them today | {r0(seqDebug)} |
| one after another, built with `-d:release` | {r0(seqRelease)} |
| four at a time | {r0(parDebug)} |
| four at a time, built with `-d:release` | {r0(parRelease)} |

Both help, about as much each, and together the fuzzers take **{r0(seqDebug / parRelease)} times less
time**. Four at a time, because a fuzzer uses one core and a runner has four. And an optimised
build, because `nim r`, which CI uses, compiles without the C compiler's optimisations; the
fuzzer spends most of its time in nimaki itself, so an optimised nimaki is about three times
faster. (The JavaScript build is already compiled with `-d:release`.) `-d:release` keeps Nim's
runtime checks: an index out of range still stops the program, so the referee loses nothing. The
sandbox runs Nim 2.2.4 and CI 2.2.14; the ratios, not the seconds, are what carries over.
"""

nbText: &"""
## Proposals

Ordered by what they save for the least change. None removes a check.

1. **Check what changed.** A first step looks at the files a pull request changes. When none of
   them is code (`src/`, `tools/`, `tests/`, `corpus/`, `reference/`, `deps.lock`, `nim.cfg`,
   `config.nims`, the workflow), the referee, the fuzzers and Pele's suites are skipped; the
   pages are still built, and they still draw every diagram with nimaki and with Pele. A claim,
   a post or a roadmap update would take setup and pages: **about two minutes instead of
   {minutes(nowBuild)}**. nanuq does this with path filters.
2. **Run side by side.** Split the build job into four jobs that start together, each on its own
   machine: the referee and tests, the fuzzers, Pele's suites, the pages. Each pays its own setup
   (under a minute, from the caches), and the run takes as long as the longest, Pele's suites:
   **about {minutes(peleSuites + 60)} minutes**. Splitting the suites in two (vitest, which runs them,
   has `--shard` for that) would bring it near four.
3. **Use the four cores, and an optimised build.** Build the C tools with `-d:release`, and run
   the fuzzers four at a time, the odd-character rounds too (measured above: {r0(seqDebug)} s
   become {r0(parRelease)} s). One change in `tools/fuzz.nim` is needed first: every fuzzer writes
   its result into the same file, `docs/data/fuzz.json`, and four at once would overwrite each
   other's lines; one result file per type, or a `--types:` option that runs several in one
   process, would do.
4. **Deploy without checking twice.** On `main`, let the deploy job wait only for the pages job,
   and give each commit its own concurrency group, so merges stop queueing. The checks still run
   on `main`, beside the deploy instead of before it, and a red one still shows. A merge would
   reach the site in **about two minutes** instead of {minutes(median(latencyToday))} today.
5. **Merge on green by itself.** GitHub can merge a pull request as soon as its checks pass
   (*auto-merge*). It needs two settings that only Pietro can change: *Allow auto-merge* in the
   repository's settings, and a rule on `main` that requires the build check. Then a thread
   turns auto-merge on when it opens a pull request, and no green pull request waits for its
   thread to wake up.

With 1 to 4, a claim would be green in about two minutes, a port in about five, and a merge on
the site two minutes later.
"""

nbNote """
Which of the five should be done? They are independent: 1 is the smallest change and the largest
saving for claims and posts; 2 and 3 shorten every run of code; 4 shortens every merge; 5 needs
two settings of yours. The proposal of this thread: 1, 3 and 4 in one pull request, then 2, then
5 if you want it.
""", nkQuestion, "For Pietro"

nbText: """
## How these numbers were read

`tools/cihistory.nim` asks GitHub's API for every run of the workflow, every job of each run and
every step of each job, and reads git for the history of the workflow on `main`. It writes three
files, which this page reads: `runs.json` (one line per run, with its jobs and steps),
`workflow.json` (one entry per change of the workflow) and `lines.json` (the timed lines of the
newest green run). A time on this page is the median over the runs it names; the cancelled jobs
that never started are left out of the machine time. The two measurements were run in the
sandbox, not on GitHub's machines, which may be a little faster or slower.

```sh
nim r tools/cihistory.nim           # docs/devlog/data/ci_history/
```
"""

nbFold "Every change of the workflow on main":
  type Row = object
    date, change: string
    pr: string
    lines, fuzzers: int
  var rows: seq[Row]
  for h in history:
    rows.add Row(date: utc(h["date"].getStr).format("d MMM HH:mm"), pr: h["pr"].getStr,
                 change: h["subject"].getStr, lines: h["lines"].getInt, fuzzers: h["fuzz"].len)
  let t = tabella(rows, rownameCol = "date"):
    tabHeader "pages.yml on main", "each commit of main that changed it; lines of the file and fuzzers after the change"
    optCssTheme()
  nbTable t

nbText: """
## What this changes for the port

Nothing yet: this post only reads and measures. The roadmap step *CI, explained* is done with
it. If Pietro picks some of the proposals, they are a new step on the roadmap, with a pull
request that changes the workflow and a short post with the times before and after.

## Sources

- The runs, jobs and steps: GitHub's REST API for Actions, `actions/workflows/pages.yml/runs`
  and `actions/runs/{id}/jobs`, read on 15 November 2026 by `tools/cihistory.nim`.
- The workflow: [`.github/workflows/pages.yml`](https://github.com/pietroppeter/nimaki/blob/main/.github/workflows/pages.yml)
  and its history on `main`.
- The failures: the logs of the failed jobs, through the same API.
- GitHub's documentation on [concurrency](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs)
  (one running and one pending run per group), on
  [path filters](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onpushpull_requestpull_request_targetpathspaths-ignore)
  and on [auto-merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request).
- nanuq's [CI in two minutes](https://pietroppeter.github.io/nanuq/blog/2026-11-02-two-minute-ci.html) and its
  [workflow](https://github.com/pietroppeter/nanuq/blob/main/.github/workflows/ci.yml); tabelline's
  [workflow](https://github.com/pietroppeter/tabelline/blob/main/.github/workflows/pages.yml).
- vitest's [`--shard`](https://vitest.dev/guide/cli.html#shard).
"""

nbSave
