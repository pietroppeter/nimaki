---
title: A model is Pele's, field for field, or says how it differs
status: accepted
date: 2026-11-14
---

## Context

`parse(text)` returns a diagram's model, as Pele's does, and Pele's tests read it
(`parse(text).nodes.get("A").label`). `tools/parsediff.nim` compares nimaki's models with Pele's,
and `tools/peletests/bridge.nim` hands nimaki's models to Pele's tests, both through the JSON that
`tools/models.nim` writes. When the roadmap step *Models as Pele's* started, most types differed,
in a few recurring ways: a field Pele leaves undefined held as a stand-in value with a flag beside
it; a union of shapes held as one object with a kind; a field of the port's own (an index, a
cache); an object Pele spreads into another; a value boxed for speed.

Each could be fixed in the model, or in the writing of it. A later session could choose either,
type by type, and end with a mixture nobody can read.

## Decision

1. **An optional field of Pele's is an `Option`** in the model (`columns: Option[float]`), not a
   stand-in value with a flag. This is the first choice, whenever the readers of the field are few.
2. **The type says what is the port's own**, with the pragmas of `src/nimaki/model.nim`:
   `{.portOnly.}` for a field Pele's model does not have (left out of the JSON), `{.spread.}` for
   an object whose fields Pele's model has as its own, `{.undefinedIfEmpty.}` for a text that is
   `""` where Pele's is undefined. A model's own `title`, `accTitle` and `accDescr` are read so in
   every type whose Pele never holds them as `""` (all but usecase), without the pragma: changing
   them to `Option` in 33 types would touch every drawing for nothing a drawing shows.
3. **Where the port holds a value in a shape of its own on purpose** (a union as one object with a
   kind, which Nim cannot write with the same field name in two branches; a boxed string shared for
   speed; a label with a "defined" flag read in many places), `tools/models.nim` has a `dump`
   overload for that type, which writes Pele's shape, with a comment saying why.
4. **Names**: a field named after a Nim keyword (`kind` or `typ` for `type`, `stop` for `end`,
   `start` for `from`) is renamed by `tools/models.nim`, by the general table or the table of one
   type.
5. The referee compares values; an empty text and a missing one are the same to it, unless it runs
   with `--strict`. Pele's tests see the difference: where one fails on it, the field becomes an
   `Option` or gets `{.undefinedIfEmpty.}`.

## Consequences

- A model's type shows where it differs from Pele's, and `tools/models.nim` holds every mapping
  that is not a rename, each with its reason.
- A model is the same as Pele's when `tools/parsediff.nim` finds it so; a test of Pele's that
  reads a model of a type not yet the same is counted apart (`model`) by `tools/peletests.nim`.
- Changing a field to an `Option` touches its readers in the drawing: difftest must stay identical,
  in C and in JavaScript.
