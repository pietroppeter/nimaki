## The release facts agree (decision 0020): the version of nimaki in `src/nimaki/version.nim`,
## `nimaki.nimble` and `CHANGELOG.md`, and the Pele of `version.nim` and `reference/PIN`.
## A nimble install holds only `src/`, so the renderer reads none of the other files itself.
import std/[unittest, os, strutils]
import nimaki
import ../tools/common

proc value(text, key, sep: string): string =
  for line in text.splitLines:
    let l = line.strip
    if l.startsWith(key) and sep in l:
      return l.split(sep, 1)[1].strip.strip(chars = {'"'})

suite "release facts":
  let pin = readFile(repoDir / "reference" / "PIN")
  test "version.nim says the Pele of reference/PIN":
    check peleVersion == pin.value("TAG", "=")
    check peleCommit == pin.value("COMMIT", "=")
    check mermaidVersion == pin.value("MERMAID", "=")
  test "nimaki.nimble has the version of version.nim":
    check readFile(repoDir / "nimaki.nimble").value("version", "=") == nimakiVersion
  test "CHANGELOG.md has a section for this version":
    check ("## " & nimakiVersion & " ") in readFile(repoDir / "CHANGELOG.md")
