## port-of: src/diagrams/venn/types.ts
## port-status: conformant
##
## JavaScript's `undefined` for a label is `none`: a label can also be "".
import std/[tables, options]

type
  VennSubset* = object
    ## A set (one id) or an overlap of sets (two or more ids, sorted), with its relative area.
    sets*: seq[string]
    size*: float
    label*: Option[string]

  VennText* = object
    ## A line of text shown inside the region of the given sets.
    sets*: seq[string]
    id*: string
    label*: Option[string]

  VennStyle* = object
    ## Targets are the sorted ids of a set or overlap, or the id of a text.
    targets*: seq[string]
    styles*: OrderedTable[string, string]
