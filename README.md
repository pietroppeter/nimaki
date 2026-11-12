# nimaki

[Pele](https://github.com/obsidianmd/pele), the Mermaid renderer by Steph Ango and Obsidian,
ported to [Nim](https://nim-lang.org) one explained step at a time. Mermaid text in, themeable
SVG out, checked byte for byte against Pele itself.

**Site:** https://pietroppeter.github.io/nimaki/ (devlog, roadmap, coverage map, decisions).

- The snapshot being ported is pinned in [`reference/PIN`](reference/PIN): Pele 1.13.0
  (commit `3a2f075`).
- The working rules, for people and coding agents: [`AGENTS.md`](AGENTS.md).
- Get started: `sh tools/setup.sh`, then `nim r docs/all.nim` to build the pages.

## The name

In Hawaiian stories Nāmaka is a goddess of the sea and Pele's older sister. When Pele dug her
fire pits down the island chain, Nāmaka's sea followed. nimaki is Nim plus Nāmaka: the sea once
more, after Mermaid, Pele and [mari](https://github.com/pietroppeter/diagrammari). It is an
independent port, made to learn, with every respect for Pele and its author: nimaki exists
because Pele was written first, and written well.

## Licence

MIT, like Pele. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE), which keeps Pele's copyright.
This project is not affiliated with Obsidian, Pele or Mermaid.
