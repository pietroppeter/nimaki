## Which diagram types a build draws. Not a port of a Pele file: Pele makes one file per type with
## its bundler (`dist/esm/diagrams/<type>.js`, `scripts/build.mjs`), and nimaki with a define,
## since Nim writes one JavaScript file per program (post *Why nimaki.js is big*):
##
##   nim js -d:danger -d:nimakiTypes=flowchart,sequence src/nimaki/web.nim
##
## The names are Pele's diagram types (`flowchart`, `gitGraph`, `quadrantChart`, `treeView`...),
## comma-separated; the default, `all`, draws every type. Detecting a type does not depend on it:
## a build that does not draw a type still names it, and says it is not supported yet, as Pele's
## core does for a type that is not loaded.
import std/strutils

const nimakiTypes* {.strdefine.} = "all"
  ## the diagram types of this build

func drawn*(diagramType: static string): bool {.compileTime.} =
  ## Whether this build draws `diagramType`.
  nimakiTypes == "all" or diagramType in nimakiTypes.split(',')
