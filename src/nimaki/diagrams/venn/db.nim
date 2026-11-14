## port-of: src/diagrams/venn/db.ts
## port-status: conformant
import std/[algorithm, sets, strutils, tables]
import ../../errors
import ../../js
import types

func normalizeText*(text: string): string =
  ## Mermaid takes one pair of quotes off an id, label or style value.
  let trimmed = jsTrim(text)
  if trimmed.len >= 2 and trimmed.startsWith('"') and trimmed.endsWith('"'): trimmed[1 ..< ^1] else: trimmed

func normalizeIds(ids: seq[string]): seq[string] =
  for id in ids: result.add normalizeText(id)
  result.sort(jsCompare)

type VennDb* = ref object of RootObj
  title*: string             ## "" for undefined
  subsets*: seq[VennSubset]
  textNodes*: seq[VennText]
  styles*: seq[VennStyle]
  known: HashSet[string]
  current: seq[string]
  hasCurrent: bool
  indent: bool               ## Whether an indented `text` line belongs to the set or union before it.

proc setDiagramTitle*(db: VennDb, title: string) = db.title = title

proc addSubsetData*(db: VennDb, ids: seq[string], label: string, hasLabel: bool, size: float, hasSize: bool) =
  ## A set without a size gets 10, and an overlap of n sets 10 / n².
  let sets = normalizeIds(ids)
  db.current = sets
  db.hasCurrent = true
  if sets.len == 1: db.known.incl sets[0]
  let n = float(ids.len)
  let labelled = hasLabel and label != ""
  db.subsets.add VennSubset(sets: sets, size: (if hasSize: size else: 10 / (n * n)),
                            label: (if labelled: normalizeText(label) else: ""), hasLabel: labelled)

proc addTextData*(db: VennDb, ids: seq[string], id: string, label: string, hasLabel: bool) =
  let labelled = hasLabel and label != ""
  db.textNodes.add VennText(sets: normalizeIds(ids), id: normalizeText(id),
                            label: (if labelled: normalizeText(label) else: ""), hasLabel: labelled)

proc addStyleData*(db: VennDb, ids: seq[string], data: seq[(string, string)]) =
  var styles = initOrderedTable[string, string]()
  for (key, value) in data: styles[key] = (if value != "": normalizeText(value) else: value)
  db.styles.add VennStyle(targets: normalizeIds(ids), styles: styles)

proc validateUnionIdentifiers*(db: VennDb, ids: seq[string]) =
  var unknown: seq[string]
  for id in ids:
    let n = normalizeText(id)
    if n notin db.known: unknown.add n
  if unknown.len > 0:
    raise newPeleError("unknown set identifier: " & unknown.join(", "), "semantic", "venn")

proc getCurrentSets*(db: VennDb): (bool, seq[string]) = (db.hasCurrent, db.current)
proc getIndentMode*(db: VennDb): bool = db.indent
proc setIndentMode*(db: VennDb, enabled: bool) = db.indent = enabled
