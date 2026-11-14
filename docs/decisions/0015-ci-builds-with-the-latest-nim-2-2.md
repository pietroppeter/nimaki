---
title: CI builds with the latest Nim 2.2 release
status: accepted
date: 2026-11-14
---

## Context

CI installed Nim 2.2.4, while the sandboxes where the port is written download the newest build of
the 2.2 branch (`tools/setup.sh`, `latest-version-2-2`). The two differ where it matters for the
JavaScript build (decision 0013). In 2.2.4, appending one string to another compiles to
`a.push.apply(a, b)`, which passes every byte of `b` as an argument: past about a hundred thousand
bytes JavaScript's stack overflows. Pele's stress tests (`tools/peletests.nim`) draw diagrams that
large, and on 14 November 2026 44 of them failed in CI on that alone, while they passed in the
sandbox. Nim 2.2.14, the latest 2.2 release, appends in a loop. It was checked locally on the whole
referee: tests, difftest in C, in JavaScript and with the test host, the pages, and Pele's suites.
The multiplication that lost bits in 2.2.4's JavaScript (`imul` in `diagrams/cynefin/boundaries.nim`)
keeps its workaround, which is correct with any version.

## Decision

- CI installs Nim 2.2.14, the latest release of the 2.2 branch, and moves to a later 2.2 release
  in a pull request of its own, after the same checks.
- The sandboxes keep the newest 2.2 build; a difference between the two that changes an answer is
  a bug to report in the porting guide, as the two found so far are.

## Consequences

- nimaki's JavaScript build needs Nim 2.2.14 or later to draw large diagrams; with 2.2.4 it fails
  on output past about 100 KB.
- The cache of compiled Nim in CI is keyed by the version, so the first run after a change
  compiles everything again.
