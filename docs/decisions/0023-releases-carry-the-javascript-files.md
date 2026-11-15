---
title: Releases carry the JavaScript files
status: accepted
date: 2026-11-15
---

## Context

A release of nimaki (decision 0020) is a tag: a Nim program requires it with nimble, and a
program in another language builds the C library from it. A page needs something else, the
JavaScript files that `tools/webbuild.nim` makes (decision 0022): `nimaki.js` with every type,
`nimaki-core.js` with none, and one `nimaki-<type>.js` per type, minified. Building them takes
Nim, Node and npm. The post *A type at a time* asked Pietro whether releases should carry them as
downloads, from 0.2.0 on; his answer, 15 November 2026: yes.

## Decision

1. **Every release carries the files**, from 0.2.0: each `.js` that `tools/webbuild.nim` writes,
   and one zip of them all, `nimaki-js-X.Y.Z.zip`.
2. **A workflow attaches them** (`.github/workflows/release.yml`): when a release is published it
   builds the files from the release's tag, checks them against Pele with `difftest --web` as CI
   does, and uploads them. Pietro publishes the release as before; nothing is uploaded by hand.
   A run by hand, with a tag, rebuilds the files of a release that exists already.

## Consequences

- A page, or diagrammari's client mode, can take nimaki's JavaScript from a release without
  building it, as it takes Pele's bundle from npm.
- A release whose files fail the check against Pele has no files, and the failed run says why:
  the files are fixed in a new patch release, not replaced on the old one.
- The files are built with the Nim of CI (2.2.14) and the esbuild of Pele's lock file, so they
  are the files the pages ship and CI checks.
