## The version of nimaki, and the Pele it draws as. Not a port of a file of Pele.
##
## nimaki's own version follows its releases (decision 0020); the Pele fields are those of
## `reference/PIN`, copied here because a package installed by nimble holds only `src/`.
## `tests/test_version.nim` fails when this file, `reference/PIN`, `nimaki.nimble` and
## `CHANGELOG.md` do not agree.

const
  nimakiVersion* = "0.2.0"   ## this release of nimaki, as in nimaki.nimble and the tag v0.2.0
  peleVersion* = "1.13.0"    ## the Pele release nimaki draws as, byte for byte
  peleCommit* = "3a2f075ee0c3d914f0fad3545fc0f193693975ac"  ## its commit in obsidianmd/pele
  mermaidVersion* = "12.1.0" ## the Mermaid whose diagram types that Pele draws
