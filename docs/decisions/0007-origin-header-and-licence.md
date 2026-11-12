---
title: Ported files name their origin, and the port is MIT like Pele
status: accepted
date: 2026-11-12
---

## Context

Pele is MIT licensed, copyright (c) 2026 kepano. The Mermaid specs and grammars in its tests are
MIT too, copyright Knut Sveidqvist. A translation into Nim is a derivative work: MIT asks that the
copyright and permission notice are kept in copies and substantial portions. The repository was
created with an MIT licence.

## Decision

- Every Nim file that ports Pele code starts by naming the file it ports, relative to the Pele
  repository at the pin, and its state:

  ```nim
  ## port-of: src/diagrams/pie/parser.ts
  ## port-status: draft
  ```

  The same lines feed the port map (`tools/portmap.nim`), so the notice and the progress bar
  cannot drift apart.
- The repository is MIT. `NOTICE` keeps Pele's copyright and permission notice, and Mermaid's
  for the specs replayed from Pele's tests.
- Before reading closely or reusing anything else (another renderer, a corpus, a font table),
  check its licence and write it down in the post that uses it.

## Consequences

- One licence, the same as Pele's, keeps "may I copy this?" simple in both directions.
- The header tells ported files from original ones.
