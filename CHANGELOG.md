# Changelog

Every release of nimaki, newest first. A version is `MAJOR.MINOR.PATCH` and its tag is
`vMAJOR.MINOR.PATCH`; how the numbers move, and what each release promises, is decision 0020
(*Versions and releases*, on the site's Decisions page). Each release says which Pele it draws as.

## 0.1.0 (15 November 2026)

The first release: every diagram type of Pele 1.13.0, ported to Nim and drawn byte for byte as
Pele draws it.

**Draws as:** Pele 1.13.0 (commit `3a2f075`, 30 October 2026), which draws the diagram types of
Mermaid 12.1.0. Nim 2.2.4 or later; the JavaScript build of large diagrams needs Nim 2.2.14.

### What it holds

- **All 33 diagram types of Pele**, from pie to agentflow. On the referee's 2,234 cases (Pele's
  corpus and compat inputs, 2,118, and diagrammari's Mermaid text, 116), nimaki's SVG is identical
  to Pele's run in Node, byte for byte, with the same text measurer, in both builds:
  - the **C build** (`nim c`), and
  - the **JavaScript build** (`nim js`), checked by `tools/difftest.nim --js`.
- **The fuzzer**: 120,500 mutated inputs over all 33 types and labels in the C build, and
  47,000 over 23 types in the JavaScript build, all identical to Pele.
- **Pele's own test suites** (6,992 tests) run on the JavaScript build: 6,949 pass. The rest are
  sorted, none failed: 25 call Pele's browser side, 12 meet only a time bound of Pele's (the
  JavaScript build is slower on stress tests), 1 tests the canvas measurer, 5 are known and
  explained in `tools/peletests/known.txt`.
- **The Nim API** (`import nimaki`): `render(text, options)`, `parse(text, options)`, which gives
  the model of a diagram, `render(model, options)`, `detectType`, `supports`, and `PeleError` with
  Pele's code, line, column and snippet. Models are in Pele's shape; on the corpus 1,745 of them
  are the same as Pele's `parse()` gives, 0 different (the other 373 inputs are errors in both).
- **The JavaScript entry point** `src/nimaki/web.nim`, for pages: `globalThis.nimaki.render`.
- **The C ABI** `src/nimaki/capi.nim` and `capi.h`, for other languages: `nimaki_render`,
  `nimaki_free`, `nimaki_pele_version` and the new `nimaki_version`, JSON in and JSON out, with
  the names diagrammari's runner of Pele uses. From Python it draws every case as Pele does.
- **The version in code**: `nimakiVersion`, `peleVersion`, `peleCommit` and `mermaidVersion`
  (`src/nimaki/version.nim`), exported by `nimaki`.
- **A nimble package**: `nimaki.nimble`, so that a project can `requires "nimaki == 0.1.0"`, or
  pin the tag with atlas. The renderer needs nitely's `regex` 0.27 and `unicodedb` 0.14, nothing
  else.

### What it does not hold

- **Pele's browser side**: `mount`, `enableZoom` and lazy loading. A page that needs them still
  loads Pele's own bundle. It is planned for a later release.
- **Pele's canvas measurer**: nimaki measures text with Pele's `metricsMeasurer` (font metrics
  tables, the measurer Pele uses in Node), not with a browser canvas.
- **Icons and math through the C ABI**: Pele takes them as callbacks; the Nim API has them, the C
  ABI does not yet.

### Known differences from Pele

Three, all at the edges of text, each explained in `docs/divergences.md` (on the site's Decisions
page): bytes that are not UTF-8 read as U+FFFD; a regular expression never stops inside an emoji;
a capture inside a repeated group keeps its last value. No case of the referee or the fuzzer
draws differently because of them.

### Good to know

- Every ported file is `conformant` (decision 0014), except `text/measurer.nim`, which ports only
  the metrics measurer and stays `draft`.
- nimaki's own `nim.cfg` picks Nim's faster hashes for the JavaScript build (decision 0017). A
  project that imports nimaki keeps its own configuration: it draws the same (all 2,234 cases were
  checked with Nim's default hashes for this release), but large diagrams are slower in its
  JavaScript build unless it adds `-d:nimStringHash2 -d:nimIntHash1`.
