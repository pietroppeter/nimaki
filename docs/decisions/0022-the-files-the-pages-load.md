---
title: The files the pages load
status: accepted
date: 2026-11-15
---

## Context

nimaki's JavaScript build, the file a page loads to draw (`src/nimaki/web.nim`), was one file of
9.9 MB, 1.4 MB compressed, five times Pele's bundle (post *Why nimaki.js is big*). Most of it was
long names and white space, which Nim writes and a minifier removes, and every diagram type was
in it, where Pele lets a page load one type at a time. Pietro wanted it small enough for
diagrammari's client mode before the 0.2 release (15 November 2026).

## Decision

1. **The browser's own URL parser.** The JavaScript build calls `new URL()`, as Pele does, where
   the C build runs the port of ada's IDNA (`src/nimaki/util/url.nim`). As with the regular
   expressions (decision 0019), the engine is the one Pele itself runs on.
2. **One build per set of types.** `-d:nimakiTypes=<types>` (`src/nimaki/selection.nim`, Pele's
   type names, comma-separated, default `all`, `none` for the core alone) chooses what a build
   draws. A type left out raises Pele's own error for a type that is not loaded
   (`unsupported-diagram`, `Diagram type "x" is not supported yet.`), which replaces nimaki's
   old `unsupported` code.
3. **Builds join on a page.** The first build that runs makes `globalThis.nimaki`; a later one
   joins it, and `render`, `parse` and `mount` go to the build that draws the text's type.
   `load(type)` adds `nimaki-<type>.js` from the folder of the first build's script: Pele's lazy
   loading (`src/lazy.ts`), with files instead of modules.
4. **The files.** `tools/webbuild.nim` builds `nimaki.js` (every type), `nimaki-core.js` (none)
   and `nimaki-<type>.js` for each type, with `-d:danger`, and minifies each with the esbuild of
   Pele's lock file, with Pele's settings and `--format=iife`. Without npm or the network the
   files stay unminified. The pages load `nimaki-core.js` and then the types they draw.
5. **The referee checks the files that ship.** The JavaScript tools build with `-d:danger`, as
   the pages do, and `difftest --web` compares the minified files with Pele, loaded in Node as a
   page loads them: `nimaki.js` alone, and the core with every type's file together.

## Consequences

- A page of flowcharts loads one file of the core and the flowchart; the four types diagrammari
  writes fit in one build smaller, compressed, than Pele's bundle (post *A type at a time*).
- The pages' build needs npm for esbuild, one more tool beside Node, which the referee needs
  already. A project that builds nimaki's JavaScript itself (diagrammari) can use
  `-d:nimakiTypes` without esbuild, and minify if it wants.
- Each file carries its own copy of the shared core, so a page with many types loads the core
  several times; one build with those types (`-d:nimakiTypes=a,b,c`) avoids it.
- The C build is unchanged.
