## port-of: src/index.ts
## port-of: src/diagrams/registry.ts
## port-status: conformant
##
## nimaki: Pele, the Mermaid renderer, in Nim. `render(text, options)` is the entry point, as
## `render` of Pele's `src/core.ts` is (ported in `nimaki/core`).
##
## Every diagram type registers here, as Pele's `src/index.ts` registers the list `all` of
## `src/diagrams/registry.ts`. Pele also builds one module per type, loaded when first needed
## (`src/lazy.ts`, `src/entries/`); Nim imports at compile time, so the port has no counterpart
## (docs/data/portmap_skip.txt). A type that is not registered raises a `PeleError` with code
## `unsupported`.
import nimaki/[core, errors, types]
import nimaki/text/measurer
import nimaki/diagrams/pie/index as pieIndex
import nimaki/diagrams/timeline/index as timelineIndex
import nimaki/diagrams/flowchart/index as flowchartIndex
import nimaki/diagrams/journey/index as journeyIndex
import nimaki/diagrams/info/index as infoIndex
import nimaki/diagrams/packet/index as packetIndex
import nimaki/diagrams/sequence/index as sequenceIndex
import nimaki/diagrams/state/index as stateIndex
import nimaki/diagrams/swimlane/index as swimlaneIndex
import nimaki/diagrams/ishikawa/index as ishikawaIndex
import nimaki/diagrams/cynefin/index as cynefinIndex
import nimaki/diagrams/wardley/index as wardleyIndex
import nimaki/diagrams/architecture/index as architectureIndex
import nimaki/diagrams/c4/index as c4Index
import "nimaki/diagrams/block/index" as blockIndex
import nimaki/diagrams/radar/index as radarIndex
import nimaki/diagrams/sankey/index as sankeyIndex
import nimaki/diagrams/quadrant/index as quadrantIndex
import nimaki/diagrams/treemap/index as treemapIndex
import nimaki/diagrams/treeview/index as treeviewIndex
import nimaki/diagrams/mindmap/index as mindmapIndex
import nimaki/diagrams/kanban/index as kanbanIndex
import nimaki/diagrams/eventmodeling/index as eventmodelingIndex
import nimaki/diagrams/class/index as classIndex
import nimaki/diagrams/er/index as erIndex
import nimaki/diagrams/requirement/index as requirementIndex
import nimaki/diagrams/git/index as gitIndex
import nimaki/diagrams/railroad/index as railroadIndex
import nimaki/diagrams/usecase/index as usecaseIndex
import nimaki/diagrams/agentflow/index as agentflowIndex
import nimaki/diagrams/gantt/index as ganttIndex
import nimaki/diagrams/xychart/index as xychartIndex
import nimaki/diagrams/venn/index as vennIndex

export core, errors, types, measurer

# In the order of Pele's `all` (src/diagrams/registry.ts).
register(flowchartIndex.flowchart)
register(pieIndex.pie)
register(erIndex.er)
register(mindmapIndex.mindmap)
register(kanbanIndex.kanban)
register(timelineIndex.timeline)
register(journeyIndex.journey)
register(classIndex.classDiagram)
register(quadrantIndex.quadrantChart)
register(xychartIndex.xychart)
register(stateIndex.state)
register(ganttIndex.gantt)
register(architectureIndex.architecture)
register(requirementIndex.requirement)
register(sankeyIndex.sankey)
register(packetIndex.packet)
register(radarIndex.radar)
register(treemapIndex.treemap)
register(infoIndex.info)
register(sequenceIndex.sequence)
register(gitIndex.gitGraph)
register(c4Index.c4)
register(blockIndex.blockDiagram)
register(railroadIndex.railroad)
register(agentflowIndex.agentflow)
register(treeviewIndex.treeView)
register(cynefinIndex.cynefin)
register(wardleyIndex.wardley)
register(eventmodelingIndex.eventmodeling)
register(usecaseIndex.usecase)
register(vennIndex.venn)
register(ishikawaIndex.ishikawa)
register(swimlaneIndex.swimlane)
