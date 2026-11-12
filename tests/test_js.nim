## JavaScript's numbers and strings in Nim (src/nimaki/js.nim), checked against Node itself on
## a seeded sample: String(x), x.toFixed(n), Math.round(x), and the UTF-16 length.
import std/[unittest, random, osproc, strutils, os, math, json, algorithm]
import nimaki/js

proc sample(): seq[float] =
  var rng = initRand(7)
  result = @[0.0, -0.0, 0.5, 1.5, 2.5, -2.5, -0.5, 12.5, 0.125, 1e21, 1e-7, 1e-6, 123456789012345680000.0,
             5e-324, 1.7976931348623157e308, 0.1 + 0.2, 42.96, 1.005, 2.675, 79.37106918238993,
             99.5, 0.05, 1e20, 999999999999999.9, 4.35, 100.0 / 3]
  for i in 0 ..< 4000:
    let kind = rng.rand(3)
    case kind
    of 0: result.add rng.rand(-1000.0 .. 1000.0)
    of 1: result.add float(rng.rand(-100000 .. 100000)) / 100 + 0.005
    of 2: result.add pow(10.0, rng.rand(-30.0 .. 30.0)) * (if rng.rand(1) == 0: 1 else: -1)
    else: result.add float(rng.rand(0 .. 200)) / 8

suite "js numbers, against Node":
  let xs = sample()
  let dir = getTempDir() / "nimaki-test-js"
  createDir dir
  var input = ""
  for x in xs: input.add jsString(x) & "\n"   # round-trips: checked below
  writeFile dir / "in.txt", input
  let script = """
const fs = require('fs');
const xs = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(Number);
const out = xs.map((x) => [String(x), x.toFixed(0), x.toFixed(1), x.toFixed(2), x.toFixed(3), String(Math.round(x))].join(' '));
fs.writeFileSync(process.argv[3], out.join('\n') + '\n');
"""
  writeFile dir / "check.js", script
  let ran = execCmd("node " & quoteShell(dir / "check.js") & " " & quoteShell(dir / "in.txt") & " " &
                    quoteShell(dir / "out.txt")) == 0

  test "node ran":
    check ran

  test "String, toFixed, Math.round":
    if ran:
      let lines = readFile(dir / "out.txt").strip.splitLines
      check lines.len == xs.len
      var bad = 0
      for i, x in xs:
        let want = lines[i].split(' ')
        let got = @[jsString(x), toFixed(x, 0), toFixed(x, 1), toFixed(x, 2), toFixed(x, 3), jsString(jsRound(x))]
        if want != got:
          inc bad
          if bad <= 5: echo "ERROR ", x, ": Node ", want, ", nimaki ", got
      check bad == 0

suite "js strings":
  test "UTF-16 length":
    check utf16Len("abc") == 3
    check utf16Len("日本") == 2
    check utf16Len("🎉") == 2
    check utf16Len("é") == 1
  test "code units":
    var units: seq[int]
    for u in codeUnits("a🎉"): units.add u
    check units == @[97, 0xD83C, 0xDF89]
  test "trim":
    check jsTrim("  x 　\n") == "x"
    check jsTrimEnd("x ") == "x"

suite "Number() and string order, against Node":
  let texts = @["", " ", "5", " 5 ", "\t3\n", "1.", ".5", "-.5", "+.5", "1e3", "1E+3", "1e", "e3", ".",
                "-", "+", "0x1F", "0X1f", "-0x1", "0o17", "0b101", "0b2", "0x", "Infinity", "-Infinity",
                "+Infinity", "infinity", "1_000", "007", "1.2.3", "5 5", "　5　", " 4",
                "4 ", "NaN", "1e400", "-0", "0.0000001", "12abc", "١", "５", "1,5", "3:4",
                "99999999999999999999", "123456789012345678901234567890", "0.1e-5", "+1", "--1"]
  let names = @["b", "a", "B", "é", "e", "", "😀", "日本", "", " ", "Z", "ä", "￿", "𝟘"]
  let dir = getTempDir() / "nimaki-test-js"
  createDir dir
  var input = ""
  for t in texts: input.add t.escapeJson & "\n"
  input.add "--\n"
  for t in names: input.add t.escapeJson & "\n"
  writeFile dir / "in2.txt", input
  writeFile dir / "check2.js", """
const fs = require('fs');
const lines = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n');
const cut = lines.indexOf('--');
const nums = lines.slice(0, cut).map((l) => String(Number(JSON.parse(l))));
const names = lines.slice(cut + 1).map((l) => JSON.parse(l)).sort();
fs.writeFileSync(process.argv[3], JSON.stringify({ nums, names }));
"""
  let ran = execCmd("node " & quoteShell(dir / "check2.js") & " " & quoteShell(dir / "in2.txt") & " " &
                    quoteShell(dir / "out2.txt")) == 0

  test "Number(s)":
    check ran
    if ran:
      let want = parseJson(readFile(dir / "out2.txt"))["nums"]
      for i, t in texts:
        let got = jsString(jsToNumber(t))
        if got != want[i].getStr: echo "ERROR Number(", t.escapeJson, "): Node ", want[i].getStr, ", nimaki ", got
        check got == want[i].getStr

  test "sort() order":
    if ran:
      var got = names
      got.sort(jsCompare)
      var want: seq[string]
      for n in parseJson(readFile(dir / "out2.txt"))["names"]: want.add n.getStr
      check got == want
