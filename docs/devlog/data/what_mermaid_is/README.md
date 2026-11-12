How the data of the post *What Mermaid is* was gathered, on 12 Nov 2026, from a clone of mermaid-js/mermaid.

- `diagram_firsts.tsv`: for every release tag, `git ls-tree` of `packages/mermaid/src/diagrams` (or `src/diagrams` before the monorepo); the first tag whose tree has the folder, with the tag's commit date. Folders renamed in 8.1.0 (sequenceDiagram, classDiagram, gitGraph) keep their first appearance under the old name.
- `grammars.tsv`: `.jison` files under `packages/mermaid/src/diagrams` and `.langium` files under `packages/parser/src/language` at tag `mermaid@12.1.0` (common.langium left out), plus the two types read otherwise (usecase, swimlanes), from their sources.
- `facts.json`: `git rev-list --count` and `git shortlog -sn` at `mermaid@12.1.0`; `git grep -c "getBBox()"` in `packages/mermaid/src`; stars from the GitHub search API; the seed round from TechCrunch, 20 March 2024.
