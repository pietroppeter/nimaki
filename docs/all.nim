## Builds every page in one program: `nim r docs/all.nim`.
## A page is a nimib notebook in docs/ or docs/devlog/; each renders when its module is
## initialised, in import order. A new page or post adds its name here (posts: one per line,
## sorted, so two branches adding a post rarely conflict).
{.warning[UnusedImport]: off.}
import index, roadmap, coverage, agents, decisions, porting
import devlog/index as devlogIndex
import devlog/a_stage_for_a_port
import devlog/class_diagrams
import devlog/diagrams_in_the_wild
import devlog/drawing_a_diagram
import devlog/first_light
import devlog/how_pele_is_built
import devlog/lanes_and_handoffs
import devlog/layered_layout_and_flowchart
import devlog/pele_origins
import devlog/pomice
import devlog/radar_treemap_treeview
import devlog/states_and_regions
import devlog/the_diagram_family
import devlog/the_referee
import devlog/three_small_diagrams
import devlog/timeline
import devlog/what_mermaid_is
import devlog/lifelines_and_messages
