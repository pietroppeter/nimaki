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
import nimaki/diagrams/journey/index as journeyIndex
import nimaki/diagrams/info/index as infoIndex
import nimaki/diagrams/packet/index as packetIndex

export core, errors, types, measurer

register(pieIndex.pie)
register(timelineIndex.timeline)
register(journeyIndex.journey)
register(infoIndex.info)
register(packetIndex.packet)
