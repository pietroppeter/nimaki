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
7. **Three states.** `draft` when translated, `verified` when a second pass with fresh eyes has
   read it against the TypeScript, `conformant` when difftest agrees on its part
   ([decision 0005](../decisions/#0005-every-file-goes-through-translate-verify-conform)).
8. **Check, then claim.** A part is `done` on the [coverage map](../coverage/) only when
   `nim r tools/difftest.nim <type>` reports every case identical.

## The traps we already know of

These come from a first reading of Pele (12 November 2026). Each port step that meets one turns
it into a rule in the idiom map.
"""

nbNote """
JavaScript strings are UTF-16: `text.length`, `charCodeAt(i)`, `slice` and the text measurer
count 16-bit code units. Nim strings are bytes (UTF-8). Pele calls `charCodeAt` or
`codePointAt` about 640 times. A width that counts characters differently is a different SVG.
The port needs one agreed way to iterate and index "like JavaScript" (a small module of ours),
used everywhere a TypeScript file indexes a string.
""", nkWarning, "Strings are UTF-16"

nbNote """
Every number Pele writes into SVG goes through one formatter (`num()` in `src/svg/builder.ts`:
round to 2 decimals). Below it is JavaScript's own number-to-string conversion (shortest
round-trip, `1e21` and beyond in exponent form, `-0` printed as `0`). Nim's `$` for floats is
not the same. Port `num()` once, with JavaScript's conversion, and test it against Node on
many numbers before any renderer uses it.
""", nkWarning, "Numbers are JavaScript numbers"

nbNote """
Pele's source has about 480 regular expression literals, 122 of them sticky (counted in
*How Pele is built*); lookahead is used, lookbehind never. `std/re` needs PCRE at run time and differs
from JavaScript's engine in details (`\s`, Unicode classes, `lastIndex`, sticky `y` flags).
The default is a hand-written scanner with the same behaviour; a regex package needs a decision
record first.
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
nesting, the port counts depth and raises the same `limit` error.
""", nkWarning, "Deep nesting"

nbText: """
## The idiom map

To be filled by the first port steps (the core and pie). One row per TypeScript idiom, with the
one Nim translation everyone uses.

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
| `list.sort((a, b) => ...)` | `algorithm.sort` with the same comparator: both are stable |
| `withPalette(p, () => ...)` (a module global set for a call) | set the global, `try` the call, restore it in `finally` |

## Names

Names changed because they clash with Nim (filled in as they are met).

| TypeScript | Nim |
| --- | --- |
| `type` | `kind` |
"""

nbSave
