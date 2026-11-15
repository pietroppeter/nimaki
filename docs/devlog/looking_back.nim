## devlog: 15 Nov 2026 S | Looking back | What nimaki is at 0.2.0, how three days of threads made it, what the posts, the roadmap and the decision records did for the work, what it all took, and what is left.
## kind: research
import std/[algorithm, json, math, os, sequtils, strformat, strutils, tables, times]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../pele

nbInit
nb.usePost()

# Every number of this post comes from these files: the repository's own data (docs/data/), the
# measures of this post (docs/devlog/data/looking_back/: repo.json by measure.nim, sessions.json
# from the session API, ci/ by tools/cihistory.nim, others.json from tabelline's post), and the
# sizes of the JavaScript build (docs/devlog/data/a_type_at_a_time/sizes.json).
const docs = currentSourcePath().parentDir.parentDir
const here = docs / "devlog" / "data" / "looking_back"
proc data(path: string): JsonNode = parseJson(readFile(path))

let
  repo = data(here / "repo.json")
  sessions = data(here / "sessions.json")["sessions"].getElems
  runs = data(here / "ci" / "runs.json").getElems
  others = data(here / "others.json")
  difftest = data(docs / "data" / "difftest.json")
  peleTests = data(docs / "data" / "peletests.json")
  cabi = data(docs / "data" / "cabi.json")
  install = data(docs / "data" / "installcheck.json")
  portmap = data(docs / "data" / "portmap.json")
  roadmap = data(docs / "data" / "roadmap.json")
  coverage = data(docs / "data" / "coverage.json")
  sizes = data(docs / "devlog" / "data" / "a_type_at_a_time" / "sizes.json")

proc thousands(n: int): string = insertSep($n, ',')
proc kb(n: int): string = $(int(n.float / 1000 + 0.5)) & " KB"
proc r1(x: float): string = formatFloat(x, ffDecimal, 1)
proc hours(secs: int64 | int): float = secs.float / 3600
proc utcOf(t: int64): string = fromUnix(t).utc.format("d MMM, HH:mm")
proc at(s: string): DateTime = parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())

# ---- the result ----
let
  cases = difftest["cases"].getInt + difftest["diagrammari"]["cases"].getInt
  identical = difftest["identical"].getInt + difftest["diagrammari"]["identical"].getInt
  types = difftest["types"].len
  counts = peleTests["counts"]
  conformant = portmap["totals"]["conformant"]["files"].getInt
  conformantLines = portmap["totals"]["conformant"]["code"].getInt
  peleGzip = sizes["peleBundle"]["gzip"].getInt
proc gzipOf(name: string): int =
  for f in sizes["files"]:
    if f["name"].getStr == name: return f["gzip"].getInt
  raise newException(KeyError, name)
let
  firstJs = gzipOf("release")
  allGzip = gzipOf("danger, in a function, minified")
  fourGzip = gzipOf("flowchart, sequence, pie, timeline")

# ---- the time ----
let
  first = repo["first"].getBiggestInt
  last = repo["last"].getBiggestInt
  pauseFrom = repo["pause"]["from"].getBiggestInt
  pauseTo = repo["pause"]["to"].getBiggestInt
  elapsed = hours(last - first)
  paused = hours(pauseTo - pauseFrom)
  working = elapsed - paused
  threads = sessions.filterIt(it["kind"].getStr == "thread")
  coordinators = sessions.filterIt(it["kind"].getStr == "coordinator")
  committed = hours(repo["activeSeconds"].getBiggestInt)
  repoLines = repo["lines"]

# ---- the tokens ----
proc total(xs: seq[JsonNode], key: string): float =
  for s in xs: result += s[key].getFloat
let
  tokens = total(sessions, "input") + total(sessions, "output") + total(sessions, "cacheRead") + total(sessions, "cacheWrite")
  output = total(sessions, "output")
  cost = total(sessions, "costUsd")
  threadCost = total(threads, "costUsd")
  cacheShare = total(sessions, "cacheRead") / tokens
  nanuqOut = others["nanuqOutputMillions"].getFloat
  scaledLow = others["nanuqAgentHours"][0].getFloat * output / 1e6 / nanuqOut
  scaledHigh = others["nanuqAgentHours"][1].getFloat * output / 1e6 / nanuqOut
  hoursLow = min(committed, scaledLow)
  byModel = block:
    var parts: seq[string]
    var models: seq[string]
    for x in sessions:
      if x["model"].getStr notin models: models.add x["model"].getStr
    for m in models:
      let xs = sessions.filterIt(it["model"].getStr == m)
      let tok = total(xs, "input") + total(xs, "output") + total(xs, "cacheRead") + total(xs, "cacheWrite")
      let outM = formatFloat(total(xs, "output") / 1e6, ffDecimal, 2)
      let usd = total(xs, "costUsd").round.int
      let tokB = formatFloat(tok / 1e9, ffDecimal, 2)
      parts.add &"{m} for {xs.len} sessions, {tokB} billion tokens, {outM} million of them output, ${usd}"
    parts.join("; ")
  hoursHigh = max(committed, scaledHigh)

# ---- CI ----
var runnerSecs, wallSecs = 0'i64
var ciRuns, ciGreen, ciRed = 0
for r in runs:
  inc ciRuns
  case r["conclusion"].getStr
  of "success": inc ciGreen
  of "failure": inc ciRed
  else: discard
  var firstStart, lastEnd = ""
  for j in r["jobs"]:
    let s = j["started"].getStr
    let e = j["completed"].getStr
    if s.len == 0 or e.len == 0 or e < s: continue
    runnerSecs += int64((at(e) - at(s)).inSeconds)
    if firstStart.len == 0 or s < firstStart: firstStart = s
    if e > lastEnd: lastEnd = e
  if firstStart.len > 0: wallSecs += int64((at(lastEnd) - at(firstStart)).inSeconds)

# ---- what is left ----
type Step = object
  id, status, owner, title, what: string
var steps: seq[Step]
for ph in roadmap["phases"]:
  for s in ph["steps"]:
    steps.add Step(id: s["id"].getStr, status: s["status"].getStr, owner: s{"owner"}.getStr,
                   title: s["title"].getStr, what: s["what"].getStr)
var peleLines, peleFiles = 0
for f in walkDirRec(docs.parentDir / "reference" / "pele" / "src"):
  if f.endsWith(".ts"):
    inc peleFiles
    peleLines += readFile(f).countLines
let divergences = readFile(docs / "divergences.md").splitLines.countIt(it.startsWith("### "))
let openSteps = steps.filterIt(it.status != "done" and it.id != "retrospective")
let doneSteps = steps.countIt(it.status == "done")

nbText: &"""
## The findings, first

- **nimaki 0.2.0 is out** (Pietro tagged it on 15 November, after reading this post). It draws all {types} of Pele's diagram types:
  {identical.thousands} of {cases.thousands} cases identical to Pele, byte for byte, in C and in
  JavaScript; Pele's own tests pass on it, {counts["passed"].getInt.thousands} of
  {peleTests["tests"].getInt.thousands}, none failing; it runs as a Nim library, a JavaScript file
  for the browser and a C library for other languages.
- **It took {r1(elapsed)} hours from the first commit to the last**, of which {r1(paused)} were a
  pause (Stop to Start), so about {r1(working)} hours of work, by {threads.len} threads, several at
  once, and {coordinators.len} sessions of the coordinator that talked to Pietro.
- **What it took**: {repo["commits"].getInt} commits, {repo["pullRequests"].getInt} pull requests,
  {repo["posts"].getInt} posts counting this one, {repo["decisionRecords"].getInt} decision
  records; {r1(tokens / 1e9)} billion tokens (an estimated ${cost.round.int} at list prices),
  {r1(hours(runnerSecs))} hours of CI machines, and, by our judgement, the work of 6 to 12 months of
  an experienced developer. Close to nanuq and tabelline, which were made the same way: the table
  is below.
- **What made it work** was the referee (Pele itself, run in Node, as the judge of every byte),
  and around it the framework: a step at a time, each one claimed on the roadmap first and
  told in a post, choices kept as decision records, and a Stop and Start that any thread could
  pick up from the repository alone.
- **What is left** is small, and none of it, by our reading, stands in the way of 0.2.0:
  {openSteps.len} roadmap steps that stay open by design (two of them recurring articles), a handful of
  Pele's stress tests that are slow in the JavaScript build, {divergences} wanted differences, and things
  only Pietro can do (the proposals to diagrammari and nim-regex). The list is in
  [What is left](#what-is-left).
"""

nbText: &"""
## What nimaki is, at 0.2.0

nimaki is a port of [Pele](https://github.com/obsidianmd/pele), the Mermaid renderer that
Obsidian built, from TypeScript to Nim. Mermaid is a way to write a diagram as text (a flowchart,
a sequence of messages, a gantt chart); a *renderer* turns that text into a drawing, an SVG file.
The port's rule from the first day was that Pele is the specification: nimaki is right when its
drawing is the same, byte for byte, as the one Pele makes of the same text. Here is a flowchart,
drawn by nimaki while this page was built, and compared with Pele's on the way:
"""

nbMermaid """flowchart LR
  T[Mermaid text] --> N[nimaki]
  T --> P[Pele in Node]
  N --> C{same bytes?}
  P --> C
  C -->|yes| D[done]
  C -->|no| F[fix nimaki]""", "The referee, which checked every step of the port", %*{"maxWidth": 390}

nbText: &"""
| | at 0.2.0 |
| --- | --- |
| diagram types | {types} of {types} |
| cases identical to Pele (Pele's corpus and diagrammari's) | {identical.thousands} of {cases.thousands} |
| Pele's own tests passing on the JavaScript build | {counts["passed"].getInt.thousands} of {peleTests["tests"].getInt.thousands}, {counts["failed"].getInt} failing |
| ported files, all conformant | {conformant} files, {conformantLines.thousands} lines of code |
| installed with nimble, drawn outside the repository | {install["identical"].getInt.thousands} of {install["cases"].getInt.thousands} identical |
| through the C library, from Python | {cabi["identical"].getInt.thousands} of {cabi["cases"].getInt.thousands} identical |
| nimaki.js, every type, compressed | {allGzip.kb} (before the step that shrank it: {firstJs.kb}; Pele's bundle: {peleGzip.kb}) |
| nimaki.js, the four types diagrammari writes | {fourGzip.kb} |

The release itself is told in [nimaki 0.2.0](../nimaki-0-2-0/), and the shrinking of the
JavaScript file, the last thing it waited for, in [A type at a time](../a-type-at-a-time/).
"""

nbText: &"""
## How it got there

The posts tell the story one step at a time, in order; here it is from far away.
"""

block:
  var perDay = initOrderedTable[string, int]()
  for f in walkFiles(docs / "devlog" / "*.nim"):
    let line = readFile(f).splitLines[0]
    if not line.startsWith("## devlog: "): continue
    let day = line["## devlog: ".len .. ^1].split(" 2026")[0]
    perDay.mgetOrPut(day, 0).inc
  var days = toSeq(perDay.keys)
  days.sort(proc (a, b: string): int = cmp(parseInt(a.split(' ')[0]), parseInt(b.split(' ')[0])))
  let labels = days.mapIt("\"" & it & "\"").join(", ")
  let values = days.mapIt($perDay[it]).join(", ")
  nbMermaid &"""xychart-beta
  title "Posts a day"
  x-axis [{labels}]
  y-axis "posts" 0 --> {max(toSeq(perDay.values)) + 5}
  bar [{values}]""", "The posts of the devlog, by the day they are dated", %*{"maxWidth": 390}

nbText: &"""
- **12 November, evening (UTC)**: the stage. Four threads at once set up the repository and its
  rules ([A stage for a port](../a-stage-for-a-port/)), the referee ([The referee](../the-referee/)),
  the look ([Pomice](../pomice/)) and the research on Pele and Mermaid. The same evening the
  first drawings were identical ([First light](../first-light/)), and the port went on into the
  night: the layered layout and flowchart, sequence, class and state diagrams, and more.
- **13 November, until {utcOf(pauseFrom)} UTC**: more types, the JavaScript build and the browser
  playground, a C library. Then Pietro said Stop, and the repository was quiet for
  {r1(paused)} hours.
- **14 November**: Start, at {utcOf(pauseTo)} UTC, with every thread given a new part. The last
  types (charts, venn), Pele's own test suites run on nimaki, the models (`parse`), a regular
  expression engine, and the first rounds of making the JavaScript build fast enough.
- **15 November**: a stock-take, 0.1.0, the CI made faster, the browser side of Pele,
  the JavaScript file cut by half and split by type, and 0.2.0, prepared.

The threads, each told by what it did: the posts it wrote, in order. A thread took a new title with each new step, so its last title says little about the busiest ones (Pietro's review, 15 November: the first version of this table showed those titles, and no history of them is kept).
"""

block:
  type Row = object
    started, did, commits, work, output, cost: string
  var titleOf = initTable[string, string]()
  for f in walkFiles(docs / "devlog" / "*.nim"):
    let line = readFile(f).splitLines[0]
    if line.startsWith("## devlog: "): titleOf[f.extractFilename.changeFileExt("")] = line.split(" | ")[1].strip
  var rows: seq[Row]
  let byId = repo["sessions"]
  var sorted = threads
  sorted.sort(proc (a, b: JsonNode): int = cmp(a["created"].getStr, b["created"].getStr))
  for s in sorted:
    let id = s["id"].getStr
    let c = byId{id}
    var did: seq[string]
    if not c.isNil:
      for p in c["posts"]: did.add titleOf.getOrDefault(p.getStr, p.getStr)
    rows.add Row(started: at(s["created"].getStr).format("d MMM HH:mm"),
                 did: (if did.len == 0: "(no post)" else: did.join(" · ")),
                 commits: (if c.isNil: "0" else: $c["commits"].getInt),
                 work: (if c.isNil: "0" else: r1(hours(c["activeSeconds"].getBiggestInt))),
                 output: r1(s["output"].getFloat / 1e6),
                 cost: "$" & $s["costUsd"].getFloat.round.int)
  let t = tabella(rows, rownameCol = "started"):
    tabHeader "The threads", "started (UTC); the posts it wrote, in order; commits on main; hours between commits less than 45 minutes apart; output tokens in millions; estimated cost at list prices"
    colsLabel:
      did: "what it did"
      commits: "commits"
      work: "hours"
      output: "output"
      cost: "cost"
    optCssTheme()
  nbFold "The threads, one row each":
    nbTable t

nbText: &"""
## What the framework did

nimaki copied its way of working from [gleam-in-nim](https://github.com/pietroppeter/gleam-in-nim),
and that way had been tried on tabelline and nanuq first. Looking back, each piece earned its
place, and each had a cost.

- **The referee** did the most. Because Pele, run in Node, judged every drawing, a thread never
  had to argue that a port was right: it was, or a byte was different. It turned a vague job
  ("port a renderer") into thousands of small yes-or-no questions, which is what lets agents work
  on their own for hours. The fuzzers and Pele's own tests extended the same idea to inputs no
  one wrote by hand.
- **A step at a time, claimed first.** The roadmap has {steps.len} steps, {doneSteps} done. A
  thread claimed a step in a small pull request before starting ({repo["claims"].getInt} commits
  say "claim"), so no two threads ever did the same work. The cost: `roadmap.json` was changed
  in {repo["roadmapCommits"].getInt} commits, and a branch had to take in `main` before merging
  {repo["merges"].getInt - repo["pullRequestMerges"].getInt} times, often for a line of the roadmap.
- **A post for every step.** {repo["posts"].getInt} posts, each readable on a phone, are how
  Pietro followed the work and steered it: his reviews of a post became fixes, and his answers to
  a post's questions became decisions (decision 0021 now makes each post show the answer). They
  also made each thread explain what it did, which caught mistakes before they were merged. The
  cost is time: a post often took as long as its step.
- **Decision records.** {repo["decisionRecords"].getInt} records hold the choices a later thread could
  have made differently (Nim's version, the regular expressions, how releases are made). A thread
  that started on a part read them first, so a choice made on the first day still held on the
  last.
- **Start and Stop, and the repository as memory.** The pause of {r1(paused)} hours lost nothing:
  each thread wrote where it stood, and on Start each one went on from the roadmap and its draft
  pull request. This post was itself paused and picked up the same way.
- **What did not work as well**: the devlog letters (two posts of a day may not share one)
  collided several times between threads writing at once; CI was slow for a while, and threads
  waited for it ([Twelve minutes of checks](../twelve-minutes-of-checks/), then
  [A faster CI](../a-faster-ci/));
  and the JavaScript build was large and slow until late, because no step measured its size
  before the release asked for it.
"""

nbText: &"""
## What it took

How much work is a port made by agents? We measured it as tabelline did for its 0.2
([its post](https://pietroppeter.github.io/tabelline/devlog/designing-0-2/)), with the same
sources, so the three projects compare. Each column is from the first commit to the release.
"""

block:
  type E = object
    measure, nimaki, nanuq, tabelline: string
  let n = others["projects"][0]
  let tb = others["projects"][1]
  let lines = repo["lines"]
  var allLines = 0
  for k, v in lines: allLines += v.getInt
  let rows = @[
    E(measure: "days", nimaki: r1(elapsed / 24) & " (" & r1(working / 24) & " without the pause)", nanuq: n["days"].getStr, tabelline: tb["days"].getStr),
    E(measure: "pull requests", nimaki: $repo["pullRequests"].getInt, nanuq: n["pullRequests"].getStr, tabelline: tb["pullRequests"].getStr),
    E(measure: "threads", nimaki: $threads.len, nanuq: n["threads"].getStr, tabelline: tb["threads"].getStr),
    E(measure: "token cost", nimaki: "$" & $cost.round.int, nanuq: n["cost"].getStr, tabelline: tb["cost"].getStr),
    E(measure: "tokens (billions)", nimaki: formatFloat(tokens / 1e9, ffDecimal, 2), nanuq: n["tokens"].getStr, tabelline: tb["tokens"].getStr),
    E(measure: "output (millions)", nimaki: r1(output / 1e6), nanuq: n["output"].getStr, tabelline: tb["output"].getStr),
    E(measure: "agent hours", nimaki: $hoursLow.round.int & "–" & $hoursHigh.round.int, nanuq: n["agentHours"].getStr, tabelline: tb["agentHours"].getStr),
    E(measure: "CI hours", nimaki: r1(hours(runnerSecs)), nanuq: n["ciHours"].getStr, tabelline: tb["ciHours"].getStr),
    E(measure: "lines (thousands)", nimaki: r1(allLines.float / 1000), nanuq: n["lines"].getStr, tabelline: tb["lines"].getStr),
    E(measure: "developer months", nimaki: "6–12", nanuq: n["devMonths"].getStr, tabelline: tb["devMonths"].getStr),
  ]
  let t = tabella(rows, rownameCol = "measure"):
    tabHeader "What it took", "nimaki to 0.2.0; nanuq to 0.6 and tabelline to 0.2, from tabelline's post"
    colsLabel:
      nimaki: "nimaki"
      nanuq: "nanuq"
      tabelline: "tabelline"
    optCssTheme()
  nbTable t

nbText: &"""
Where the numbers come from, and how sure they are:

- **Days** are from the first commit ({utcOf(first)} UTC) to the last one measured
  ({utcOf(last)} UTC). The pause is the longest stretch without a commit.
- **Tokens and token cost** are measured: the usage the Claude Code session API reports for each
  of the {threads.len} threads that made commits (each commit names its session) and the
  {coordinators.len} sessions of the coordinator, read on 15 November; the cost is the API's own
  figure at list prices, a measure of size and not a bill. {int(cacheShare * 100 + 0.5)}% of the
  tokens are *cache reads*: the same long context read again at each turn, which is cheap. The
  threads alone cost ${threadCost.round.int}. This thread was still running when it was read,
  so its last hour is missing.
- **By model**: {byModel}. The threads ran on one model and the coordinator on
  another; the session records name each session's model and the one that served its last turn,
  so a turn that fell back to another model in between is not seen here.
- **Agent hours** are a range, as tabelline's: one end sums the time between each thread's
  commits when they are less than 45 minutes apart ({r1(committed)} hours: it misses the work
  before a first commit and between far-apart ones), the other scales nanuq's hours by the output
  tokens ({scaledLow.round.int} to {scaledHigh.round.int}).
- **CI hours** add up the time of every job of every run of the workflow, from GitHub's Actions
  API ({ciRuns} runs, {ciGreen} green, {ciRed} red, the rest cancelled or skipped); counted run by
  run, from the first job's start to the last job's end, it is {r1(hours(wallSecs))} hours.
- **Lines** are counted in the files of `main` by kind: the port {repoLines["port"].getInt.thousands},
  tests {repoLines["tests"].getInt.thousands}, tools {repoLines["tools"].getInt.thousands}, the posts
  {repoLines["posts"].getInt.thousands}, the other pages {repoLines["pages"].getInt.thousands}, decision
  records {repoLines["decisions"].getInt.thousands} and other Markdown {repoLines["markdown"].getInt.thousands}.
  Generated files (the corpus, the data) are not counted.
- **Developer months** are a judgement, as for nanuq and tabelline: the time one experienced
  developer who knows Nim and TypeScript, but not Pele, would need. Pele's source is
  {peleLines.thousands} lines of TypeScript in {peleFiles} files; porting it so that every drawing is the same byte for byte
  (down to how JavaScript rounds a sine, which needed a port of fdlibm) is slow, careful work; on
  top of that come the referee, the fuzzers, a regular expression engine that behaves as
  JavaScript's, a JavaScript build that is small and fast, a C library, and some seventy posts.
  We think 6 to 12 months; it could be more.

In all, nimaki took about what nanuq and tabelline took, in less than half their days.
"""

nbText: """
## What is left

Written for Pietro, to decide whether 0.2.0 could go out (it did). By our reading, nothing here blocked it: each item
is known, written down where a later thread will find it, and none changes a drawing.

**Things only Pietro can do**

- **Tag 0.2.0.** Done on 15 November, from the commit that merged this post
  ([nimaki 0.2.0](../nimaki-0-2-0/),
  [the release](https://github.com/pietroppeter/nimaki/releases/tag/v0.2.0)); its workflow then
  attached the JavaScript files, each type's and a zip of all (decision 0023).
- **Propose nimaki to diagrammari.** The [proposal](../a-proposal-for-diagrammari/) lists what
  diagrammari needed; every item is now done. Changing diagrammari is Pietro's, not ours.
- **Send the proposal to nim-regex**, if he wants to:
  [A proposal for nim-regex](../a-proposal-for-nim-regex/). Nothing here depends on it.

**Open on the roadmap, by design**
"""

block:
  var md = ""
  for s in openSteps:
    let first = s.what.split(". ")[0]
    let who = if s.owner.len > 0: ", " & s.owner else: ""
    md.add &"- **{s.title}** ({s.status}{who}): {first}.\n"
  nbText: md

nbText: &"""
**Known and written down**

- **{counts["speed"].getInt} of Pele's stress tests** draw the same but miss one of Pele's time
  bounds in the JavaScript build when four test files run at once; each passes alone (the step
  above, and the porting guide's note on code that JavaScript runs slowly).
- **{counts["known"].getInt} of Pele's tests are listed as known** in `tools/peletests/known.txt`,
  each with its reason: most are stress tests that run out of memory in the JavaScript
  build (thousands of levels of nesting), the others send text that is not valid Unicode, which
  is one of the wanted differences.
- **{divergences} wanted differences** from Pele, on the [Decisions](../../decisions/) page: text that is
  not UTF-8, half of an emoji, and captures inside a repeated group of a regular expression.
- **CI**: Pele's suites, split in two, are still the longest part of a run; balancing the halves on
  nimaki's times rather than Pele's could make it shorter
  ([Two machines for Pele's suites](../two-machines-for-peles-suites/)).

**When to pick it up again**

- When Pele releases past {difftest["pin"].getStr}: the weekly CI run turns red, and
  `nim r tools/followpele.nim` lists the files the release touches and their ports.
- When diagrammari takes nimaki in, and asks for something.
- To resume: say Start, and each open step's thread (or a new one) runs `sh tools/setup.sh`,
  reads the roadmap and goes on.
"""

nbText: """
## What this changes for the port

- The automatic work stops here, after 0.2.0. The roadmap, the coverage map, the decision
  records and this post are where a later thread starts.
- The open steps keep their owners; a new thread may take one over by claiming it again.

## Sources

- The repository's history: `docs/devlog/data/looking_back/measure.nim` writes `repo.json`
  (commits, the sessions in their `Claude-Session` lines, pull requests from GitHub's API, lines).
- The sessions' usage: `docs/devlog/data/looking_back/sessions.json`, from the Claude Code
  session API, read on 15 November 2026.
- CI: `tools/cihistory.nim`, into `docs/devlog/data/looking_back/ci/`.
- nanuq and tabelline: `docs/devlog/data/looking_back/others.json`, from tabelline's post
  [Designing 0.2](https://pietroppeter.github.io/tabelline/devlog/designing-0-2/).
- The result: `docs/data/` (difftest, peletests, cabi, installcheck, portmap) and
  [A type at a time](../a-type-at-a-time/) for the sizes.
"""

nbSave
