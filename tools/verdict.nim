## The referee's verdict on one case: Pele's answer against nimaki's, byte for byte. Used by
## tools/difftest.nim, its tests, and the pages that show how the referee works.
import std/strutils

type
  Answer* = object
    ## What one side made of a case: an SVG, or an error.
    ok*: bool
    svg*, code*, message*: string
  Verdict* = enum vIdentical = "identical", vDifferent = "different", vUnsupported = "unsupported"
  Outcome* = object
    id*, diagramType*: string
    verdict*: Verdict
    detail*: string

func firstDifference*(a, b: string): int =
  ## The offset of the first byte where `a` and `b` differ, or -1 when they are equal.
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]: return i
  if a.len != b.len: min(a.len, b.len) else: -1

func around*(s: string, at: int): string =
  ## A short, one-line excerpt of `s` around offset `at`.
  let lo = max(0, at - 30)
  let hi = min(s.len, at + 30)
  result = (if lo > 0: "…" else: "") & s[lo ..< hi].replace("\n", "\\n") & (if hi < s.len: "…" else: "")

func compare*(id, diagramType: string, want, got: Answer): Outcome =
  ## The verdict on one case: Pele's answer `want`, nimaki's `got`.
  result = Outcome(id: id, diagramType: diagramType)
  if not got.ok and got.code == "unsupported":
    result.verdict = vUnsupported
  elif want.ok and got.ok:
    let at = firstDifference(want.svg, got.svg)
    if at < 0: result.verdict = vIdentical
    else:
      result.verdict = vDifferent
      result.detail = "first difference at byte " & $at & " of " & $want.svg.len & ": Pele `" &
        around(want.svg, at) & "` nimaki `" & around(got.svg, at) & "`"
  elif not want.ok and not got.ok:
    if want.code == got.code and want.message == got.message: result.verdict = vIdentical
    else:
      result.verdict = vDifferent
      result.detail = "both throw: Pele " & want.code & " `" & want.message & "`, nimaki " & got.code & " `" & got.message & "`"
  else:
    result.verdict = vDifferent
    result.detail = if want.ok: "Pele draws, nimaki throws " & got.code & " `" & got.message & "`"
                    else: "Pele throws " & want.code & " `" & want.message & "`, nimaki draws"

func flipped*(a: Answer): Answer =
  ## `a` with one byte changed: what a candidate one byte away from Pele looks like.
  result = a
  if a.ok:
    let i = a.svg.len div 2
    result.svg[i] = (if a.svg[i] == 'x': 'y' else: 'x')
  else:
    result.message.add '.'
