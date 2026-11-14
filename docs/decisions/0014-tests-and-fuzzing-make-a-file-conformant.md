---
title: Tests and fuzzing make a file conformant, without a second reading
status: accepted
date: 2026-11-14
---

## Context

Decision 0005 moves a ported file through three states: `draft` when translated, `verified` when a
second pass with fresh context has read it against the TypeScript, and `conformant` when Pele's
tests pass on it and difftest finds its part identical. On 14 November 2026 all 221 ported files
still said `draft`. Meanwhile the referee had grown: difftest compares every case of the corpus in
the C and the JavaScript builds, a fuzzer per type and one for labels run thousands of random
diagrams in CI, and the test host draws icons and math on both sides. A second reading of nearly 43,000
lines would cost more than the rest of the checks together, and what it looks for (a behaviour that
differs from Pele's) is what those checks already measure, on real output. Asked whether tests and
fuzzing are enough to call a file conformant without a second reading, Pietro answered yes
(14 November 2026).

## Decision

- This record supersedes the `verified` step of decision 0005. A second reading is no longer
  required; a file goes from `draft` to `conformant` when:
  1. difftest finds the part it belongs to identical to Pele, in both builds, and that part's
     fuzzer finds no difference;
  2. the tests of Pele's suites that reach it (the step *Run Pele's own test suites*) pass on the
     port, or a divergence in `docs/divergences.md` says why one does not.
- `verified` stays a valid status, for a file that was read a second time but is not covered by
  tests yet. No step has to produce it.
- A file that no test and no fuzzer reaches stays `draft`, and the port map shows it.

## Consequences

- The roadmap step *Past draft: verified and conformant* is done by this record; the step *Run
  Pele's own test suites* moves the files it covers to `conformant`.
- The porting guide and the port map describe the states this way.
- A difference found later in a `conformant` file is fixed and gets a case in the corpus or a
  fuzzer, so the check that missed it no longer can.
