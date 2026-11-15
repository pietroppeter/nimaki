## Measures the repository for the post Looking back (15 Nov 2026 P): commits, the sessions that
## made them, the time each session was at work, pull requests, and lines by kind of file.
##
##   nim r docs/devlog/data/looking_back/measure.nim     (from the repository's root, full history)
##
## Writes docs/devlog/data/looking_back/repo.json. The pull requests come from GitHub's API
## (curl, as tools/cihistory.nim does); everything else from git.
import std/[algorithm, json, os, osproc, sequtils, strutils, tables, times]

const outPath = "docs/devlog/data/looking_back/repo.json"
const gapMinutes = 45   ## commits of one session closer than this count as one stretch of work

proc run(cmd: string): string =
  let (o, code) = execCmdEx(cmd)
  if code != 0: quit "ERROR " & cmd & "\n" & o, 2
  o

proc main() =
  if run("git rev-parse --is-shallow-repository").strip == "true":
    quit "ERROR shallow checkout: git fetch --unshallow origin main first", 2
  let head = run("git rev-parse origin/main").strip

  # Every commit of main: time, whether it is a merge, the session in its trailer.
  type C = object
    t: int64
    merge: bool
    session: string
    subject: string
  var commits: seq[C]
  let log = run("git log origin/main --format=%H%x1f%ct%x1f%P%x1f%B%x1e")
  for rec in log.split('\x1e'):
    let f = rec.strip(chars = {'\n'}).split('\x1f')
    if f.len < 4: continue
    var s = ""
    let i = f[3].find("session_")
    if i >= 0:
      var j = i
      while j < f[3].len and f[3][j] in {'A'..'Z', 'a'..'z', '0'..'9', '_'}: inc j
      s = f[3][i ..< j]
    commits.add C(t: parseBiggestInt(f[1]), merge: f[2].splitWhitespace.len > 1, session: s,
                   subject: f[3].strip.splitLines[0])
  commits.sort(proc (a, b: C): int = cmp(a.t, b.t))

  # The longest quiet stretch of the repository: the pause between Stop and Start.
  var pauseFrom, pauseTo = 0'i64
  for i in 1 ..< commits.len:
    if commits[i].t - commits[i - 1].t > pauseTo - pauseFrom:
      pauseFrom = commits[i - 1].t
      pauseTo = commits[i].t

  # Each session: its commits, and its time at work (stretches of commits less than gapMinutes apart).
  var bySession = initOrderedTable[string, seq[int64]]()
  for c in commits:
    if c.session.len > 0 and not c.merge: bySession.mgetOrPut(c.session, @[]).add c.t
  var sessions = newJObject()
  var activeTotal = 0'i64
  for s, ts in bySession:
    var active = 0'i64
    for i in 1 ..< ts.len:
      let d = ts[i] - ts[i - 1]
      if d <= gapMinutes * 60: active += d
    activeTotal += active
    sessions[s] = %*{"commits": ts.len, "first": ts[0], "last": ts[^1], "activeSeconds": active}

  # Lines by kind of file, at main's head.
  proc lines(spec: string, ext = ".nim"): int =
    for f in run("git ls-files " & spec).splitLines:
      if f.endsWith(ext) and fileExists(f): result += readFile(f).countLines
  let kinds = %*{
    "port": lines("src"), "tests": lines("tests"), "tools": lines("tools"),
    "posts": lines("docs/devlog"), "pages": lines("docs") - lines("docs/devlog"),
    "decisions": lines("docs/decisions", ".md"), "markdown": lines("'*.md'", ".md")}

  # Pull requests, from GitHub's API.
  var prs, merged = 0
  for page in 1 .. 10:
    let j = parseJson(run("curl -sS 'https://api.github.com/repos/pietroppeter/nimaki/pulls?state=all&per_page=100&page=" &
                          $page & "'"))
    if j.len == 0: break
    for p in j:
      inc prs
      if p["merged_at"].kind == JString: inc merged

  let data = %*{
    "about": "Written by docs/devlog/data/looking_back/measure.nim. Do not edit by hand.",
    "head": head, "measured": now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "commits": commits.len, "merges": commits.countIt(it.merge),
    "pullRequestMerges": commits.countIt(it.merge and it.subject.startsWith("Merge pull request")),
    "claims": commits.countIt(not it.merge and "claim" in it.subject.toLowerAscii),
    "roadmapCommits": run("git log origin/main --no-merges --format=%H -- docs/data/roadmap.json").splitLines.len,
    "first": commits[0].t, "last": commits[^1].t,
    "pause": {"from": pauseFrom, "to": pauseTo},
    "gapMinutes": gapMinutes, "activeSeconds": activeTotal, "sessions": sessions,
    "lines": kinds, "pullRequests": prs, "merged": merged,
    "posts": toSeq(walkFiles("docs/devlog/*.nim")).filterIt(not it.endsWith("index.nim")).len,
    "decisionRecords": toSeq(walkFiles("docs/decisions/0*.md")).len}
  writeFile outPath, data.pretty & "\n"
  echo "measure: ", commits.len, " commits, ", bySession.len, " sessions, ", prs, " pull requests; ", outPath

main()
