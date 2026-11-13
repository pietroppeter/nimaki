---
title: JavaScript's Date is a time value in Nim, local time is UTC, and its parser is V8's
status: accepted
date: 2026-11-13
---

## Context

Gantt charts compute with dates the way JavaScript does: `new Date(y, m, d)`, `setDate`,
`setMonth` and their overflow rules, local time, and, when a start date does not fit the chart's
`dateFormat`, `new Date(text)`, whose rules for anything but ISO 8601 are not in the language
specification but in each engine. Nim's `std/times` has its own rules for all of these. The
referee runs Pele in Node with `TZ=UTC` (decision 0004, `tools/oracle.mjs`), so Pele's local time
is UTC in every comparison.

## Decision

- A JavaScript `Date` is its time value, a `float` of milliseconds since 1970, NaN when invalid
  (`JsDate` in `src/nimaki/jsdate.nim`). Constructors, getters and setters follow ECMAScript's
  algorithms (MakeDay, MakeTime, TimeClip...). A setter returns the new value instead of changing
  a date in place.
- Local time is UTC: the local getters and setters are the UTC ones and `getTimezoneOffset` is 0.
  nimaki draws what Pele draws in UTC, wherever it runs.
- `parseDate` (for `new Date(text)`) follows V8's date parser, since Node is the oracle: ISO 8601
  first, then the legacy forms (`Jan 5, 2026`, `1/5/2026 10:00 PM`...), with its quirks (a missing
  year is 2001).
- `tests/test_jsdate.nim` checks parsing and calendar arithmetic against Node on thousands of
  inputs.

## Consequences

- A chart that depends on a time zone (a task at local midnight, a daylight saving change) draws
  as Pele draws it in UTC, not as it would in the reader's zone. If a host ever needs another
  zone, local time becomes a parameter of `jsdate.nim`, with a new record.
- Another engine's `Date` parser (Firefox's, Safari's) may read the same text differently; the
  port follows V8 only.
