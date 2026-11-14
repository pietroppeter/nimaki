## port-of: src/diagrams/info/model.ts
## port-status: conformant
import ../../js
import parser

type InfoModel* = ref object of RootObj
  title*, accTitle*, accDescr*: string   ## "" for undefined

func collapseIndents(s: string): string =
  ## s.replace(/\n\s+/g, '\n')
  var i = 0
  while i < s.len:
    if s[i] == '\n' and spaceLenAt(s, i + 1) > 0:
      result.add '\n'
      i += 1
      while true:
        let n = spaceLenAt(s, i)
        if n == 0: break
        i += n
      continue
    result.add s[i]
    inc i

proc buildInfo*(ast: InfoAst, title: string): InfoModel =
  InfoModel(
    title: if ast.title != "": ast.title else: title,
    accTitle: if ast.accTitle != "": jsTrimStart(ast.accTitle) else: "",   # replace(/^\s+/g, '')
    accDescr: if ast.accDescr != "": collapseIndents(ast.accDescr) else: "")
