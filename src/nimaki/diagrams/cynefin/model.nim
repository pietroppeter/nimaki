## port-of: src/diagrams/cynefin/model.ts
## port-status: draft
##
## Pele's `DomainBlock` and `Transition` inputs of `CynefinDb` are the parser's AST types.
import std/tables
import ../../js
import parser
import ../../jsregex

type
  CynefinDomain* = object
    name*: string
    items*: seq[string]          ## the labels of its items

  CynefinTransition* = object
    start*: string               ## Pele's `from`
    to*: string
    label*: string               ## "" for undefined

  CynefinModel* = ref object of RootObj
    title*, accTitle*, accDescr*: string   ## "" for undefined
    domains*: Table[string, CynefinDomain]
      ## The domains the source declares. All five are drawn either way.
    transitions*: seq[CynefinTransition]

func dropBreakSpaces(text: string): string =
  text.replace(jsre"/\n\s+/g", "\n")

proc buildCynefin*(ast: CynefinAst, title: string): CynefinModel =
  result = CynefinModel(
    title: (if ast.title != "": ast.title else: title),
    accTitle: (if ast.accTitle != "": jsTrimStart(ast.accTitle) else: ""),
    accDescr: (if ast.accDescr != "": dropBreakSpaces(ast.accDescr) else: ""))
  # A later block for a domain replaces an earlier one.
  for blk in ast.domains:
    result.domains[blk.domain] = CynefinDomain(name: blk.domain, items: blk.items)
  for t in ast.transitions:
    if t.start != t.to:
      result.transitions.add CynefinTransition(start: t.start, to: t.to, label: t.label)
