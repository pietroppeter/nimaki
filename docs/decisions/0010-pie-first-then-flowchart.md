---
title: Pie first, then flowchart
status: accepted
date: 2026-11-12
---

## Context

The first brief proposed the shared core with pie and timeline; the second suggested flowchart,
whose layered layout many other types reuse. Pie is the smallest type (about 330 lines) and uses
no graph layout, but it needs the whole chain under it: the text measurer, the SVG builder, the
palette and theme, `render()` and the difftest harness.

## Decision

The first diagram type is pie: it proves the chain end to end, byte for byte, with the least code
in the way. Flowchart comes next, with the layered layout it needs. Pietro agreed on 12 November
2026.

## Consequences

- The first milestone is small and fully checkable: one type identical to Pele on its corpus.
- The layered layout (about 3,400 lines in `src/layout/`) starts in phase 2, with flowchart as
  its first user; sequence follows, and with these diagrammari's common types need no Node.
