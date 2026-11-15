## Checks the hosts of src/nimaki/util/url.nim (`parseDomain`, through IDNA in `idna.nim`)
## against Node: the same hosts through `new URL("http://" + host + "/").hostname`. Random hosts
## from pieces that IDNA treats each in its own way (mapped, ignored, refused, joiners, scripts
## written right to left, Punycode), and each code point up to U+2FFFF next to a letter.
import std/[os, osproc, json, random, options, unittest, unicode]
import ../src/nimaki/util/url

const pieces = ["a", "b", "e", "1", "-", ".", "é", "Ω", "ß", "ς", "ﬀ", "Ⅸ", "ア", "ｱ", "Ａ", "K", "Å",
  "ǅ", "İ", "한", "ᄀ", "ᅡ", "ᆨ", "\u0301", "\u0300", "\u0344", "\u0958", "\u200C",
  "\u200D", "\u094D", "क", "ا", "ل", "ن", "١", "۱", "\u0670", "א",
  "\u05BF", "٣", "٫", "\u00A0", "\u3000", "\u2028", "\u00AD", "\uFEFF", "\u200B", "。", "😀", "𝐀",
  "xn--", "xn--a", "xn--ls8h", "xn--cib", "%41", "%C3%A9"]

proc buildDir(): string = currentSourcePath().parentDir.parentDir / "build"

proc main() =
  var r = initRand(7)
  var hosts: seq[string]
  for i in 0 ..< 20000:
    var s = ""
    for k in 0 ..< r.rand(1 .. 6): s.add pieces[r.rand(pieces.high)]
    hosts.add s
  var cp = 0x80
  while cp < 0x30000:
    if cp < 0xD800 or cp > 0xDFFF:
      let ch = $Rune(cp)
      hosts.add "a" & ch
      hosts.add ch & "b"
    cp += (if cp < 0x10000: 1 else: 7)
  let input = buildDir() / "idna-hosts.json"
  createDir input.parentDir
  writeFile input, $(%hosts)
  let script = """
const hosts = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
const out = hosts.map((h) => { try { return new URL('http://' + h + '/').hostname; } catch { return null; } });
process.stdout.write(JSON.stringify(out));
"""
  let (output, code) = execCmdEx("node -e " & quoteShell(script) & " " & quoteShell(input))
  doAssert code == 0, output
  let want = parseJson(output)
  var bad = 0
  for i, h in hosts:
    let got = parseDomain(h)
    let w = if want[i].kind == JNull: none(string) else: some(want[i].getStr)
    if got != w:
      inc bad
      if bad <= 10: echo "ERROR ", (%h), ": Node ", w, ", nimaki ", got
  test "hosts as new URL() writes them (" & $hosts.len & ")":
    check bad == 0

main()
