# nimaki

[Pele](https://github.com/obsidianmd/pele), the Mermaid renderer by Steph Ango and Obsidian,
ported to [Nim](https://nim-lang.org) one explained step at a time. Mermaid text in, themeable
SVG out, checked byte for byte against Pele itself.

**Site:** https://pietroppeter.github.io/nimaki/ (devlog, roadmap, coverage map, decisions).

- The snapshot being ported is pinned in [`reference/PIN`](reference/PIN): Pele 1.13.0
  (commit `3a2f075`).
- The working rules, for people and coding agents: [`AGENTS.md`](AGENTS.md).
- Get started: `sh tools/setup.sh`, then `nim r docs/all.nim` to build the pages.

## Use it

The latest release is **0.2.0** ([`CHANGELOG.md`](CHANGELOG.md)): every diagram type of Pele
1.13.0, identical to Pele byte for byte, in the C and JavaScript builds, with Pele's browser side
(`mount`, zoom) in the JavaScript build and Pele's models as JSON. In a nimble file:

```nim
requires "nimaki == 0.2.0"
```

```nim
import nimaki
writeFile "pets.svg", render("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85").svg
```

In a page, `src/nimaki/web.nim` compiled with `nim js` gives `nimaki.render`, `nimaki.mount`
and the rest of Pele's browser functions under the name `nimaki`; from other languages, the C
ABI (`src/nimaki/capi.h`) gives `nimaki_render` and `nimaki_parse`.

## The name

In Hawaiian stories Nāmaka is a goddess of the sea and Pele's older sister. When Pele dug her
fire pits down the island chain, Nāmaka's sea followed. nimaki is Nim plus Nāmaka: the sea once
more, after Mermaid, Pele and [mari](https://github.com/pietroppeter/diagrammari). It is an
independent port, made to learn, with every respect for Pele and its author: nimaki exists
because Pele was written first, and written well.

## Licence

MIT, like Pele. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE), which keeps Pele's copyright.
This project is not affiliated with Obsidian, Pele or Mermaid.
