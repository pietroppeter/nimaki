## bench: how long nimaki takes to draw the corpus, per diagram type. Build it with -d:release
## (the numbers of a debug build say little):
##
##   nim c -d:release -o:build/bench tools/bench.nim && build/bench
##   build/bench pie flowchart          only these types
##   options:
##     --rounds:N    draw every case N times (default 5) and keep the fastest round of each type
##
## It prints one line per type (cases, and the fastest round in milliseconds) and the total last.
## The post on regular expressions compares two builds with it.
import std/[os, strutils, json, tables, parseopt, monotimes, times, algorithm, sequtils]
import common
import nimaki

proc main() =
  var rounds = 5
  var only: seq[string]
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "rounds": rounds = parseInt(val)
      else: quit "ERROR unknown option --" & key, 2
    of cmdArgument: only.add key
    of cmdEnd: discard
  var byType: OrderedTable[string, seq[string]]
  for c in parseFile(repoDir / "corpus" / "cases.json")["cases"]:
    let t = c["type"].getStr
    if only.len > 0 and t notin only: continue
    byType.mgetOrPut(t, @[]).add c["source"].getStr
  var names = toSeq(byType.keys)
  names.sort()
  var total = 0.0
  var drawn = 0
  for t in names:
    var best = Inf
    for r in 0 ..< rounds:
      let start = getMonoTime()
      for source in byType[t]:
        try: discard render(source, RenderOptions(now: some(1_700_000_000_000.0)))
        except CatchableError: discard
      best = min(best, (getMonoTime() - start).inNanoseconds.float / 1e6)
    total += best
    drawn += byType[t].len
    echo "  ", t.alignLeft(14), ($byType[t].len).align(5), " cases ", formatFloat(best, ffDecimal, 1).align(9), " ms"
  echo "bench: ", drawn, " cases of ", names.len, " types, fastest of ", rounds, " rounds: ",
    formatFloat(total, ffDecimal, 1), " ms"

main()
