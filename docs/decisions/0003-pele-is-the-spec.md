---
title: Pele at the pin is the specification, and its npm package is the oracle
status: accepted
date: 2026-11-12
---

## Context

Pele 1.13.0 (commit `3a2f075`, 30 October 2026) is the newest release on 12 November 2026, on
GitHub and on npm. It is about 47,600 lines of TypeScript (code, without comments and blank
lines) with about 55,000 lines of tests: Mermaid's own specs ported per type in `tests/compat/`,
render and layout tests, and 34 corpus files with 761 documented diagrams. Writing a second
description of the same behaviour would be slower than the port and would be wrong in places.

## Decision

- The specification is Pele at the pin (`reference/PIN`): its source, its tests, and what its
  published package draws. When they disagree with anything we wrote, they win.
- The oracle is the npm package `pele@1.13.0`, checked against the integrity hash in `PIN`, run
  in Node by `tools/oracle.mjs`. Its `dist/pele.js` is byte-identical to the one `npm run build`
  makes from the source at the pinned commit (checked on 12 November 2026), so the package and
  the source agree.
- No separate behaviour specification. Pele's tests and corpus are replayed, not retyped.
- Every place where the Nim knowingly differs from Pele is one entry in
  `docs/divergences.md`, with the reason. Nothing else may differ.

## Consequences

- "Is this right?" always has an answer that needs no person: run the oracle.
- The pin does not move during the port. Following Pele's releases later is a separate step
  (a diff-and-port routine) with its own record.
- The pin is shown in the footer of every page, read from `reference/PIN`.
