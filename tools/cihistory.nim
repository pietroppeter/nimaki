## cihistory: the history of nimaki's CI, read from GitHub Actions and from git.
##
## CI is one workflow, `.github/workflows/pages.yml`. This tool keeps a record of its runs that
## a page can read without asking GitHub again:
##
## - every run of the workflow (`runs.json`): when it was created, started and finished, what
##   started it (a push to main, a pull request, the weekly schedule, by hand), how it ended,
##   and, for each job, every step with its duration in seconds;
## - every commit that changed the workflow (`workflow.json`): its date, subject, pull request,
##   and the names of the workflow's steps after it;
## - the timed lines of the newest green pull-request run (`lines.json`): each fuzzer, each
##   odd-character seed and Pele's suites print one summary line, and the log stamps each line,
##   so the time between two lines is what one of them took.
##
## It asks the GitHub REST API through `curl` (so a proxy in `HTTPS_PROXY` works, and
## `GITHUB_TOKEN`, when set, raises the rate limit), and it reads git for the workflow's history.
## The API is read only; nothing on GitHub changes.
##
##   nim r tools/cihistory.nim                       # docs/devlog/data/ci_history/
##   nim r tools/cihistory.nim --out:build/ci        # somewhere else
##   nim r tools/cihistory.nim --fast:20             # only the 20 newest runs, to try it
##
## A run that is still going is recorded as it stands; rerun the tool to see it finish.
import std/[os, osproc, strutils, json, times, parseopt, algorithm, sequtils]

const
  repo = "pietroppeter/nimaki"
  workflow = "pages.yml"
  workflowPath = ".github/workflows/" & workflow

proc curlJson(url: string): JsonNode =
  var args = @["-sS", "--fail-with-body", "--retry", "4", "-H",
               "Accept: application/vnd.github+json"]
  let token = getEnv("GITHUB_TOKEN")
  if token.len > 0 and not token.startsWith("placeholder"):
    args.add ["-H", "Authorization: Bearer " & token]
  args.add url
  let (output, code) = execCmdEx("curl " & args.mapIt(quoteShell(it)).join(" "))
  if code != 0:
    quit "ERROR curl " & url & " failed:\n" & output.strip, 2
  parseJson(output)

proc stamp(node: JsonNode): string =
  if node.isNil or node.kind != JString: "" else: node.getStr

proc seconds(a, b: string): int =
  ## The seconds from time a to time b (ISO 8601, as GitHub writes them), -1 if one is missing.
  if a.len == 0 or b.len == 0: return -1
  let fmt = "yyyy-MM-dd'T'HH:mm:ss'Z'"
  int((parse(b, fmt, utc()) - parse(a, fmt, utc())).inSeconds)

proc runsOf(fast: int): seq[JsonNode] =
  var page = 1
  while true:
    let url = "https://api.github.com/repos/" & repo & "/actions/workflows/" & workflow &
              "/runs?per_page=100&page=" & $page
    let batch = curlJson(url)["workflow_runs"]
    if batch.len == 0: break
    for r in batch: result.add r
    if fast > 0 and result.len >= fast:
      result.setLen fast
      break
    inc page

proc jobsOf(runId: int): JsonNode =
  ## Every job of a run, with every attempt (a run started again keeps its first attempt's jobs).
  result = newJArray()
  var page = 1
  while true:
    let url = "https://api.github.com/repos/" & repo & "/actions/runs/" & $runId &
              "/jobs?filter=all&per_page=100&page=" & $page
    let batch = curlJson(url)["jobs"]
    for j in batch:
      var steps = newJArray()
      for s in j{"steps"}.getElems:
        steps.add %*[s["name"].getStr, s{"conclusion"}.stamp,
                     seconds(s{"started_at"}.stamp, s{"completed_at"}.stamp)]
      result.add %*{
        "name": j["name"].getStr,
        "attempt": j{"run_attempt"}.getInt(1),
        "conclusion": j{"conclusion"}.stamp,
        "created": j{"created_at"}.stamp,
        "started": j{"started_at"}.stamp,
        "completed": j{"completed_at"}.stamp,
        "runner": j{"runner_name"}.stamp,
        "steps": steps}
    if batch.len < 100: break
    inc page

proc prOf(subject: string): string =
  ## The pull request a commit came from: "Merge pull request #12 from ..." or "Title (#12)".
  if subject.startsWith("Merge pull request #"):
    return subject["Merge pull request #".len .. ^1].split(' ')[0]
  let open = subject.rfind("(#")
  if open >= 0 and subject.endsWith(")"):
    return subject[open + 2 .. ^2]
  ""

proc stepNames(yml: string): seq[string] =
  ## The steps of the workflow's build job: `- name:` lines, and `- uses:` / `- run:` lines
  ## without a name, as GitHub names them.
  var inBuild = false
  var lines = yml.splitLines
  for i, line in lines:
    if line.startsWith("  build:"): inBuild = true
    elif line.len > 2 and line[0] == ' ' and line[1] == ' ' and line[2] != ' ' and
         line.strip.endsWith(":") and not line.startsWith("  build:"):
      inBuild = false
    if not inBuild: continue
    let s = line.strip
    if s.startsWith("- name:"): result.add s["- name:".len .. ^1].strip
    elif s.startsWith("- uses:"):
      result.add "uses " & s["- uses:".len .. ^1].strip.split('@')[0]
    elif s.startsWith("- run:"):
      result.add "run " & s["- run:".len .. ^1].strip

proc workflowHistory(): JsonNode =
  ## The workflow as main saw it: one entry per commit of main's first-parent line that changed
  ## it (a merged pull request, mostly), with the build steps added and removed by that change
  ## and the fuzz lines (`nim r tools/fuzz.nim <type>`) after it.
  result = newJArray()
  if execProcess("git rev-parse --is-shallow-repository").strip == "true":
    quit "ERROR the checkout is shallow: git fetch --unshallow origin main", 2
  let log = execProcess("git log --first-parent --reverse --format=%H%x09%cI%x09%s -- " &
                        workflowPath)
  var before: seq[string]
  for line in log.strip.splitLines:
    let parts = line.split('\t', 2)
    if parts.len < 3: continue
    let yml = execProcess("git show " & parts[0] & ":" & workflowPath)
    let steps = stepNames(yml)
    let fuzzed = yml.splitLines.filterIt("tools/fuzz.nim " in it).mapIt(
      it.split("tools/fuzz.nim ")[1].split(' ')[0])
    # a merge commit's subject names the branch; the pull request's title is its body's first line
    var subject = parts[2]
    if subject.startsWith("Merge pull request #"):
      let body = execProcess("git log -1 --format=%b " & parts[0]).strip
      if body.len > 0: subject = body.splitLines[0]
    result.add %*{"commit": parts[0][0 .. 6], "date": parts[1], "subject": subject,
                  "pr": prOf(parts[2]), "lines": yml.countLines,
                  "added": steps.filterIt(it notin before),
                  "removed": before.filterIt(it notin steps),
                  "steps": steps, "fuzz": fuzzed}
    before = steps

proc curlText(url: string): string =
  let (output, code) = execCmdEx("curl -sSL --retry 4 " & quoteShell(url))
  if code != 0: quit "ERROR curl " & url & " failed", 2
  output

proc timedLines(runs: JsonNode): JsonNode =
  ## The summary lines of the newest green pull-request run's build job, with their times.
  result = %*{"run": 0, "lines": []}
  for i in countdown(runs.len - 1, 0):
    let r = runs[i]
    if r["event"].getStr != "pull_request" or r["conclusion"].getStr != "success": continue
    let jobs = curlJson("https://api.github.com/repos/" & repo & "/actions/runs/" &
                        $r["id"].getInt & "/jobs")["jobs"]
    for j in jobs:
      if j["name"].getStr != "build": continue
      let log = curlText("https://api.github.com/repos/" & repo & "/actions/jobs/" &
                         $j["id"].getInt & "/logs")
      result["run"] = %r["number"].getInt
      for line in log.splitLines:
        if line.len < 30: continue
        let text = line[29 .. ^1]
        if text.startsWith("##[group]Run ") or text.startsWith("fuzz: ") or
           text.startsWith("mutate") or text.startsWith("peletests: ") or
           text.startsWith("difftest") or text.startsWith("cabi"):
          result["lines"].add %*[line[0 .. 18] & "Z", text]
      return

proc main() =
  var outDir = "docs/devlog/data/ci_history"
  var fast = 0
  for kind, key, val in getopt():
    case key
    of "out": outDir = val
    of "fast": fast = parseInt(val)
    else: quit "ERROR unknown option " & key, 2
  createDir outDir

  let wf = workflowHistory()
  writeFile(outDir / "workflow.json", pretty(wf))
  echo "workflow: ", wf.len, " commits changed ", workflowPath

  let runs = runsOf(fast)
  var record = newJArray()
  var failed, cancelled = 0
  for i, r in runs:
    let id = r["id"].getInt
    let title = r{"display_title"}.stamp
    record.add %*{
      "id": id,
      "number": r["run_number"].getInt,
      "attempt": r{"run_attempt"}.getInt(1),
      "event": r["event"].getStr,
      "branch": r{"head_branch"}.stamp,
      "sha": r["head_sha"].getStr[0 .. 6],
      "title": (if title.len > 90: title[0 ..< 90] else: title),
      "status": r["status"].getStr,
      "conclusion": r{"conclusion"}.stamp,
      "created": r{"created_at"}.stamp,
      "started": r{"run_started_at"}.stamp,
      "updated": r{"updated_at"}.stamp,
      "jobs": jobsOf(id)}
    case r{"conclusion"}.stamp
    of "failure": inc failed
    of "cancelled": inc cancelled
    else: discard
    if (i + 1) mod 50 == 0: echo "runs: ", i + 1, " of ", runs.len
  record.elems.sort(proc (a, b: JsonNode): int = cmp(a["number"].getInt, b["number"].getInt))
  writeFile(outDir / "runs.json", $record)
  writeFile(outDir / "lines.json", pretty(timedLines(record)))
  echo "summary: ", record.len, " runs (", failed, " failed, ", cancelled, " cancelled) in ",
       outDir / "runs.json"

main()
