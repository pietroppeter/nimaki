---
title: Regular expressions as Pele writes them, on nim-regex
status: accepted
date: 2026-11-14
---

## Context

Pele writes about five hundred regular expression literals (344 distinct ones, and 11
`new RegExp` calls; `corpus/regexes.json` lists them). Until now the porting guide asked for a
hand-written scanner for each, with the pattern it answers as in a comment: Nim's `std/re` needs
PCRE at run time and differs from JavaScript in details, and no regex package had a decision.
By 14 November the port held about 220 such scanners, one pattern (`/\n\s+/g`) written by hand
in 23 files. The post *The shape of the port* proposed one shared module of scanners. Pietro
asked instead to use nitely's pure Nim `regex` package: a dependency, but a good one.

The package (`regex` 0.27.0, MIT, with `unicodedb` 0.14.1, MIT, by the same author) is pure
Nim, matches in linear time and builds with `nim js`. Its syntax is close to JavaScript's, its
meaning is not. Checked by test (`tests/test_jsregex.nim`, against Node): `\s` holds U+0085 and
lacks U+FEFF; `\w`, `\d` and `\b` are Unicode; `.` matches `\r`, U+2028 and U+2029; the `i` flag
folds `ſ` with `s` and the Kelvin sign with `k`; a repeat over 100 is refused, and so is `[^]`.
Its public `startsWith` returns the shortest match, so a sticky match needs its anchored matcher.
In a debug build it stops on a string that is not UTF-8.

## Decision

- The port writes Pele's regexes as Pele writes them, through `src/nimaki/jsregex.nim`:
  `const RE_TITLE = jsre"/title([\t ][^\n\r]*|)/"`, then `RE_TITLE.exec(text)[1]`,
  `s.replace(re, "$1")`, `s.split(re)`, `re.matches(s)`, `re.exec(src, lastIndex)` for `g` and
  `y`. `newRegExp(source, flags)` is `new RegExp`; `jsre(pattern, flags)` is one built from
  constants.
- `jsregex.nim` translates a JavaScript pattern into the package's syntax with JavaScript's
  meaning (the classes spelled out as code point ranges, ASCII letters paired under `i`, line
  ends for `^`, `$` and `.`, a surrogate pair as one character outside the BMP, long repeats in
  pieces). A literal is translated at compile time: a pattern it cannot translate faithfully
  stops the build. It is compiled the first time it matches; a pattern made at run time once per
  pattern and flags.
- A hand-written scanner stays only where a regex cannot be faithful or would cost too much, it
  says why in its comment, and it is written once, in a shared module: the patterns that must see
  a lone surrogate (`util/url.nim`, `esc` in `svg/builder.nim`, sankey's check), the ones that run
  on every character of every text, and Pele's own scanners (a `scanner` in a token table is
  Pele's, not the port's).
- `render` and `detectType` read a byte that is not UTF-8 as U+FFFD, as TextDecoder does, so the
  renderer only works on UTF-8. This replaces the last point of decision 0011 (such a byte was
  dropped by `esc`, as Pele drops a lone surrogate): JavaScript strings cannot hold such a byte, so
  neither reading is a copy of Pele's, and this one lets regexes read every string.
- The package and its tables are pinned in `deps.lock`, like the docs' dependencies, and are the
  renderer's only dependency.

## Consequences

- The port reads closer to Pele line by line, and a new Pele release that changes a pattern is
  ported by copying it.
- What stays different, and cannot be translated: JavaScript reads UTF-16 code units, so a `.`
  or a negated class matches half of an emoji there and the whole emoji here; and a capture inside
  a repeated group keeps its last value here where JavaScript resets it (no pattern of Pele has
  one). `docs/divergences.md` says so.
- A regex costs more than a scanner (about 600 ns a try for a keyword against tens of ns), so
  the lexer-heavy types draw slower; the post *Regular expressions, as Pele writes them* has the
  numbers. Compiling every literal at compile time made the build 29 s slower and the JavaScript
  1 MB larger, which is why literals are compiled when first used.
