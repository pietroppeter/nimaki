## devlog: 15 Nov 2026 A | Both builds, every file | The odd-character fuzzer now runs nimaki's JavaScript build too; it found half an emoji lost on the way out, and with that fixed, every ported file but one is conformant.
## kind: port
import std/[json, os, sequtils, strformat, strutils]
import nimib
import ../blocks

nbInit
nb.usePost()

const here = currentSourcePath.parentDir / "data" / "both_builds_every_file"
var runs: seq[JsonNode]
for seed in 1 .. 7: runs.add parseJson(readFile(here / &"mutate-js-{seed}.json"))
let totals = parseJson(readFile(here / "portmap-totals.json"))["totals"]
proc thousands(n: int): string = insertSep($n, ',')
let
  answers = runs.mapIt(it["cases"].getInt).foldl(a + b, 0)
  different = runs.mapIt(it["different"].getInt).foldl(a + b, 0)
  conformant = totals["conformant"]["files"].getInt
  draft = totals["draft"]["files"].getInt

nbText: &"""
## The findings, first

- **The JavaScript build agrees with Pele on odd characters too.** `tools/mutate.nim --js` asks
  nimaki compiled to JavaScript the same {thousands(answers)} questions as the
  [previous post](../one-odd-character/) asked the C build: {different} answers differ.
  CI now runs both.
- **Before the fix, three did**, all the same way: an error message that quotes half of an emoji
  came out of the JavaScript build as `%ed%a0%bd` instead of the half character Pele gives.
- **{conformant} ported files are now conformant**, the state that says a file is proven equal
  to Pele ([decision 0014](../../decisions/#0014-tests-and-fuzzing-make-a-file-conformant-without-a-second-reading)).
  {draft} stays draft: the text measurer, whose half that measures with a browser canvas is not
  ported.

## Half of a character

A computer keeps text as numbers. JavaScript keeps a string as a list of 16-bit numbers, *code
units*; a character past U+FFFF, such as most emoji, takes two of them, a *surrogate pair*. A
program can cut a pair in two, and then holds a *lone surrogate*: half of a character. V8 does it
in one message: when `JSON.parse` stops at an emoji, it quotes the first code unit of what it
stopped at.

Nim keeps a string as bytes, in UTF-8, which has no way to write half a character. nimaki writes
one as the three bytes it would take if it were a character (a form called WTF-8), as
[decision 0016](../../decisions/#0016-regular-expressions-as-pele-writes-them-on-nim-regex)
records, so the half survives inside the port.

The trouble was the way out. When the JavaScript build hands a string to JavaScript, `nim js`
turns its bytes into a JavaScript string by decoding them as UTF-8, and when that fails, as it does
on those three bytes, it gives up and writes them as percent escapes: `%ed%a0%bd`. So a message
that quotes a lone surrogate was garbled.

`src/nimaki/js.nim` now has `toJsString`, which decodes the bytes itself: those three bytes become
the half character again, any other byte that is not UTF-8 becomes U+FFFD (as the browser's
`TextDecoder` reads it), and text that is plain UTF-8 takes the usual, fast way. The build's
entry point (`render` in `web.nim`), the bridge to Pele's tests and the runner of the referees use
it. The message now comes out as Pele's, half character and all.
"""

nbNote """
- `src/nimaki/js.nim`: `toJsString`, for the JavaScript build.
- `src/nimaki/web.nim`, `tools/peletests/bridge.nim`, `tools/jsrunner.nim`: strings handed to
  JavaScript go through it; the runner also writes a lone surrogate as a JSON escape, since a file
  in UTF-8 cannot hold one either.
- `tools/answers.nim`: the reader of such escapes, which `tools/mutate.nim` had for Pele's answers,
  now reads the JavaScript build's too.
- `tools/mutate.nim`: `--js`; CI runs seeds 1 to 7 in both builds.
- `util/url.nim`, `util/yaml.nim`, `diagrams/class/*`, `diagrams/gantt/*`: conformant.
""", nkNim, "In the port"

nbNote """
- `tools/mutate.nim --js` on seeds 1 to 7, the counts above; `nimaki.render` of the JavaScript
  build in Node gives Pele's message, character for character, on the case that differed.
- difftest of the JavaScript build: every drawing of the corpus still the same bytes as Pele's.
- Pele's test suites on the JavaScript build; `tests/all.nim`.
""", nkDone, "Checked"

nbNote """
- Half a character going *in* is still read as U+FFFD, a divergence the
  [Decisions page](../../decisions/) lists (*Text that is not UTF-8*): Pele's sankey refuses a
  name that holds one, nimaki draws it. Two of Pele's tests say so, listed in
  `tools/peletests/known.txt`.
""", nkWarning, "Not changed"

nbText: """
## What this changes for the port

- Every ported file but the measurer is conformant, as the port map (`docs/data/portmap.json`,
  written by `nim r tools/portmap.nim`) records.
- The odd-character fuzzer keeps watch on both builds in CI.

## Sources

- How JavaScript keeps strings, and lone surrogates:
  [MDN, UTF-16 characters, Unicode code points, and grapheme clusters](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String#utf-16_characters_unicode_code_points_and_grapheme_clusters).
- WTF-8: [the encoding's description](https://simonsapin.github.io/wtf-8/).
- The code: [`src/nimaki/js.nim`](https://github.com/pietroppeter/nimaki/blob/main/src/nimaki/js.nim).
"""

nbSave
