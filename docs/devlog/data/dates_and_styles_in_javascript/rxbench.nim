## Throughput of the regex library through nimaki's wrapper, in C and in JavaScript (post 14 Nov Q):
##   nim r -d:release docs/devlog/data/dates_and_styles_in_javascript/rxbench.nim
##   nim js -d:nodejs -d:release -o:rxbench.js docs/devlog/data/dates_and_styles_in_javascript/rxbench.nim && node rxbench.js
import std/[monotimes, times, strutils]
import nimaki/jsregex

template timeIt(label: string, reps: int, body: untyped) =
  let t0 = getMonoTime()
  for _ in 1 .. reps: body
  let ms = (getMonoTime() - t0).inMicroseconds.float / 1000 / reps.float
  echo label.alignLeft(46), formatFloat(ms, ffDecimal, 2), " ms"

let lines = block:
  var s = ""
  for i in 0 ..< 4000: s.add "key" & $i & " : some value number " & $i & "\n"
  s
echo "text: ", lines.len, " bytes, 4000 lines"
const WithGroups = jsre"/(\w+)[ \t]*:[ \t]*([^\n]*)/g"
const NoGroups = jsre"/\w+[ \t]*:[ \t]*[^\n]*/g"
const Sticky = jsre"/[ \t]*:[ \t]*/y"
const Word = jsre"/\w+/y"
timeIt("g walk, 2 groups (matchAll)", 3): discard lines.matchAll(WithGroups)
timeIt("g walk, no groups (matchAll)", 3): discard lines.matchAll(NoGroups)
timeIt("g walk, 2 groups, text only (match)", 3): discard lines.match(WithGroups)
timeIt("sticky lexer: exec at each token", 3):
  var at = 0
  var n = 0
  while at < lines.len:
    let e = Word.matchEnd(lines, at)
    if e > at: at = e; inc n; continue
    let e2 = Sticky.matchEnd(lines, at)
    if e2 > at: at = e2; continue
    inc at
