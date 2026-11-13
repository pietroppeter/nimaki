## nimaki: Pele, the Mermaid renderer, in Nim. `render(text, options)` is the entry point, as
## `render` of Pele's `src/core.ts` is (ported in `nimaki/core`).
##
## Each diagram type, as it is ported, registers itself here. A type Pele draws that nimaki has
## not ported yet raises a `PeleError` with code `unsupported`, which `tools/difftest.nim`
## counts as not ported.
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
import nimaki/diagrams/treemap/index as treemapIndex
import nimaki/diagrams/treeview/index as treeviewIndex
import nimaki/diagrams/class/index as classIndex
import nimaki/diagrams/er/index as erIndex
import nimaki/diagrams/requirement/index as requirementIndex
import nimaki/diagrams/git/index as gitIndex
import nimaki/diagrams/railroad/index as railroadIndex
import nimaki/diagrams/usecase/index as usecaseIndex
import nimaki/diagrams/gantt/index as ganttIndex

export core, errors, types, measurer

register(pieIndex.pie)
register(timelineIndex.timeline)
register(flowchartIndex.flowchart)
register(journeyIndex.journey)
register(infoIndex.info)
register(packetIndex.packet)
register(sequenceIndex.sequence)
register(stateIndex.state)
register(swimlaneIndex.swimlane)
register(ishikawaIndex.ishikawa)
register(cynefinIndex.cynefin)
register(wardleyIndex.wardley)
register(architectureIndex.architecture)
register(c4Index.c4)
register(blockIndex.blockDiagram)
register(radarIndex.radar)
register(treemapIndex.treemap)
register(treeviewIndex.treeView)
register(classIndex.classDiagram)
register(erIndex.er)
register(requirementIndex.requirement)
register(gitIndex.gitGraph)
register(railroadIndex.railroad)
register(usecaseIndex.usecase)
register(ganttIndex.gantt)
