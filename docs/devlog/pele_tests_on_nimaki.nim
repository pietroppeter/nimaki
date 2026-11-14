## devlog: 14 Nov 2026 G | Pele's tests, on nimaki | Pele comes with almost seven thousand tests of its own. Now they run on nimaki too: none finds a different drawing, six found bugs on the way, and most of the port is conformant.
## kind: tooling
import std/[strformat, strutils, json, re, algorithm, tables, sequtils]
import nimib
import tabelline, tabelline/nimib
import ../blocks, ../site, ../pele
import nimaki
import nimaki/js
import ../../tools/answers

nbInit
nb.usePost()

let data = parseFile(docsDir / "data" / "peletests.json")
let counts = data["counts"]
proc count(k: string): int = counts{k}.getInt
let totals = parseFile(docsDir / "data" / "portmap.json")["totals"]
let conformantFiles = totals["conformant"]["files"].getInt
let draftFiles = totals["draft"]["files"].getInt
let portedLines = totals["conformant"]["code"].getInt + totals["draft"]["code"].getInt +
                  totals["verified"]["code"].getInt
let conformantShare = 100 * totals["conformant"]["code"].getInt div portedLines

# The speed misses: how far over Pele's bound each one is.
type Miss = object
  file, test: string
  ratio: float
var misses: seq[Miss]
for f in data["notPassed"]:
  if f["kind"].getStr != "speed": continue
  var m: array[2, string]
  if f["message"].getStr.find(re"expected ([0-9.e+]+) to be less than ([0-9]+)", m) >= 0:
    misses.add Miss(file: f["file"].getStr, test: f["test"].getStr,
                    ratio: parseFloat(m[0]) / parseFloat(m[1]))
misses.sort(proc (a, b: Miss): int = cmp(b.ratio, a.ratio))
let underTwice = misses.countIt(it.ratio < 2)

nbText: &"""
## The findings, first

- **Pele's own tests now run on nimaki.** Pele ships {data["files"].getInt} files of tests, run by
  a tool called vitest. A new tool, `tools/peletests.nim`, runs them twice: once as they are, and
  once with Pele's drawing swapped for nimaki's (its JavaScript build). Of the
  {data["tests"].getInt.thousands} tests that pass on Pele, **{count("passed").thousands} pass on
  nimaki**, and **none finds a drawing or an error that differs**.
- **The rest are sorted, not hidden.** {count("api")} use a part of Pele's interface nimaki does
  not have (`parse()`, which hands out the parsed model, and `mount()`, which draws into a web
  page); {count("speed")} draw the same but miss one of Pele's time limits; {count("canvas")} tests
  a measurer that needs a browser; {count("known")} are listed, with the reason, as known gaps.
- **Six bugs found and fixed.** Two crashes (a flowchart node with a size that is not a number, a
  sankey chart with a tiny font) and four places where the JavaScript build of nimaki was
  dramatically slow or ran out of memory: a 50,000-character label took 34 seconds, now a tenth of
  one. The corpus and the fuzzers had missed all six: they never write such inputs.
- **{conformantFiles} files of the port are now conformant** ({conformantShare}% of the ported
  lines). Pietro decided that tests and fuzzing are enough, without a second reading of each file
  ([decision 0014](../../decisions/#0014-tests-and-fuzzing-make-a-file-conformant-without-a-second-reading)).
  {draftFiles} files stay *draft*, because a difference is known in them and not fixed yet.
- **CI runs the suites on every pull request**, and fails when a test that passes on Pele fails
  on nimaki for any other reason.

## What a test suite is

A test is a small program that checks one thing and says *yes* or *no*. Pele's are written for
vitest, a test runner for JavaScript: `it` names the check, `expect` states what must be true.
This one, from Pele's `tests/render/math.test.ts`, checks that `$$x^2$$` stays plain text when
the page gives no typesetter:

```ts
it('leaves $$ as text without a resolver', () => {{
  const {{ svg }} = render('flowchart LR\n  A["$$x^2$$"]', options);
  expect(svg).toContain('$$x^2$$');
  expect(svg).not.toContain('pele-math');
}});
```

The referee nimaki has used so far (difftest) asks a different question: given the same text,
is nimaki's SVG the same as Pele's, byte for byte? That needs no knowledge of what the SVG should
be, only Pele to compare with, and it checks everything at once. A test checks one property, but
it can check things the corpus never shows: what happens with a 50,000-character label, with a
font size of a billionth of a pixel, with hostile text in every field. Pele's author wrote those
cases because they once broke something.

## How Pele's tests run on nimaki

Every test reaches Pele through one file, `src/index.js`, which exports `render`. vitest can
replace an imported file with another one (an *alias*), so the tool makes a copy of Pele, installs
its test tools, and points that import at a small module of nimaki's:

- `tools/peletests/bridge.nim` is compiled with `nim js` into a JavaScript module whose
  `nimakiRender` takes Pele's options as JavaScript values: numbers, lists, and functions too (a
  text measurer, an icon resolver, a typesetter), which it wraps as Nim procedures;
- `tools/peletests/index.mjs` gives it Pele's shape: `render`, `detectType`, `supports`, and
  `PeleError`, the class of Pele's errors, so that `expect(...).toThrow(PeleError)` works;
- what nimaki does not provide (`parse`, `mount`, zoom) throws, and marks the test, so that it is
  counted apart even when the test catches the error.

The text measurer stays Pele's own, as in difftest. Tests that call other parts of Pele directly
(a parser, the layout) still run those parts in TypeScript; they pass as they do on Pele, and
check Pele, not the port.

Each test that passes on Pele then gets one of these verdicts:
"""

block:
  type Row = object
    verdict, meaning: string
    tests: int
  let meaning = {"passed": "passes on nimaki too",
                 "api": "uses mount() or zoom, which nimaki does not provide (parse() too, until the post Pele's tests read the models)",
                 "model": "reads a model of a type whose models are not Pele's yet (since the post Pele's tests read the models)",
                 "unported": "draws a type nimaki does not draw yet",
                 "speed": "draws the same, but misses one of Pele's time limits",
                 "canvas": "tests the canvas measurer, which needs a browser",
                 "known": "a known gap, listed with its reason in tools/peletests/known.txt",
                 "failed": "anything else: an ERROR, and CI fails"}.toTable
  var rows: seq[Row]
  for k in ["passed", "api", "model", "unported", "speed", "canvas", "known", "failed"]:
    rows.add Row(verdict: k, meaning: meaning[k], tests: count(k))
  let t = tabella(rows, rownameCol = "verdict"):
    tabHeader "Pele's tests on nimaki", "the tests that pass on Pele 1.13.0, by what they do on nimaki"
    fmtInteger ["tests"]
    optCssTheme()
  nbTable t

nbText: """
## Six bugs the corpus had missed

The first run found 60 failures that were not about missing interface or missing types. Most
came from types another thread was porting at the time (venn, xy charts), which landed during the
afternoon. Six were bugs.

**A size that is not a number.** A flowchart node can give its image a size in its metadata:
`A@{ img: "cat.png", w: 120 }`. Pele reads `w` with JavaScript's `Number()`, which turns anything
that is not a number into NaN, and NaN means *no size*. nimaki called a parser that only accepts
digits, and threw on anything else. Pele's security tests put a script tag in every field, and that
was enough. The fix uses `jsToNumber`, nimaki's `Number()`; the node now draws as in Pele:
"""

nbCode:
  let src = "flowchart LR\n  A@{ label: \"x\", w: \"wide\" } --> B"
  let fromNimaki = render(src, toOptions(%*{})).svg
  echo "nimaki draws it: ", fromNimaki.len, " characters of SVG"
  echo "the same as Pele's: ", fromNimaki == peleSvg(src, %*{})

nbText: """
**A tiny font.** With a font size of a billionth of a pixel, a sankey chart divides by a line
height of almost nothing and gets *Infinity*. Pele files its labels in a `Map` keyed by line
number, and in JavaScript Infinity is a fine key. nimaki keyed its table by integers, and turning
Infinity into an integer stopped the JavaScript build with a `RangeError`. The table is now keyed
by numbers, as Pele's is (NaN included, which needed a little care: in Nim, NaN is not equal to
itself, so it gets a key of its own).

The other four were about speed, and only in the JavaScript build.

## Why the JavaScript build was slow

In JavaScript, a string is a value the engine shares: copying it copies a pointer. Nim's strings
are a sequence of bytes, and when nimaki is compiled to JavaScript, a Nim string becomes a
JavaScript array of numbers, one per byte. Copying it copies every byte. Code that copies a string
in passing, harmless in C, becomes a loop over the whole text, and if that happens once per
character, the time grows with the square of the length.

The C build was fast on all four inputs; the JavaScript build was not:

- **`runes`.** To cut a label into characters, several files used Nim's `for r in s.runes`. In
  JavaScript, Nim compiles that loop so that it copies `s` at every byte it reads. A label of
  50,000 characters took 34 seconds. `codePoints(s)`, a new iterator of `js.nim`, reads the bytes
  in place: 0.1 seconds.
- **A helper that captures the text.** The code that finds `%%{` directives had a small local
  procedure that reads spaces in the source. A local procedure that uses a variable of the
  procedure around it is a *closure*, and in JavaScript it got a copy of the whole source at each
  call: 12,000 unclosed directives took five seconds. As a `template`, pasted in place, it copies
  nothing: 0.2 seconds.
- **The same label, many times.** A packet field of 20,000 bits, with one bit per row, is drawn in
  20,000 pieces, and each piece kept its own copy of the field's label: with a 40,000-character
  label, that is 800 million bytes, which the JavaScript engine could not hold. The pieces now
  share one label (a `ref object`, which is a pointer in both builds). A class definition given
  to 8,000 classes, with 8,000 style declarations, had the same problem, solved the same way.
- **Hashing a long key.** The packet code also kept its fitted labels in a table keyed by the
  label's text, so every row hashed 40,000 characters again. JavaScript remembers a string's hash;
  Nim does not. The table is now keyed by the field itself.

Here is the difference `codePoints` makes to the result, which is none: it gives the same
characters as `runes`, as JavaScript's `Array.from` does, emoji included:
"""

nbCode:
  import std/unicode
  let label = "añ😀 漢"
  echo toSeq(codePoints(label))
  echo toSeq(label.runes).mapIt($it) == toSeq(codePoints(label))

nbText: &"""
These four patterns are now in the [porting guide](../../porting/), in a note called *Code
that JavaScript runs slowly*.

## And one from the compiler

The first CI run of this pull request failed 44 tests that passed in the sandbox, all with
JavaScript's *Maximum call stack size exceeded*. CI installed Nim 2.2.4; the sandbox has a newer
build of Nim 2.2. In 2.2.4, adding one string to another compiles to `a.push.apply(a, b)`, which
hands every byte of `b` to a function as a separate argument, and past about a hundred thousand
bytes, the size of a large diagram's SVG, the stack runs out. Nim 2.2.14, the latest release,
adds them in a loop. CI now uses it
([decision 0015](../../decisions/#0015-ci-builds-with-the-latest-nim-2-2-release)), after the
whole referee passed with it here.

## What is still slow

{count("speed")} of Pele's stress tests still draw the same in JavaScript but take longer than
Pele allows. {underTwice} of them by less than twice, and the tests ran four at a time, which
slows each one. The worst are many times over: they are the next step on the
[roadmap](../../roadmap/) (*Pele's time bounds in the JavaScript build*). Two more tests, JSON
nested 12,000 and 20,000 levels deep in a use case diagram, run the JavaScript build out of memory,
because the JSON reader keeps one path string per level; they are skipped and listed in
`tools/peletests/known.txt`. The C build draws them in half a second.
"""

nbFold "The ten slowest, against Pele's limit":
  var lines = ""
  for m in misses[0 ..< min(10, misses.len)]:
    lines.add &"- {m.ratio:.1f} times the limit: `{m.file}`, *{m.test}*\n"
  nbText: lines

nbText: &"""
## Conformant

Each ported file says in its first lines how far it has come: *draft* when translated,
*conformant* when proven. [Decision 0005](../../decisions/#0005-every-file-goes-through-translate-verify-conform)
asked for a step in between, a second reading of each file against the TypeScript by someone with
fresh eyes. On 14 November Pietro was asked whether tests and fuzzing are enough without it, and
answered yes; decision 0014 records it. A file is conformant when difftest and the fuzzers find its
part identical to Pele, in both builds, and Pele's tests that reach it pass.

Every type nimaki draws is identical on the corpus and in CI's fuzzers, and Pele's tests find no
other failure, so {conformantFiles} files moved to *conformant*. {draftFiles} stay *draft*,
because a difference is known in them and waits for its fix (the roadmap step *Odd characters*,
found by the article [How nimaki reads text](../how-nimaki-reads-text/)): the URL and YAML readers,
the class files (a line separator in a member changes a box) and the gantt files (a date with a
line separator), and the text measurer, whose canvas half is not ported. The port map
(`docs/data/portmap.json`, written by `nim r tools/portmap.nim`) lists every file and its state.

## What this changes for the port

- `nim r tools/peletests.nim` runs Pele's suites on nimaki; `--check` fails on a test that passes
  on Pele and not on nimaki, and CI runs it. The first run installs Pele's test tools with `npm
  ci` in `build/peletests/`, from registry.npmjs.org.
- A file moves to *conformant* by decision 0014; the porting guide and `AGENTS.md` say so.
- `tools/peletests/known.txt` lists the tests known not to pass, with the reason; a line goes when
  the port is fixed.
- New code that cuts a string into characters uses `codePoints`, and the porting guide warns about
  the other three patterns.
- CI builds with Nim 2.2.14 (decision 0015); the JavaScript build needs it, or a later 2.2, to
  draw large diagrams.

## Sources

- Pele's tests at the pin: [`tests/`](https://github.com/obsidianmd/pele/tree/3a2f075ee0c3d914f0fad3545fc0f193693975ac/tests),
  run with vitest ([vitest.dev](https://vitest.dev/)); the swap of `src/index.js` uses vitest's
  `resolve.alias`.
- The tool: `tools/peletests.nim`, `tools/peletests/` (bridge, module, setup, known gaps);
  the counts in `docs/data/peletests.json`.
- What was checked: one full run of the {data["files"].getInt} test files, after the fixes, on the
  JavaScript build. Not checked: the C build against Pele's tests, which call JavaScript functions
  the C build cannot receive; it is checked by difftest and the fuzzers.
"""

nbSave
