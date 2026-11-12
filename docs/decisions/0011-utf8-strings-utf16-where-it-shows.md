---
title: Strings stay UTF-8; JavaScript's UTF-16 is counted only where it shows
status: accepted
date: 2026-11-12
---

## Context

JavaScript strings are sequences of 16-bit code units (UTF-16): `length`, `charCodeAt`,
`slice` and every index count units, and a character outside the Basic Multilingual Plane (an
emoji, say) is two of them. Nim strings are bytes, and the bytes are UTF-8. Pele reads its input
with `charCodeAt` in its lexers and its text measurer, and indexes strings throughout. The port
has to choose once: carry JavaScript's strings over (a sequence of `uint16` everywhere, or a
string type of our own), or keep Nim's strings and copy UTF-16 only where the difference reaches
the output. The research thread leaned to the second; the first port (the core and pie) tried
it.

## Decision

- Strings stay Nim strings, UTF-8. Indexes inside the port are byte offsets.
- Where a count or a code unit of UTF-16 shows in Pele's output, the port computes it from the
  UTF-8 bytes with the helpers of `src/nimaki/js.nim`: `utf16Len` (a `length` that is compared
  or printed: the input and output limits), `codeUnits` (a loop over `charCodeAt`: the metrics
  measurer), and the column of an error, turned into UTF-16 units by `locate` in `errors.nim`.
- Tests on characters that a regular expression of Pele makes (`\s`, `[^\n\r]`, a range of
  CJK code points) read whole code points (`codePointAt`), never single bytes, when the
  character can be outside ASCII.
- A byte that is not valid UTF-8 reads as U+FFFD, as a `TextDecoder` would make it, and `esc`
  drops it, as Pele drops a lone surrogate. JavaScript strings cannot hold such a byte, so this is
  the nearest behaviour, not a copy of one.

## Consequences

- Most of the port reads like ordinary Nim, and the standard library's string procs work.
  Every place that counts UTF-16 calls a helper with that name in it, so the places are easy to
  find.
- A position inside a multi-byte character is a byte offset here and a unit offset in Pele. It
  does not show while positions are only compared with each other; it does where one is printed
  (an error column), and there the port converts. A later type that prints or compares a raw
  index must convert too: the porting guide says so.
- The pie corpus and more than 20,000 generated pie inputs (labels in Japanese, Korean, combining marks
  and emoji among them, and error messages that point into them) are identical to Pele.
