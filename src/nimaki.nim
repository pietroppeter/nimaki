## port-of: src/index.ts
## port-of: src/diagrams/registry.ts
## port-status: conformant
##
## nimaki: Pele, the Mermaid renderer, in Nim. `render(text, options)` is the entry point, as
## `render` of Pele's `src/core.ts` is (ported in `nimaki/core`).
##
## Every diagram type registers here, as Pele's `src/index.ts` registers the list `all` of
## `src/diagrams/registry.ts`. Pele also builds one module per type, loaded when first needed
## (`src/lazy.ts`, `src/entries/`); Nim imports at compile time, so a build chooses its types with
## `-d:nimakiTypes=...` (`nimaki/selection`), and the JavaScript build loads another build's
## types when a page needs them (`nimaki/web`). A type that is not registered raises Pele's
## `PeleError` for it, code `unsupported-diagram`.
import nimaki/[core, errors, types, version, selection]
import nimaki/text/measurer
when drawn("pie"): import nimaki/diagrams/pie/index as pieIndex
when drawn("timeline"): import nimaki/diagrams/timeline/index as timelineIndex
when drawn("flowchart"): import nimaki/diagrams/flowchart/index as flowchartIndex
when drawn("journey"): import nimaki/diagrams/journey/index as journeyIndex
when drawn("info"): import nimaki/diagrams/info/index as infoIndex
when drawn("packet"): import nimaki/diagrams/packet/index as packetIndex
when drawn("sequence"): import nimaki/diagrams/sequence/index as sequenceIndex
when drawn("state"): import nimaki/diagrams/state/index as stateIndex
when drawn("swimlane"): import nimaki/diagrams/swimlane/index as swimlaneIndex
when drawn("ishikawa"): import nimaki/diagrams/ishikawa/index as ishikawaIndex
when drawn("cynefin"): import nimaki/diagrams/cynefin/index as cynefinIndex
when drawn("wardley"): import nimaki/diagrams/wardley/index as wardleyIndex
when drawn("architecture"): import nimaki/diagrams/architecture/index as architectureIndex
when drawn("c4"): import nimaki/diagrams/c4/index as c4Index
when drawn("block"): import "nimaki/diagrams/block/index" as blockIndex
when drawn("radar"): import nimaki/diagrams/radar/index as radarIndex
when drawn("sankey"): import nimaki/diagrams/sankey/index as sankeyIndex
when drawn("quadrantChart"): import nimaki/diagrams/quadrant/index as quadrantIndex
when drawn("treemap"): import nimaki/diagrams/treemap/index as treemapIndex
when drawn("treeView"): import nimaki/diagrams/treeview/index as treeviewIndex
when drawn("mindmap"): import nimaki/diagrams/mindmap/index as mindmapIndex
when drawn("kanban"): import nimaki/diagrams/kanban/index as kanbanIndex
when drawn("eventmodeling"): import nimaki/diagrams/eventmodeling/index as eventmodelingIndex
when drawn("class"): import nimaki/diagrams/class/index as classIndex
when drawn("er"): import nimaki/diagrams/er/index as erIndex
when drawn("requirement"): import nimaki/diagrams/requirement/index as requirementIndex
when drawn("gitGraph"): import nimaki/diagrams/git/index as gitIndex
when drawn("railroad"): import nimaki/diagrams/railroad/index as railroadIndex
when drawn("usecase"): import nimaki/diagrams/usecase/index as usecaseIndex
when drawn("agentflow"): import nimaki/diagrams/agentflow/index as agentflowIndex
when drawn("gantt"): import nimaki/diagrams/gantt/index as ganttIndex
when drawn("xychart"): import nimaki/diagrams/xychart/index as xychartIndex
when drawn("venn"): import nimaki/diagrams/venn/index as vennIndex

export core, errors, types, measurer, version, selection

# In the order of Pele's `all` (src/diagrams/registry.ts).
when drawn("flowchart"): register(flowchartIndex.flowchart)
when drawn("pie"): register(pieIndex.pie)
when drawn("er"): register(erIndex.er)
when drawn("mindmap"): register(mindmapIndex.mindmap)
when drawn("kanban"): register(kanbanIndex.kanban)
when drawn("timeline"): register(timelineIndex.timeline)
when drawn("journey"): register(journeyIndex.journey)
when drawn("class"): register(classIndex.classDiagram)
when drawn("quadrantChart"): register(quadrantIndex.quadrantChart)
when drawn("xychart"): register(xychartIndex.xychart)
when drawn("state"): register(stateIndex.state)
when drawn("gantt"): register(ganttIndex.gantt)
when drawn("architecture"): register(architectureIndex.architecture)
when drawn("requirement"): register(requirementIndex.requirement)
when drawn("sankey"): register(sankeyIndex.sankey)
when drawn("packet"): register(packetIndex.packet)
when drawn("radar"): register(radarIndex.radar)
when drawn("treemap"): register(treemapIndex.treemap)
when drawn("info"): register(infoIndex.info)
when drawn("sequence"): register(sequenceIndex.sequence)
when drawn("gitGraph"): register(gitIndex.gitGraph)
when drawn("c4"): register(c4Index.c4)
when drawn("block"): register(blockIndex.blockDiagram)
when drawn("railroad"): register(railroadIndex.railroad)
when drawn("agentflow"): register(agentflowIndex.agentflow)
when drawn("treeView"): register(treeviewIndex.treeView)
when drawn("cynefin"): register(cynefinIndex.cynefin)
when drawn("wardley"): register(wardleyIndex.wardley)
when drawn("eventmodeling"): register(eventmodelingIndex.eventmodeling)
when drawn("usecase"): register(usecaseIndex.usecase)
when drawn("venn"): register(vennIndex.venn)
when drawn("ishikawa"): register(ishikawaIndex.ishikawa)
when drawn("swimlane"): register(swimlaneIndex.swimlane)
