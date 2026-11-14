## port-of: src/diagrams/pie/model.ts
## port-status: draft
import std/tables
import ../../errors
import ../../js
import parser
import ../../jsregex

type PieModel* = ref object of RootObj
  title*, accTitle*, accDescr*: string   ## "" for undefined
  showData*: bool
  sections*: OrderedTable[string, float]

func dropLeadingSpaces(s: string): string =
  ## s.replace(/^\s+/g, '')
  jsTrimStart(s)

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc buildPie*(ast: PieAst, title: string): PieModel =
  var sections = initOrderedTable[string, float]()
  for section in ast.sections:
    if section.value < 0:
      raise newPeleError("\"" & section.label & "\" has invalid value: " & jsString(section.value) &
        ". Negative values are not allowed in pie charts. All slice values must be >= 0.",
        "semantic", ErrorInfo(diagramType: "pie"))
    if section.label notin sections: sections[section.label] = section.value
  PieModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": dropLeadingSpaces(ast.accTitle) else: "",
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "",
    showData: ast.showData,
    sections: sections)
