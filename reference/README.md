# reference

The Pele we are porting, pinned.

- `PIN` records the release: tag, commit, date, the npm package and its integrity hash, and the
  Mermaid version Pele follows. Everything in this repository (ported files, tests, line counts,
  explainers, the footer of every page) refers to this exact snapshot: Pele **1.13.0**.
- `fetch.sh` clones the source into `reference/pele/` and unpacks the published npm package into
  `reference/npm/package/`, after checking its integrity against `PIN`. Neither is committed.

The source is the specification. The package is the oracle: for any Mermaid input, the port is
right when it writes, byte for byte, the SVG that `render(text, options)` of the package writes in
Node, with the same text measurer (Pele's own `metricsMeasurer`, the default where there is no
canvas). `tools/difftest.nim` asks it through `tools/oracle.mjs`.

The npm package's `dist/pele.js` is byte-identical to the one `npm run build` makes from the
source at the pinned commit (checked on 12 November 2026), so the oracle and the source agree.

Pele is MIT licensed, copyright (c) 2026 kepano. Files ported from it keep a header that says
where they come from (`## port-of: src/...`), and `NOTICE` keeps the copyright.
