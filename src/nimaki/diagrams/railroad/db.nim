## port-of: src/diagrams/railroad/db.ts
## port-status: conformant
##
## Port notes: Pele's `RailroadDb` keeps a map from names to rules for `getRule`, which nothing
## in the drawing reads; here the model is the rule list alone.
import std/strutils except unescape
import ../../errors
import types, common, ir, ebnf, abnf, peg
import ../../jsregex

func dropBreakSpaces(text: string): string =
  text.replace(jsre"/\n\s+/g", "\n")

const RE_KEYWORD = jsre"/^\s*railroad-(ebnf-|abnf-|peg-)?beta/i"

proc notationOf*(source: string): (bool, Notation) =
  ## Mermaid has a detector per keyword, each matching without regard to case.
  let m = RE_KEYWORD.exec(source)
  if not m.found: return (false, "")
  let infix = m[1].toLowerAscii
  (true, if infix == "ebnf-": "ebnf" elif infix == "abnf-": "abnf" elif infix == "peg-": "peg" else: "railroad")

proc grammar(source: string, notation: Notation): (Grammar, seq[RailroadRule]) =
  case notation
  of "ebnf":
    let ast = parseEbnf(source)
    (ast, ebnfRules(ast))
  of "abnf":
    let ast = parseAbnf(source)
    (ast, abnfRules(ast))
  of "peg":
    let ast = parsePeg(source)
    (ast, pegRules(ast))
  else:
    let ast = parseIr(source)
    (ast, irRules(ast))

proc populate*(db: RailroadModel, source: string, notation: Notation) =
  ## Parses the text in one notation and loads the result into the model, as Mermaid's four parsers do.
  let (ast, rules) = grammar(source, notation)
  db.notation = notation
  if ast.accDescr != "": db.accDescr = dropBreakSpaces(ast.accDescr)
  if ast.accTitle != "": db.accTitle = ast.accTitle.replace(jsre"/^\s+/g", "")
  if ast.title != "": db.title = ast.title
  for rule in rules: db.rules.add rule

proc parseRailroad*(source: string, title: string): RailroadModel =
  let (found, notation) = notationOf(source)
  if not found: raise newPeleError("No railroad diagram keyword found.", "syntax", "railroad")
  result = RailroadModel(notation: "railroad")
  if title != "": result.title = title
  populate(result, source, notation)
