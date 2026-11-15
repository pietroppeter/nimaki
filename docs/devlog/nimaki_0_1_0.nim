## devlog: 15 Nov 2026 E | nimaki 0.1.0 | The first release: every diagram type of Pele 1.13.0, byte for byte, as a nimble package that another project can require, and what it took to make an installed copy draw as the repository does.
## kind: tooling
import std/[json, os, sequtils, strformat, strutils]
import nimib
import ../blocks, ../pele
import nimaki

nbInit
nb.usePost()

const docs = currentSourcePath().parentDir.parentDir
proc data(name: string): JsonNode = parseJson(readFile(docs / "data" / name))
proc thousands(n: int): string = insertSep($n, ',')

let
  difftest = data("difftest.json")
  jsRun = data("js.json")
  peleTests = data("peletests.json")
  fuzz = data("fuzz.json")["types"]
  parsed = data("parsediff.json")
  install = data("installcheck.json")
  cases = difftest["cases"].getInt + difftest["diagrammari"]["cases"].getInt
  identicalC = difftest["identical"].getInt + difftest["diagrammari"]["identical"].getInt
  identicalJs = jsRun["difftest"]["identical"].getInt + jsRun["difftest"]["diagrammari"]["identical"].getInt
  fuzzedC = toSeq(fuzz.pairs).mapIt(it[1]["cases"].getInt).foldl(a + b, 0)
  fuzzedJs = toSeq(jsRun["fuzz"].pairs).mapIt(it[1]["cases"].getInt).foldl(a + b, 0)
  testCounts = peleTests["counts"]
  # the summary line of `nim r -d:release --undef:nimStringHash2 --undef:nimIntHash1
  # tools/difftest.nim --strict`, run for this post
  defaultHashes = readFile(currentSourcePath().parentDir / "data" / "nimaki_0_1_0" /
                           "default-hashes.txt").strip

nbText: &"""
## The findings, first

- **nimaki has its first release, 0.1.0**, the number Pietro chose. It draws as Pele
  {peleVersion}, every one of its 33 diagram types: on the referee's {cases.thousands} cases,
  {identicalC.thousands} identical in the C build and {identicalJs.thousands} in the JavaScript
  build, byte for byte.
- **It is now a package.** nimaki had no `nimaki.nimble`, the file by which nimble and atlas,
  Nim's package tools, find a package. With it, a project writes `requires "nimaki == 0.1.0"`, as
  diagrammari's proposal planned.
- **An installed copy did not build its C ABI.** `capi.nim` read Pele's version from
  `reference/PIN`, a file outside `src/`, and nimble installs only `src/`. The versions now live in
  `src/nimaki/version.nim`, and a test checks they agree with the pin, the nimble file and the
  changelog.
- **An installed copy draws as Pele too.** A new tool, `tools/installcheck.nim`, installs nimaki
  with nimble and draws the whole corpus from a program outside the repository:
  **{install["identical"].getInt.thousands} of {install["cases"].getInt.thousands} identical**.
  That program does not read nimaki's `nim.cfg`, so it also hashes with Nim's default hashes,
  which decision 0017 said would draw the same; now it is measured.
- **What is not in it**: Pele's browser side (`mount`, zoom), planned for later, and Pele's canvas
  measurer. The changelog lists it all.
"""

nbText: """
## What a release is

So far, anyone who wanted nimaki took whatever `main` held that day. That is fine for the people
who write it, and awkward for anyone who builds on it: `main` moves several times a day, and a
project that depends on it cannot say *which* nimaki it was checked with.

A **release** is a moment of the repository given a name, with a promise about what it holds.
Three words come with it:

- A **version** is the name, three numbers such as `0.1.0`: *major*, *minor*, *patch*. The
  convention most packages follow, *semantic versioning*, says how they move: the patch number for
  a fix, the minor number for something new, the major number when something that worked stops
  working. A major number of 0 means *young*: anything may still change.
- A **tag** is git's way to pin a name to one commit, forever: `v0.1.0` will always mean the same
  files. Nim's package tools read tags: asked for nimaki 0.1.0, they fetch the commit tagged
  `v0.1.0`.
- A **package** is what those tools install. For Nim, it is the repository with a `.nimble` file
  at its root: the name, the version, the folder with the code (`srcDir`), and what it requires.

The version lives in four places, and they must agree: the nimble file, the code, the changelog
and the tag. The code's copy is a constant any program can print:
"""

nbCode:
  echo "nimaki ", nimakiVersion, " draws as Pele ", peleVersion,
    " (", peleCommit[0 ..< 7], "), the types of Mermaid ", mermaidVersion

nbText: """
`tests/test_version.nim` reads the nimble file, the changelog and `reference/PIN`, and fails when
one of them says something else. The tag is the fourth place, and it is made by hand, last.
"""

nbMermaid """flowchart LR
  A[nimaki.nimble] --> T{test_version}
  B[version.nim] --> T
  C[CHANGELOG.md] --> T
  P[reference/PIN] --> T
  T --> I[installcheck]
  I --> G[tag v0.1.0]
  G --> R[GitHub release]
  G --> D[a project pins it]
""", "The path of a release: three files that must agree, an install that must draw as Pele, then the tag."

nbText: &"""
## Why 0.1.0, and not 1.13.0

Pietro was asked which of two readings he wanted: nimaki's own numbers, starting at 0.1.0, or
numbers that follow Pele's, so that nimaki 1.13.0 would draw as Pele 1.13.0. He chose 0.1.0.
Decision 0020 writes down what follows from it:

- **The Pele it draws as is not in the number.** It is in `peleVersion`, in the C ABI's
  `nimaki_pele_version()`, and in the first lines of each release's notes.
- **While the major number is 0**, moving the Pele pin (roadmap step *follow-pele*) is a minor
  release, 0.2.0: the drawings change because Pele's do. A fix of the port that keeps the pin is a
  patch release, 0.1.1.
- **1.0.0 waits** for the day the API is meant to stay, which is Pietro's call. *Pietro's answer,
  15 November 2026: after extensive use; with use, nimaki may move away from Pele and take on
  wider goals ([The answers in the posts](../the-answers-in-the-posts/)).*

The other reading has its appeal (one number tells you which Pele), but it leaves nimaki no
number of its own: a fix to the port with the same pin would need a suffix, and a change of
nimaki's API would have nowhere to go.
"""

nbText: &"""
## What is in 0.1.0

The numbers below are read from the data files the tools write (`docs/data/`), at the commit
this page was built from.

| Check | What it does | Result |
|---|---|---|
| difftest, C build | every case of the corpus, against Pele in Node | {identicalC.thousands} of {cases.thousands} identical |
| difftest, JavaScript build | the same, nimaki compiled with `nim js` | {identicalJs.thousands} of {cases.thousands} identical |
| fuzzer, C build | mutated inputs, every type | {fuzzedC.thousands} inputs, all identical |
| fuzzer, JavaScript build | mutated inputs, {jsRun["fuzz"].len} types | {fuzzedJs.thousands} inputs, all identical |
| Pele's own tests | {peleTests["tests"].getInt.thousands} tests, on the JavaScript build | {testCounts["passed"].getInt.thousands} pass, {testCounts["failed"].getInt} fail |
| models | `parse()` against Pele's | {parsed["same"].getInt.thousands} the same, {parsed["different"].getInt} different |
| installcheck | the installed package, from outside the repository | {install["identical"].getInt.thousands} of {install["cases"].getInt.thousands} identical |

Of Pele's tests that do not pass, none fails on a drawing: {testCounts["api"].getInt} call the
browser side, {testCounts["speed"].getInt} only miss one of Pele's time limits (the JavaScript
build is slower on stress tests, which the step *js-speed* is working on),
{testCounts["canvas"].getInt} tests the canvas measurer, and {testCounts["known"].getInt} are
listed with their reasons in `tools/peletests/known.txt`.

The release holds three ways in:

- **Nim**: `import nimaki`, then `render(text, options)`, `parse(text, options)` for the model,
  `render(model, options)`, `detectType`, and `PeleError` with Pele's code, line and column.
- **JavaScript**: `src/nimaki/web.nim`, compiled with `nim js`, gives `nimaki.render` in a page.
- **C**, for other languages: `src/nimaki/capi.nim` and `capi.h`, JSON in and out. It gained one
  function for the release, `nimaki_version()`.
"""

nbText: &"""
## Two things the release found

A release is a test of its own: the first time the code leaves the repository. Two things only
showed there.

**The C ABI read a file outside `src/`.** To answer `nimaki_pele_version()`, `capi.nim` read
`reference/PIN` while compiling (`staticRead`). In the repository the file is there. In an
installed package it is not: nimble copies only `srcDir`, here `src/`. The fix is
`src/nimaki/version.nim`, which holds the four facts as constants, and the rule in decision
0020: nothing the renderer compiles may read outside `src/`.

**An installed copy uses Nim's default hashes.** nimaki's `nim.cfg` picks faster hashes for
both builds (decision 0017), and it applies only when compiling inside this repository. Decision
0017 says the drawings do not depend on it, since every map whose order shows is ordered; it had
not been measured. Two runs measure it now: difftest with the two defines turned off
(`--undef:nimStringHash2 --undef:nimIntHash1`), and installcheck, whose program never sees
nimaki's configuration. Both draw every case as Pele does.
"""

nbNote &"""
`nim r tools/installcheck.nim` ran on {install["nim"].getStr}: nimble installed
{install["installed"].mapIt(it.getStr).join(", ")}, fetching the two dependencies from GitHub
as any user's nimble would; a program outside the repository drew
{install["identical"].getInt.thousands} of {install["cases"].getInt.thousands} cases identical
to Pele, {install["different"].getInt} different; {install["builds"].mapIt(it.getStr).join(" and ")}
of the installed package compiled. difftest with Nim's default hashes, run for this post:
`{defaultHashes}`.
""", nkDone, "Checked"

nbText: """
## How a project uses it

In a project's nimble file:

```nim
requires "nimaki == 0.1.0"
```

and then, in its code:

```nim
import nimaki
let drawing = render("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85")
writeFile "pets.svg", drawing.svg
```

nimaki's own requirements are Nim 2.2.4 or later and nitely's `regex` 0.27 (with `unicodedb`
0.14). They are pinned to those minor versions, the ones the referee checked; a newer one moves
in a pull request after the same checks.

For diagrammari, this is the first item of the list in the proposal post: *a tag of nimaki to
pin*. The second, a public `parse`, was done on 14 November. The third, Pele's browser side,
is what 0.1.0 leaves out. The proposal stays a proposal: nothing in diagrammari changes from
here.
"""

nbNote """
- Pele's browser side: `mount`, `enableZoom` and lazy loading, which diagrammari's client mode
  uses. A page that needs them still loads Pele's own bundle.
- The canvas measurer: nimaki measures text with Pele's `metricsMeasurer`, from font tables,
  which is what Pele itself uses in Node.
- Icons and math through the C ABI: the Nim API takes them, the C ABI does not yet.
""", nkWarning, "Not in 0.1.0"

nbText: """
## What this changes for the port

- **Every release follows decision 0020**: the nimble file and `version.nim` bumped together, a
  section of `CHANGELOG.md`, `nim r tools/installcheck.nim` passing, then the tag on a green
  commit of `main`. Tags still wait for Pietro.
- **The next minor release is the next Pele**: when *follow-pele* moves the pin, nimaki 0.2.0.
- **`src/` is self-contained**: a file outside it, read at compile time, is a bug that only
  installcheck finds.
- The roadmap step *release* is done with the tag.

## Sources

- The release: [`CHANGELOG.md`](https://github.com/pietroppeter/nimaki/blob/main/CHANGELOG.md),
  [`nimaki.nimble`](https://github.com/pietroppeter/nimaki/blob/main/nimaki.nimble),
  [`src/nimaki/version.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/version.nim),
  [`tests/test_version.nim`](https://github.com/pietroppeter/nimaki/blob/main/tests/test_version.nim),
  [`tools/installcheck.nim`](https://github.com/pietroppeter/nimaki/blob/main/tools/installcheck.nim),
  and decision 0020 on the [Decisions](../../decisions/) page.
- The proposal it answers: [A proposal for diagrammari](../a-proposal-for-diagrammari/).
- Semantic versioning: [semver.org](https://semver.org/). Nim's package manager:
  [nimble](https://github.com/nim-lang/nimble), and how it reads a `.nimble` file, its
  [README](https://github.com/nim-lang/nimble#readme); [atlas](https://github.com/nim-lang/atlas).
  What nimble installs (only `srcDir`) was seen in the installed copy, in the run above.
"""

nbSave
