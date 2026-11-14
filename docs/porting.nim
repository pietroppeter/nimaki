## The porting guide, docs/porting/index.html: how Pele's TypeScript is written in Nim here.
## Every port step reads it first and adds to it what it learned. Kept up to date.
import nimib
import blocks

nbInit
nb.doc.filename = docsDir / "porting" / "index.html"
nb.usePage(section = "Porting guide", cadence = "kept up to date", title = "Porting guide · nimaki",
           homeHref = "../", description = "How Pele's TypeScript is translated to Nim: ground rules, the idiom map, and the traps.")

nbTitle "Porting guide · kept up to date", "The porting guide", """
How a TypeScript file of Pele becomes a Nim file here. Read it whole before porting anything:
the port is done by many sessions, and it only stays one program if they all translate the same
thing the same way. When a step finds a rule missing or wrong, it changes this page in the same
pull request.
"""

nbToc

nbText: """
## Ground rules

1. **Translate, do not improve.** Same types, same functions, same fields in the same order, same
   control flow, same order of side effects
   ([decision 0002](../decisions/#0002-this-is-a-port-not-a-rewrite)). If the TypeScript does
   something odd, the Nim does the same odd thing, with a comment if it helps.
2. **One TypeScript file, one Nim file.** `src/diagrams/pie/parser.ts` is
   `src/nimaki/diagrams/pie/parser.nim`; `src/svg/builder.ts` is `src/nimaki/svg/builder.nim`.
   A file directly in Pele's `src/` (`core.ts`, `detect.ts`) is `src/nimaki/core.nim`.
3. **Say what you ported.** The file starts with its origin and its state. The port map and the
   licence notice both read these lines
   ([decision 0007](../decisions/#0007-ported-files-name-their-origin-and-the-port-is-mit-like-pele)):

   ```nim
   ## port-of: src/diagrams/pie/parser.ts
   ## port-status: draft
   ```

   A Nim file that ports only part of a TypeScript file says `## port-part-of:` instead.
4. **Names.** Types, functions, fields and variables keep their name (TypeScript is already
   camelCase). A name that is a Nim keyword (`type`, `end`, `from`, `method`, `object`...) takes
   the nearest plain word, listed in the table of names below so that everyone picks the same.
5. **Comments come along.** They are part of the program we are porting; Pele comments only the
   non-obvious, so each one matters.
6. **Only the standard library** in `src/`. A new dependency needs a decision record.
7. **Draft, then conformant.** `draft` when translated, `conformant` when difftest and the fuzzer
   agree on its part and Pele's tests that reach it pass on the port
   ([decision 0014](../decisions/#0014-tests-and-fuzzing-make-a-file-conformant-without-a-second-reading));
   `verified`, a second reading against the TypeScript, is no longer required.
8. **Check, then claim.** A part is `done` on the [coverage map](../coverage/) only when
   `nim r tools/difftest.nim <type>` reports every case identical.
9. **It also compiles to JavaScript.** `nim js` must build the same renderer, and
   `nim r tools/difftest.nim --js` must find it identical too
   ([decision 0013](../decisions/#0013-nimaki-also-builds-with-nim-js)). A few ways of writing
   Nim break there and nowhere else; the traps below say which.

## The traps we already know of

These come from a first reading of Pele (12 November 2026). Each port step that meets one turns
it into a rule in the idiom map.
"""

nbNote """
JavaScript strings are UTF-16: `text.length`, `charCodeAt(i)`, `slice` and the text measurer
count 16-bit code units. Nim strings are bytes (UTF-8). Pele calls `charCodeAt` or
`codePointAt` about 640 times. A width that counts characters differently is a different SVG.
Settled by [decision 0011](../decisions/#0011-strings-stay-utf-8-javascript-s-utf-16-is-counted-only-where-it-shows):
strings stay UTF-8 and indexes are bytes; `utf16Len`, `codeUnits` and `codePointAt` of
`src/nimaki/js.nim` count and read UTF-16 where it shows (a limit, the measurer, an error
column). A test on a character a regular expression makes (`\s`, `[^\n\r]`) reads a whole code
point when the character can be outside ASCII.
""", nkNim, "Strings are UTF-16"

nbNote """
Every number Pele writes into SVG goes through one formatter (`num()` in `src/svg/builder.ts`:
round to 2 decimals). Below it is JavaScript's own number-to-string conversion (shortest
round-trip, `1e21` and beyond in exponent form, `-0` printed as `0`). Nim's `$` for floats is
not the same. Port `num()` once, with JavaScript's conversion, and test it against Node on
many numbers before any renderer uses it. Done in the core step: `jsString`, `toFixed` and
`jsRound` (`src/nimaki/js.nim`) agree with Node on about 4,000 seeded numbers, checked on
every run of `tests/test_js.nim`; `num()` is in `src/nimaki/svg/builder.nim`.
""", nkNim, "Numbers are JavaScript numbers"

nbNote """
Pele's source has about 480 regular expression literals, 122 of them sticky (counted in
*How Pele is built*); lookahead is used, lookbehind never. `std/re` needs PCRE at run time and differs
from JavaScript's engine in details (`\s`, Unicode classes, `lastIndex`, sticky `y` flags).
The default is a hand-written scanner with the same behaviour; a regex package needs a decision
record first. The core and pie needed about 60 of them, all written as scanners: each one says
in a comment the pattern it answers as. Watch the patterns that backtrack (`[OPEN]*[CJK]` in
`label.ts`, `\s+$` with the `m` flag in `accDescrValue`) and `^\s*` with the `m` flag, which
runs across line breaks.
""", nkWarning, "Regular expressions"

nbNote """
Gantt reads the current time (`Date.now()`) and works in local time. The port takes `now`
from the options like Pele, and difftest fixes it and runs the oracle with `TZ=UTC`.
""", nkWarning, "Time"

nbNote """
JavaScript rounds a tie up, toward +∞; Nim away from zero. `Math.round(-2.5)` is `-2`,
`round(-2.5)` is `-3`. `(12.5).toFixed(0)` is `13`; `formatFloat(12.5, ffDecimal, 0)` is `12.`
(C's `printf`: a tie to the even digit, and the dot kept). Pie writes every percentage with
`toFixed`. Use our `jsRound` and `toFixed`, never `round` or `formatFloat`, where Pele rounds.
""", nkWarning, "Rounding ties"

nbNote """
V8 computes `Math.sin`, `cos`, `atan2`, `pow`, `log10` with its own port of fdlibm and `hypot`
with its own algorithm; Nim calls the C library. On 100,000 seeded inputs they differ in the
last bit 0.6% (`log10`) to 40% (`hypot`) of the time, and never after `num()`'s rounding, but a
bit can still flip a comparison in a layout. Call them through one module of ours (`jsmath`), so
a port of V8's versions can replace Nim's in one place when difftest finds a case. `sqrt` is exact
in both.
""", nkWarning, "Math functions"

nbNote """
`Math.max` and `Math.min` return NaN when any argument is NaN; Nim's `max` and `min` do not.
Pele's layout uses NaN for *unknown* (`hint`, `key`). Use `jsMax`/`jsMin` where NaN can reach.
""", nkWarning, "NaN"

nbNote """
A JavaScript `RangeError` (stack overflow from deep nesting) is caught by `render()` and reported
as a `limit` error. In Nim deep recursion crashes the process. Where Pele recurses on the input's
nesting, the port counts depth and raises the same `limit` error. Any other `RangeError` Pele can
throw (`String.fromCodePoint` of a bad code) is a `JsRangeError` of `errors.nim`, which `render()`
turns into the same `limit` error.
""", nkWarning, "Deep nesting"

nbNote """
Nim compares identifiers without case and underscores, except their first letter: `BOLD` and
`Bold` are one name, and so are `metrics.BOLD` and `measurer.Bold`. Pele has both (the table of
bold widths and `Style.Bold`). The core named the style bits `Bold`, `Italic`, `Mono`... (Pele's
`Style` members) and gave the other the module's name or a suffix (`BOLD_ATTR`).
""", nkWarning, "Two names that are one"

nbNote """
A closure that uses a `var` parameter (a `seq` passed by reference) does not compile in Nim.
Pele's local helpers often change the arrays of the function around them (`commit()` in
`label.ts`'s `wrap`): write them as a `template`, which pastes the code in place.
""", nkWarning, "Local helpers that change their surroundings"

nbNote """
Four ways of writing Nim compile to C but not to JavaScript (Nim 2.2), and the JavaScript build
is checked in CI. An address chosen by an `if` expression, `let p = if down: addr g.a else: addr
g.b`, loses its field in JavaScript: use `choose(down, g.a, g.b)` of `layout/layered.nim`, or an
`if` statement. A `ref` cast to `int` (`cast[int](node)`, a key by identity) is no number in
JavaScript: key the `Table` by the `ref` itself, with `proc hash(n: Node): Hash =
hash(cast[pointer](n))`, which is the address in C and an id in JavaScript. And an `if`
expression whose branch is a constant array made a `seq` (`if s.len > 0: s else: @DEFAULTS`)
loses that branch: assign it in an `if` statement. Last, a JavaScript number is a double: a product
of two 32-bit numbers can pass 2^53 and lose its low bits before Nim masks it (the JavaScript build
of Nim 2.2.4, which CI uses, does). Multiply in 16-bit halves, as `imul` in
`diagrams/cynefin/boundaries.nim` does.
""", nkWarning, "Code that only C can run"

nbNote """
The older types (timeline, journey, flowchart, sequence...) are read by hand-written loops that
port Jison's compiled rules: `src.charCodeAt(p)`, then `p++`. With byte offsets, read the
character with `codeAt(src, p)` of `common/scan.nim` (a code point, -1 past the end) and step
with `sizeAt(src, p)` wherever the character tested can be outside ASCII (`isSpace`). A loop
that only looks for ASCII (a colon, `#`, a line break) can step byte by byte: no byte of a longer
character is ASCII. A `text.substring(n)` that drops a keyword and the `\s` after it drops
characters, not bytes (`substringFrom` of `js.nim`).
""", nkNim, "Hand-written lexers"

nbText: """
## The idiom map

One row per TypeScript idiom, with the one Nim translation everyone uses. The core and pie
filled it in; later steps add to it.

| TypeScript | Nim |
| --- | --- |
| `interface X { a: number; b?: string }` | `object` with `a: float` and `b: Option[string]`, or a default value when Pele treats missing and empty alike |
| `number` | `float` (JavaScript has only doubles); `int` only where the TypeScript does integer-only work and the result is the same |
| `readonly T[]`, `T[]` | `seq[T]` |
| `Map<K, V>` (insertion order) | `OrderedTable[K, V]` |
| `Set<T>` (insertion order) | `OrderedSet[T]` |
| `undefined` / `null` | `Option[T]`, or `nil` for `ref` types |
| `throw new PeleError(msg, code)` | `raise newPeleError(msg, code)` |
| `Math.round(x)` | `jsRound(x)`: `floor(x)`, plus one when `x - floor(x) >= 0.5` |
| `x.toFixed(n)` | `toFixed(x, n)` of ours (exact decimal value, ties up) |
| `` `${x}` ``, `String(x)` for a number | `jsString(x)` of ours (ECMAScript Number::toString) |
| `Math.sin` and the other libm calls | `jsmath.sin`... |
| `Math.max(a, b)` where NaN can occur | `jsMax(a, b)` |
| `Int32Array`, `Float64Array`, `Uint8Array` | `seq[int32]`, `seq[float]`, `seq[uint8]` |
| `Math.imul(a, b)`, `x >>> 0` | `uint32` arithmetic (wraps) |
| `x | 0`, `x ^ y`, `x >>> n` on a float (ToInt32 first) | ECMAScript ToInt32 (drop the fraction, wrap modulo 2^32; NaN and infinity give 0), then casts between `int32` and `uint32`, as in `cynefin/boundaries.nim` |
| `list.sort((a, b) => ...)` | `algorithm.sort` with the same comparator: both are stable |
| `withPalette(p, () => ...)` (a module global set for a call) | set the global, `try` the call, restore it in `finally` |
| a sticky regex `re.lastIndex = p; re.test(s)` | a matcher `proc (s: string, p: int): int` returning the end, or -1, with the pattern in a comment |
| `s.replace(re, ...)` with `/g` | a loop that copies `s` and writes the replacement at each match |
| `s.length` that is compared or printed | `utf16Len(s)` |
| `for (...) s.charCodeAt(i)` over a whole string | `for c in codeUnits(s)` |
| `s.trim()`, `trimStart()`, `trimEnd()` | `jsTrim`, `jsTrimStart`, `jsTrimEnd` (JavaScript's whitespace, wider than Nim's) |
| a string that may be `undefined` and is never `""` when set | `string`, with `""` for undefined (say so in a comment on the field) |
| a number option `options.padding ?? 8` | `Option[float]`: `options.padding.get(8)` |
| a `YamlValue` or `Config` (front matter, `%%{init}%%`) | `YamlValue` of `util/yaml.nim`: `nil` is undefined, kind `yNull` is null; `v["key"]` is nil when `v` is not a record |
| a `Diagram<Model>` | `Diagram` of `types.nim`, with the model as a `ref object of RootObj` |
| `Math.sin(x)` | `sin(x)` of `jsmath` (`import ../../jsmath`, and `from std/math import PI, ceil`) |
| `` `${n}` `` in an attribute | `jsString(n)`; but a coordinate goes through `num(n)` as in Pele |
| `Number(s)` of any text (a score, a value as written) | `jsToNumber(s)` (whitespace, `""` is 0, `Infinity`, `0x`; NaN otherwise); `jsNumber` only for what a lexer already checked |
| `names.sort()` with no comparator, `a < b` on strings | `sort(names, jsCompare)`: UTF-16 code unit order |
| `s.substring(n)` that drops a keyword and its space | `substringFrom(s, n)`: counts UTF-16 code units, not bytes |
| `src.charCodeAt(p)` in a lexer, then `p++` | `codeAt(src, p)`, then `p += sizeAt(src, p)` (`common/scan.nim`) |
| `text.match(/.../g)` that cuts text into pieces | an iterator or a proc returning `seq[string]`, the pattern in a comment (`units` in `fit.nim`) |
| a value that is a number or `undefined` (`seriesOf`) | an `int` with a named sentinel (`NO_SERIES = -1`) when no real value can be negative |
| a local arrow function that reads a `let` changed later (`eventTextW`) | a `template`, so it reads the current value |
| `a.rank - b.rank \|\| a.seq - b.seq` in a comparator | `(a.rank - b.rank).orElse(a.seq - b.seq)` (`orElse` of `layout/layered.nim`) |
| an inner function that changes an array its outer function was given as `var` | `let p = addr param`, then `template param: untyped = p[]`: a closure cannot capture a `var` parameter |
| `r[0]` that may read past the end (`undefined`, then NaN in arithmetic) | `if r.len > 0: r[0] else: NaN`; Nim stops where JavaScript reads `undefined` |
| `Object.is(a, b)` | equal, except that NaN is the same as NaN and 0 is not the same as -0 (`isSame` in `compound.nim`) |
| a field that is an array or `undefined`, read only for its items | an empty `seq`; a flag (`hasGroups`) where empty and undefined differ |
| `JSON.parse(text)` | `jsonParse(text)` of `js.nim` (strict, as JavaScript is; raises `JsSyntaxError`), never `std/json`'s `parseJson`, which accepts comments, trailing commas and `01` |
| `s.toLowerCase()` compared with a list of words | `unicode.toLower(s)`: JavaScript lowers more than ASCII (the Kelvin sign is `k`) |
| a value that is a string, a list or a nested list (`SeqItem` of sequence) | a variant `ref object` with one branch per shape, walked with an explicit stack |
| `x.toPrecision(p)`, `x.toExponential(d)`, `parseFloat(s)` | `toPrecision`, `toExponential`, `jsParseFloat` of `js.nim` (exact decimal, ties up; `jsParseFloat` reads the longest number at the start) |
| a token matcher that keeps state between calls (`unclosed` in `accDescr.ts`, a run of digits in radar) | a `scanner: proc (): Scanner` on the `TokenType`: the tokenizer makes the matcher once per text, so the state starts fresh |
| an arrow function made in a loop, keeping that turn's values | a closure returned by a proc of its own (`columnMap` in `treeview/box_drawing.nim`): closures made in a Nim loop share the loop's variables |
| an index into a string that enters arithmetic (a column, a depth) | UTF-16 code units: `utf16Len(s, 0, at)` from bytes, `unitOffset(s, first, units)` back to bytes |

## Names

Names changed because they clash with Nim (filled in as they are met).

| TypeScript | Nim |
| --- | --- |
| `type` | `kind` (`diagramType` where the type of a diagram is meant) |
| `src/diagrams/common/fit-width.ts` | `fit_width.nim` (a module name has no `-`) |
| `boxDrawing.ts`, `accDescr.ts` | `box_drawing.nim`, `acc_descr.nim` (a module named `accDescr` would clash with its proc `accDescr`) |
| `end` | `stop` |
| `from` | `start` or `first` |
| `out` | `output` |
| `open` (a local) | `opening` |
| `Style.Bold` and its siblings | `Bold`, `Italic`, `Mono`, `Sub`, `Sup`, `Underline` (`int` bits) |
| `const enum T` of a parser | `T_name` constants (`T_newline`) |
| `T.END` beside `T.end` (style insensitivity makes them one name) | `T_STOP` for `T.END`; `T_end` stays the `end` keyword |
| `KIND` beside `Kind` | `kinds` (only the first letter of a Nim name is case sensitive) |
| `reach.of(node, side)` | `reachOf` (`of` is a keyword) |
| `LinkInfo` of `flowchart/types.ts` | `FlowLinkInfo` (the core's `LinkInfo` is a link in the SVG) |
| `const enum LINETYPE`, `PLACEMENT` of sequence | `LINETYPE_SOLID`, `PLACEMENT_OVER`... (`NO_TYPE` = -1 for an undefined `type`) |
| a message's `from` (sequence) | `start` |
"""

nbSave
