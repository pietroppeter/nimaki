---
title: nimaki also builds with nim js
status: accepted
date: 2026-11-13
---

## Context

nimaki is a Nim port of Pele, compiled to C. Nim can also compile a program to JavaScript
(`nim js`), and the roadmap's `nimjs` step asks for the same renderer in a browser: Pele itself
runs there, and diagrammari draws in the reader's browser when Node is not around at build time.
A first `nim js` build of nimaki (13 November 2026) compiled with no change and drew most of the
corpus as Pele does; the rest failed on two ways of writing Nim that only the C backend runs.

## Decision

- `src/` must compile with `nim js` (with `-d:nodejs` for Node, without it for a browser), with
  the same source as for C: no `when defined(js)` in a ported file unless a record says why.
- `tools/difftest.nim --js` and `tools/fuzz.nim --js` compare Pele with the JavaScript build
  (`tools/jsrunner.nim`, run in Node with `TZ=UTC`). CI runs `difftest --js --check-done` on every
  pull request: a type marked done must be identical in both builds.
- The porting guide lists the code that only C can run, and how to write it instead.

## Consequences

- A port step that breaks the JavaScript build fails CI, like one that breaks the C build.
- The JavaScript build is not minified or packaged yet: a page that draws with it in the browser,
  and its size, are a later step.
