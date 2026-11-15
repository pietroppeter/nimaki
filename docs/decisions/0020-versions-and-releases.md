---
title: Versions and releases
status: accepted
date: 2026-11-15
---

## Context

By 15 November 2026 nimaki drew every diagram type of Pele 1.13.0 as Pele does, in its C and
JavaScript builds, and diagrammari's proposal (post *A proposal for diagrammari*, 14 November)
named a tag of nimaki as the first thing it needs before it can depend on it. There had been no
tag. A version number had to be chosen, and two readings were possible: nimaki's own numbers,
or numbers that follow Pele's (1.13.0, or 1.13.0 with a suffix). Pietro chose 0.1.0 for the first
release (15 November 2026).

A Nim package is found by nimble and atlas through a `.nimble` file at the root of the
repository, which nimaki did not have, and an installed package holds only its `srcDir`: the C
ABI read Pele's version from `reference/PIN`, outside `src/`, so it would not have compiled from
an installed package.

## Decision

- **nimaki numbers its own releases**, `MAJOR.MINOR.PATCH` after semantic versioning, starting at
  0.1.0. The Pele a release draws as is not in the number; it is in `src/nimaki/version.nim`
  (`peleVersion`, `peleCommit`, `mermaidVersion`), in `nimaki_pele_version()` of the C ABI, and in
  the release's notes.
- While the version is 0.x, a **minor** release (0.2.0) is any release that moves the Pele pin
  (its drawings change with Pele's) or changes the API; a **patch** release (0.1.1) fixes the port
  without moving the pin. 1.0.0 is for when the API is meant to stay, which is Pietro's call.
- The **tag** is `v` and the version (`v0.1.0`), on a commit of `main` where CI is green. Tags
  and GitHub releases wait for Pietro: he names the version, then the tag is pushed and the
  release published, its notes taken from the release's section of `CHANGELOG.md`.
- **One version, four places**: `nimaki.nimble`, `nimakiVersion` in `src/nimaki/version.nim`, a
  section of `CHANGELOG.md`, and the tag. `tests/test_version.nim` fails when the first three do
  not agree, or when `version.nim` and `reference/PIN` name different Pele.
- **Before a tag, `nim r tools/installcheck.nim` passes**: nimble installs the checkout into a
  directory of its own, a program outside the repository draws every case of the corpus with only
  that package on its path (none of nimaki's `nim.cfg`), and the drawings are Pele's, byte for
  byte; the JavaScript entry point and the C ABI of the installed package compile.
- **What `src/` reads stays in `src/`**: nothing the renderer, the JavaScript entry point or the
  C ABI compile may read files outside `src/`, so an installed package builds.
- **Dependencies in `nimaki.nimble` are the minor versions of `deps.lock`**: `regex` 0.27 and
  `unicodedb` 0.14, where the referee checked every case. A new minor version of either moves in a
  pull request after the same checks, as a new Nim does (decision 0015).

## Consequences

- diagrammari, or any project, can `requires "nimaki == 0.1.0"` in its nimble file, or pin the tag
  in atlas, as its proposal planned.
- The pin can move (roadmap step *follow-pele*) without waiting for a 1.0: each move is a minor
  release, and the notes say which Pele it draws as.
- A release adds a section to `CHANGELOG.md`, bumps the two version fields, and gets a devlog
  post when it holds a big step; the first release has one (*nimaki 0.1.0*).
