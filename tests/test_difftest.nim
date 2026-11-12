## The referee's verdicts (tools/verdict.nim): difftest must tell identical from different, byte
## for byte.
import std/unittest
import ../tools/verdict
from ../tools/difftest import coverageName

suite "difftest":
  test "first difference":
    check firstDifference("<svg/>", "<svg/>") == -1
    check firstDifference("<svg a=\"1\"/>", "<svg a=\"2\"/>") == 8
    check firstDifference("<svg/>", "<svg/> ") == 6
    check firstDifference("", "") == -1

  test "verdicts":
    let pele = Answer(ok: true, svg: "<svg width=\"10\"/>")
    check compare("a", "pie", pele, pele).verdict == vIdentical
    check compare("a", "pie", pele, Answer(ok: true, svg: "<svg width=\"10.0\"/>")).verdict == vDifferent
    check compare("a", "pie", pele, Answer(ok: false, code: "unsupported")).verdict == vUnsupported
    let err = Answer(ok: false, code: "syntax", message: "Unexpected token at line 2")
    check compare("a", "pie", err, err).verdict == vIdentical
    check compare("a", "pie", err, Answer(ok: false, code: "syntax", message: "Unexpected token at line 3")).verdict == vDifferent
    check compare("a", "pie", err, pele).verdict == vDifferent
    check compare("a", "pie", pele, flipped(pele)).verdict == vDifferent

  test "type names":
    check coverageName("gitGraph") == "git"
    check coverageName("pie") == "pie"
