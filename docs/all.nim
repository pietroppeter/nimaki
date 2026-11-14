## Builds every page in one program: `nim r docs/all.nim`.
## A page is a nimib notebook in docs/ or docs/devlog/; each renders when its module is
## initialised, in import order. A new page or post adds its name here (posts: one per line,
## sorted, so two branches adding a post rarely conflict).
{.warning[UnusedImport]: off.}
import index, roadmap, coverage, agents, decisions, porting, playground
import devlog/index as devlogIndex
import devlog/a_stage_for_a_port
import devlog/actors_and_use_cases
import devlog/agents_in_flows
import devlog/class_diagrams
import devlog/crows_feet
import devlog/diagrams_in_the_wild
import devlog/drawing_a_diagram
import devlog/first_light
import devlog/git_graphs
import devlog/railroad_diagrams
import devlog/gantt_charts
import devlog/diagrammari_as_a_corpus
import devlog/diagrammari_at_work
import devlog/following_pele
import devlog/every_drawing_a_test
import devlog/the_model_in_between
import devlog/nimaki_in_javascript
import devlog/drawn_in_your_browser
import devlog/how_pele_is_built
import devlog/lanes_and_handoffs
import devlog/layered_layout_and_flowchart
import devlog/mindmap_kanban_eventmodeling
import devlog/flows_and_quadrants
import devlog/pele_origins
import devlog/pomice
import devlog/radar_treemap_treeview
import devlog/states_and_regions
import devlog/the_diagram_family
import devlog/the_referee
import devlog/the_shape_of_the_port
import devlog/three_small_diagrams
import devlog/timeline
import devlog/what_a_label_holds
import devlog/what_mermaid_is
import devlog/lifelines_and_messages
import devlog/fishbones_and_domains
import devlog/maps_and_clouds
import devlog/boxes_in_boxes
import devlog/a_c_abi
import devlog/how_nimaki_reads_text
import devlog/opening_a_web_page
import devlog/a_kitchen_on_friday_night
import devlog/charts_on_two_axes
import devlog/circles_that_overlap
import devlog/a_proposal_for_diagrammari
import devlog/regular_expressions_as_pele_writes_them
import devlog/pele_tests_on_nimaki
import devlog/faster_in_javascript
