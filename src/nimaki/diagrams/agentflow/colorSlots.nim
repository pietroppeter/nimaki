## port-of: src/diagrams/agentflow/colorSlots.ts
## port-status: conformant
##
## Two rules, as in Mermaid: a node takes the color of its kind, from a fixed slot, so editing the
## diagram around it never recolors it; containers count through the slots above the kinds, in the
## order they were declared, so a frame does not take the color of a node inside it.
## `assignColorSlots` is written out where it is called, in `graph.nim`.

const KIND_SLOT* = [
  ("tool", 0),
  ("task", 1),
  ("decision", 2),
  ("input", 3),
  ("refdoc", 4),
  ("connector", 5),
  ("action", 6),
]

const KIND_COUNT* = KIND_SLOT.len

func kindSlot*(kind: string): int =
  ## The slot of a kind, -1 for none.
  for (k, s) in KIND_SLOT:
    if k == kind: return s
  -1

# At least one, so that a palette shorter than the kinds still gives containers a slot.
func containerSlotCount*(paletteLength: int): int = max(1, paletteLength - KIND_COUNT)

func containerSlot*(n, paletteLength: int): int =
  let slot = KIND_COUNT + (n mod containerSlotCount(paletteLength))
  if paletteLength > 0: slot mod paletteLength else: slot
