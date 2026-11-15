## devlog: 15 Nov 2026 C | A proposal for nim-regex | Two things nimaki measured in nim-regex, the regex library its C build runs on: copies that make it slow under nim js, and a walk with groups that slows down as it goes. A small patch for the first, and a description of the second, for its author to consider.
## kind: research
import std/[json, strformat, strutils]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site

nbInit
nb.usePost()

let regex = parseFile(docsDir / "devlog" / "data" / "dates_and_styles_in_javascript" / "regex.json")
let rows = regex["rows"].getElems
let quad = regex["quadratic"]["rows"].getElems
let patch = readFile(docsDir / "devlog" / "data" / "dates_and_styles_in_javascript" / "pstate.patch")

nbText: """
## The findings, first

- [nim-regex](https://github.com/nitely/nim-regex), by nitely, is the regex library nimaki runs
  Pele's regular expressions on in its C build, where it is fast and has been exact on every case
  nimaki checks ([decision 0016](../../decisions/#0016-regular-expressions-as-pele-writes-them-on-nim-regex)).
  It also supports `nim js`, and nimaki used it there until [the last post](../javascripts-own-regular-expressions/).
- **Under `nim js`, building and storing the engine's state copies it, at every character.** A
  patch of about ten lines sets the fields one by one instead, and makes a walk over a text about
  1.9 times faster in JavaScript, with no change in C.
- **A walk over every match (`findAll`) of a pattern with capture groups slows down as the
  matches pile up, in both builds.** The groups of every match found stay in use until the walk
  ends, and are checked again at each character.
- This post is the proposal. nimaki does not open issues or pull requests on other projects:
  whether to take any of this, and how, is the author's call; Pietro decides whether to point the
  author to it. *Pietro's answer, 15 November 2026: not now
  ([The answers in the posts](../the-answers-in-the-posts/)).*
"""

nbText: """
## Copies under nim js

The engine runs a pattern as a small machine and keeps, at each character, the states the
machine can be in. Each state is a small object, `Pstate`: the node of the pattern it is at, its
captures, and the bounds of its match so far. `initPstate` builds one, and `Pstates.add` stores
it in a list.

In C, both are a copy of a few machine words. Under `nim js`, Nim builds an object with a
constructor and then copies it into place with `nimCopy`, a generic function that walks the
type's description, field by field, and the nested `bounds` slice too. A profile of a walk over
4,000 lines put more than half of the time in those copies.

The patch below sets the fields one by one in both places, which compiles to plain assignments in
JavaScript and to the same code as before in C. It was tried on a scratch copy of the library at
the commit nimaki pins, with the benchmark below only: nimaki's full checks did not run on it.
"""

nbCode:
  # pstate.patch, against src/regex/nfatype.nim at the commit in nimaki's deps.lock
  echo patch.strip

block:
  type Row = object
    measured: string
    c, js, patched: string
  var t: seq[Row]
  for r in rows:
    t.add Row(measured: r["case"].getStr, c: &"""{r["c"].getFloat:.1f}""",
              js: $int(r["js"].getFloat), patched: $int(r["patched"].getFloat))
  let table = tabella(t, rownameCol = "measured"):
    tabHeader "nim-regex on 4,000 lines", "milliseconds: in C, under nim js, and under nim js with the patch"
    optCssTheme()
  nbTable table

nbText: """
The next copy in the same profile is the slice of `bounds` itself, built with `..` at each new
state (`bounds.a .. i-1` in `nfafindall2.nim`); passing the two ends as integers would remove it
too. That was not tried.

## A walk with groups

`findAll` yields every match of a pattern in a text. With capture groups, the engine keeps a
block of captures per state in `Capts3`, and marks blocks it can reuse; `recycle` goes over all
the marks at each character. The blocks of matches already yielded seem to stay marked as in use
until the walk ends, so the list that `recycle` reads grows with each match, and the walk takes
time in the square of the number of matches. A pattern without groups does not have it:
"""

block:
  type Row = object
    matches: int
    cWith, cWithout, jsWith, jsWithout: int
  var t: seq[Row]
  for r in quad:
    t.add Row(matches: r["tokens"].getInt, cWith: r["cGroups"].getInt, cWithout: r["cNoGroups"].getInt,
              jsWith: r["jsGroups"].getInt, jsWithout: r["jsNoGroups"].getInt)
  let table = tabella(t, rownameCol = "matches"):
    tabHeader "One findAll over a text of n matches", "milliseconds; dayjs's token pattern with its three groups and without them, in C and under nim js"
    fmtInteger ["cWith", "cWithout", "jsWith", "jsWithout"]
    optCssTheme()
  nbTable table

nbText: """
Doubling the matches makes the walk with groups four times slower in C, and the one without
groups twice. The reading of the cause comes from the code (`nfatype.nim`, `recycle` and
`keepAlive`; `nfafindall2.nim`, the end of `nextState`) and from these timings; it was not
confirmed with a fix. A fix might free the capture blocks of a match once it is yielded.

nimaki works around it on its side: where only the whole text of each match is read, it gives the
pattern without groups ([Dates and styles in JavaScript](../dates-and-styles-in-javascript/)).

## What this changes for the port

Nothing in nimaki's code. Its C build keeps nim-regex as it is, at the commit in `deps.lock`;
its JavaScript build runs on JavaScript's own `RegExp`
([decision 0019](../../decisions/#0019-javascript-s-own-regexp-in-the-javascript-build)). If the
library takes a change like these, moving the pin is a change to `deps.lock`.

## Sources

- nim-regex at the commit pinned in `deps.lock`, read in `deps/regex/src/regex/nfatype.nim`
  (`Pstate`, `initPstate`, `Pstates.add`, `Capts3`, `recycle`) and `nfafindall2.nim`.
- The measurements: `docs/devlog/data/dates_and_styles_in_javascript/` (`rxbench.nim`,
  `regex.json`, `pstate.patch`), from the post
  [Dates and styles in JavaScript](../dates-and-styles-in-javascript/).
"""

nbSave
