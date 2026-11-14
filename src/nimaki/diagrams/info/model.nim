## port-of: src/diagrams/info/model.ts
## port-status: draft
import ../../js
import parser
import ../../jsregex

type InfoModel* = ref object of RootObj
  title*, accTitle*, accDescr*: string   ## "" for undefined

func collapseIndents(s: string): string =
  s.replace(jsre"/\n\s+/g", "\n")

proc buildInfo*(ast: InfoAst, title: string): InfoModel =
  InfoModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": jsTrimStart(ast.accTitle) else: "",   # replace(/^\s+/g, '')
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "")
