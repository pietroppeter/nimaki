## Detection and preprocessing (src/nimaki/detect.nim, preprocess.nim), checked against Pele's
## detectType in Node on every input of the corpus: the same type, or the same error (a front
## matter that is not valid YAML).
import std/[unittest, osproc, os, json]
import nimaki/[core, errors]
import ../tools/common

suite "detect, against Node":
  let cases = parseFile(repoDir / "corpus" / "cases.json")["cases"]
  let dir = getTempDir() / "nimaki-test-detect"
  createDir dir
  var sources = newJArray()
  for c in cases: sources.add c["source"]
  writeFile dir / "in.json", $sources
  writeFile dir / "check.mjs", """
import fs from 'node:fs';
const { detectType } = await import(process.argv[2]);
const sources = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const out = sources.map((s) => { try { return detectType(s) ?? ''; } catch (e) { return 'ERROR ' + e.code; } });
fs.writeFileSync(process.argv[4], JSON.stringify(out));
"""
  let pkg = "file://" & repoDir / "reference" / "npm" / "package" / "dist" / "pele.js"
  let ran = execCmd("node " & quoteShell(dir / "check.mjs") & " " & quoteShell(pkg) & " " &
                    quoteShell(dir / "in.json") & " " & quoteShell(dir / "out.json")) == 0

  test "node ran":
    check ran

  test "detectType on every corpus input":
    if ran:
      let want = parseFile(dir / "out.json")
      var bad = 0
      for i, c in cases.getElems:
        var got: string
        try: got = detectType(c["source"].getStr)
        except PeleError as e: got = "ERROR " & e.code
        if got != want[i].getStr:
          inc bad
          if bad <= 5: echo "ERROR ", c["id"].getStr, ": Pele ", want[i].getStr, ", nimaki ", got
      check bad == 0
