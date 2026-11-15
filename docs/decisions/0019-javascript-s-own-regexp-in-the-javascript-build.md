---
title: JavaScript's own RegExp in the JavaScript build
status: accepted
date: 2026-11-15
---

## Context

Decision 0016 runs Pele's regular expressions on nitely's nim-regex, through `jsregex.nim`,
which translates each pattern into the library's syntax. In C it is fast. In the JavaScript
build the library is 30 to 50 times slower than in C, and JavaScript's own engine is faster
than both (post *Dates and styles in JavaScript*, 14 November 2026). Most of the time goes into
copies of the library's state that Nim's JavaScript build makes and the C build does not.

That post weighed four ways out: shortcuts in the wrapper, a patch kept in the vendored copy of
the library, a proposal to the library's author, and JavaScript's own RegExp in the JavaScript
build. Pietro chose the last, with a post proposing the patch upstream (15 November 2026).

## Decision

In the JavaScript build, `jsregex.nim` matches with JavaScript's `RegExp`, made from Pele's
pattern and flags as written, in a sticky and a global form. Its fast paths (a class run, plain
text, a literal prefix, the bytes a match can start with) still run first. The C build keeps
nim-regex and the translation.

nimaki's strings stay UTF-8 (decision 0011). A text becomes a JavaScript string once, and the
last four are kept with tables between byte offsets and UTF-16 positions, so a lexer that matches
one source thousands of times converts it once. The text of a match and of its groups comes back
as UTF-8.

## Consequences

- The JavaScript build matches as Pele does, with the engine Pele runs on: the differences
  `jsregex.nim` lists for the translation (a `.` and half of an emoji, a capture in a repeated
  group) remain in the C build only.
- The two builds run different engines. The referee, the fuzzers and Pele's own suites run both
  builds against Pele, so a difference between them shows up there.
- A pattern still has to translate for the C build, so `jsre` literals are checked at compile
  time as before.
- The cache takes a text to be the same when it is the same array of the same length: a text
  changed in place while it is being matched would not be converted again. The port does not do
  that.
