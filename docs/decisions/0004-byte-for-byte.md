---
title: The SVG is compared byte for byte, with the same text measurer
status: accepted
date: 2026-11-12
---

## Context

"Looks the same" is weak, and tests written by the same hand as the code share its blind spots.
Pele makes a promise that turns this into a machine check: its `AGENTS.md` says "Identical inputs
and text measurer must produce identical SVG". Rendering is synchronous, uses no DOM, and every
number goes through one formatter in `src/svg/builder.ts`.

## Decision

A part of the port is done when `tools/difftest.nim` finds the SVG of the Nim identical, byte for
byte, to the SVG of the oracle, on that part's corpus.

- Both sides use Pele's `metricsMeasurer` (font-metric tables, no canvas), which is what Pele
  uses in Node when no measurer is given. The Nim measurer is a port of it.
- The comparison is done with fixed options: `now` fixed for gantt, and the oracle runs with
  `TZ=UTC`, because gantt computes in local time.
- Errors are compared too: the error code and message Pele throws for a bad input.
- No fuzzy matching, no normalising of whitespace or numbers. Where identical output is
  impossible or pointless, the difference is a divergence and the comparison excludes exactly it.

## Consequences

- The Nim must reproduce details that look arbitrary: the order of attributes, of edges, of ids,
  JavaScript's number-to-string conversion, and UTF-16 lengths in the measurer.
- Any difference is a bug with a small reproduction, found by a machine, with the first differing
  byte shown.
- The harness is part of the product: it has a self test, and a change to it is reviewed like
  port code.
