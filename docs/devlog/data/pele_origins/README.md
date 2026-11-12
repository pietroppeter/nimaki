How the data of the post *Pele, a volcano in four weeks* was gathered, on 12 Nov 2026.

- `npm_releases.tsv`: `https://registry.npmjs.org/pele`, field `time` (1.0.0 of 2020 left out: it is an unrelated package that held the name before).
- `commits_per_day.tsv`, `contributors.tsv`: `git log` and `git shortlog -sn` of obsidianmd/pele at commit 3a2f075 (tag 1.13.0).
- `facts.json` `tests`: file and line counts of `tests/` at 3a2f075; `corpus_diagrams` is the total length of the 34 arrays in `tests/corpus/*.json`; `skipped_cases` counts the `- ` lines of `tests/compat/*/SKIPPED.md`.
- `facts.json` `claims`: pele.run home page (`website/src/content/pages/index.md` at 3a2f075). They are Pele's claims, not our measurements.
- `mermaid_cves.tsv`: releasealert.dev's CVE list for mermaid, checked against the GitLab advisory pages for the 2025 entries.
