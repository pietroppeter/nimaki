## Checks src/nimaki/jsdate.nim against Node: the same strings through `new Date(text)`, and the
## same calendar arithmetic, run with TZ=UTC as the referee runs Pele.
import std/[os, osproc, json, random, unittest]
import ../src/nimaki/jsdate

const texts = [
  "2024-01-05", "2024-01-05T10:00", "2024-01-05T10:00:30.5Z", "2024-01-05T24:00", "2024-01-05T24:01",
  "2024-1-5", "2024/01/05", "01/05/2024", "1/5/24", "Jan 5, 2024", "5 January 2024", "January 5",
  "Jan 5", "2024", "202", "+002024-01-01", "-000000-01-01", "-002024-01-01", "2024-13-01", "2024-02-30",
  "2024-01-05 10:00", "2024-01-05 10:00 PM", "10:00 2024-01-05", "Tue, 05 Jan 2024 10:00:00 GMT",
  "Tue, 05 Jan 2024 10:00:00 GMT+0100", "2024-01-05T10:00:00+01:00", "2024-01-05T10:00:00+0100",
  "x", "", " ", "2024-01-05x", "today", "2024-01-05 (note) 10:00", "12/31/1999 23:59:59.999",
  "1999-12-31 12:00 am", "1999-12-31 12:00 pm", "13:00 pm", "2024 Jan 05", "05 2024 Jan",
  "2024-01-05T10", "2024-01-05T", "2024-01-05 T10:00", "Sept 5 2024", "Mayday 5", "5 may",
  "2024-01-05 10:00 EST", "2024-01-05 10:00 UTC-5", "2024-01-05 10:00 GMT-08:00", "2024-01-05Z",
  "99", "49", "50", "1 2 3", "1 2 3 4", "32 1 2024", "0 1 2024", "1.2.2024", "2024.01.05",
  "2024-01-05.5", "3d", "after a", "1000000", "275760-09-13", "+275760-09-13T00:00:00.001Z",
  "2024-01-05T10:00:00.123456789Z", "日本 2024", "2024 日本", "Jan 1 2024 10:00:00.5",
  "2024-01-05T10:00:00 GMT", "Thu Jan 01 1970 00:00:00", "1970-01-01T00:00:00.000-00:00",
]

proc main() =
  var r = initRand(7)
  var all: seq[string] = @texts
  let pieces = ["2024", "-", "01", "/", "5", " ", ":", "10", "Jan", "pm", "T", "Z", "+", "0100",
                "GMT", ".", "123", "(", ")", "x", "99", "31", "1999", ",", "  ", "12", "00", "UTC"]
  for i in 0 ..< 3000:
    var s = ""
    for k in 0 ..< r.rand(1 .. 7): s.add pieces[r.rand(pieces.high)]
    all.add s
  # calendar arithmetic: start points and amounts
  var arith: seq[array[2, float]]
  for i in 0 ..< 2000:
    arith.add [float(r.rand(-5_000_000 .. 5_000_000)) * 86400000.0 / 1000 + float(r.rand(0 .. 86399999)),
               float(r.rand(-400 .. 400))]
  let input = %*{"texts": all, "arith": arith}
  let script = """
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const out = { parsed: input.texts.map((t) => { const v = new Date(t).getTime(); return Number.isNaN(v) ? null : v; }),
  arith: input.arith.map(([t, n]) => {
    const d = new Date(t);
    const a = new Date(d); a.setDate(a.getDate() + n);
    const b = new Date(d); b.setMonth(b.getMonth() + n);
    const c = new Date(d); c.setFullYear(c.getFullYear() + n);
    const e = new Date(d); e.setHours(0, 0, 0, 0);
    const f = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    return [a.getTime(), b.getTime(), c.getTime(), e.getTime(), f.getTime(), d.getDay(), d.getDate(), d.getMonth(), d.getFullYear(), d.getHours()];
  }) };
process.stdout.write(JSON.stringify(out));
"""
  let dir = getTempDir() / "nimaki-test-jsdate"
  createDir dir
  writeFile dir / "check.js", script
  let (output, code) = execCmdEx("TZ=UTC node " & quoteShell(dir / "check.js"), input = $input)
  doAssert code == 0, output
  let want = parseJson(output)
  var bad = 0
  for i, t in all:
    let w = want["parsed"][i]
    let got = parseDate(t)
    let ok = if w.kind == JNull: got != got else: got == w.getFloat
    if not ok:
      inc bad
      if bad <= 20: echo "ERROR parse ", escapeJson(t), ": node ", w, ", nimaki ", got
  for i, tn in arith:
    let (t, n) = (tn[0], tn[1])
    let w = want["arith"][i]
    let d = fromTime(t)
    let got = [d.setDate(d.getDate + n), d.setMonth(d.getMonth + n), d.setFullYear(d.getFullYear + n),
               d.setHours(0, 0, 0, 0), newDate(d.getFullYear, d.getMonth + 1, 0), d.getDay, d.getDate,
               d.getMonth, d.getFullYear, d.getHours]
    for k in 0 ..< got.len:
      let wk = w[k]
      let ok = if wk.kind == JNull: got[k] != got[k] else: got[k] == wk.getFloat
      if not ok:
        inc bad
        if bad <= 20: echo "ERROR arith ", t, " ", n, " #", k, ": node ", wk, ", nimaki ", got[k]
  test "new Date(text) and calendar arithmetic as in Node (" & $all.len & " strings, " & $arith.len & " dates)":
    check bad == 0

main()
