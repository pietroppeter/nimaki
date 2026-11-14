---
title: One fast hash for both builds
status: accepted
date: 2026-11-14
---

## Context

Nim's `Table` and `HashSet` hash a string with farmhash and an integer with Wang Yi's mix by
default. Both multiply 64-bit integers. JavaScript has no 64-bit integers, so the JavaScript
build does those multiplications by hand, in pieces: hashing a 3,000-byte string took about 25
times longer than with murmur, which uses 32-bit arithmetic. Pele's stress tests that look up
long names (class namespaces, `classDef` lists, gantt's excluded days) spent most of their time
there.

Nim offers the other hashes through two defines, `nimStringHash2` (murmur for strings) and
`nimIntHash1` (an integer is its own hash). A define that applies only to the JavaScript build
cannot go in `nim.cfg`: Nim 2.2 reads the file before it knows the backend (`@if js:` and
`defined(js)` in a `config.nims` are both false there).

## Decision

`nim.cfg` defines `nimStringHash2` and `nimIntHash1` for every build, C and JavaScript.

## Consequences

- The JavaScript build hashes as fast as JavaScript allows, and both builds iterate a plain
  `Table` in the same order, since they hash alike.
- Nothing nimaki draws may depend on the order of a plain `Table` or `HashSet` anyway: Pele's
  `Map` and `Set` keep insertion order, which the port writes as `OrderedTable` and `OrderedSet`.
  The referee found all 2,234 cases identical in both builds with the new hashes.
- A program that imports nimaki with its own configuration keeps Nim's default hashes. It draws
  the same, but its JavaScript build is slower on large diagrams.
