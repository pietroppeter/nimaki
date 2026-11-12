## Builds every page in one program: `nim r docs/all.nim`.
## A page is a nimib notebook in docs/ or docs/devlog/; each renders when its module is
## initialised, in import order. A new page or post adds its name here (posts: one per line,
## sorted, so two branches adding a post rarely conflict).
{.warning[UnusedImport]: off.}
import index, roadmap, coverage, agents, decisions, porting
import devlog/index as devlogIndex
import devlog/a_stage_for_a_port
import devlog/diagrams_in_the_wild
import devlog/pele_origins
import devlog/the_diagram_family
import devlog/what_mermaid_is
