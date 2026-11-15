# Package

version       = "0.1.0"
author        = "Pietro Peterlongo"
description   = "Pele, the Mermaid renderer, ported to Nim: Mermaid text in, themeable SVG out, identical to Pele byte for byte"
license       = "MIT"
srcDir        = "src"

# Dependencies
#
# The renderer needs Nim's standard library and nitely's regex (decision 0016), with the Unicode
# tables it reads. The versions are those of deps.lock, where the referee checked every case;
# a later minor version of either is not checked, so it is not allowed (decision 0020).
# The JavaScript build of large diagrams needs Nim 2.2.14 or later (decision 0015).

requires "nim >= 2.2.4"
requires "regex >= 0.27.0 & < 0.28.0"
requires "unicodedb >= 0.14.1 & < 0.15.0"
