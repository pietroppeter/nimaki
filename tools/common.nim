## What the tools share: where the reference is, and how they talk.
##
## The tools are written to be read by a coding agent with a small context window: a few lines
## on stdout, one line per problem starting with `ERROR` (so `grep ERROR` finds everything), the
## detail in a file under `build/`, and a last line that says what happened.
import std/[os, strutils, tables]

const
  repoDir* = currentSourcePath().parentDir.parentDir   ## the root of nimaki
  defaultRef* = repoDir / "reference" / "pele"         ## the pinned checkout of obsidianmd/pele
  defaultPackage* = repoDir / "reference" / "npm" / "package"  ## the pinned npm package (the oracle)
  dataDir* = repoDir / "docs" / "data"
  buildDir* = repoDir / "build"

proc readPin*(): Table[string, string] =
  ## reference/PIN as KEY -> VALUE.
  for line in lines(repoDir / "reference" / "PIN"):
    if line.len == 0 or line.startsWith("#"): continue
    let kv = line.split('=', maxsplit = 1)
    if kv.len == 2: result[kv[0]] = kv[1]

proc refDirFrom*(arg: string): string =
  ## The reference checkout: `--ref:PATH`, or $PELE_REF, or reference/pele.
  result = if arg.len > 0: arg else: getEnv("PELE_REF", defaultRef)
  if not fileExists(result / "src" / "core.ts"):
    quit "ERROR no Pele checkout at " & result &
      " (pass --ref:PATH, set PELE_REF, or run reference/fetch.sh)", 2

proc packageDirFrom*(arg: string): string =
  ## The oracle package: `--package:PATH`, or $PELE_PACKAGE, or reference/npm/package.
  result = if arg.len > 0: arg else: getEnv("PELE_PACKAGE", defaultPackage)
  if not fileExists(result / "dist" / "pele.js"):
    quit "ERROR no Pele package at " & result &
      " (pass --package:PATH, set PELE_PACKAGE, or run reference/fetch.sh)", 2

proc pinOf*(refDir: string): string =
  ## The version of a Pele checkout or package, read from its package.json.
  for line in lines(refDir / "package.json"):
    let l = line.strip
    if l.startsWith("\"version\""):
      return l.split('"')[3]

proc unixPath*(path: string): string = path.replace('\\', '/')
