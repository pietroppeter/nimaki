---
title: This is a port, not a rewrite
status: accepted
date: 2026-11-12
---

## Context

The projects that changed language quickly and kept their behaviour (the Go compiler from C to Go,
TypeScript's compiler to Go, Ladybird's LibJS to Rust, Bun to Rust) translated the program they
had: same files, same functions, same data structures, same order of operations. gleam-in-nim,
Pietro's port of the Gleam compiler, works the same way and its notes are the starting point here.

## Decision

The Nim code mirrors the TypeScript of the pinned Pele snapshot.

- One TypeScript file, one Nim file, at the matching path: `src/diagrams/pie/parser.ts` is
  `src/nimaki/diagrams/pie/parser.nim`. Types, functions and fields keep their names.
- Same control flow and the same order of side effects, so a difference in output points to a
  line. Above all the same order of iteration, the same arithmetic and the same rounding: a
  layout that differs by one in the second decimal is a different SVG.
- Nim that reads like translated TypeScript is expected in this phase and is not a defect.
  Making it idiomatic is a later, separate change, file by file, once the file is `conformant`.
- Where Nim cannot say what TypeScript says (UTF-16 strings, regular expressions, `undefined`,
  structural types, closures over mutable state), the [porting guide](../porting/) has one agreed
  translation, and everyone uses it.

## Consequences

- A reviewer can put the two files side by side. So can a second agent, which is how we verify.
- We inherit Pele's architecture, including what we might have done differently.
- Improvements and new features are out of scope until the port is complete.
